#!/usr/bin/env python3
"""Fetch only CPR members of the official Cubase demos using HTTP byte ranges.

Python 3.10+ standard library only. This is an opt-in development tool: it does
not run from DPM or CI, install software, execute projects, or download audio.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
from typing import BinaryIO
import urllib.parse
import urllib.request
import zipfile


MIB = 1024 * 1024
MAX_MEMBER_BYTES = 64 * MIB
MAX_TOTAL_BYTES = 128 * MIB
MAX_READ_BYTES = 16 * MIB
MAX_ENTRIES = 100_000
ALLOWED_HOST = "download.steinberg.net"


def official_url(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != "https" or parts.hostname != ALLOWED_HOST
            or parts.port not in (None, 443) or parts.username is not None
            or parts.password is not None or parts.fragment):
        raise ValueError("Only official HTTPS Steinberg download URLs are allowed")
    return url


class OfficialRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        official_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class HTTPRangeFile(io.RawIOBase):
    """Bounded, seekable remote file; an ignored Range request is a hard error."""

    def __init__(self, url: str):
        super().__init__()
        self.url = official_url(url)
        self.position = 0
        self.downloaded = 0
        self.opener = urllib.request.build_opener(OfficialRedirectHandler())
        headers = {"Accept-Encoding": "identity", "User-Agent": "DPM-corpus/1"}
        self.headers = headers
        request = urllib.request.Request(self.url, headers=headers, method="HEAD")
        with self.opener.open(request, timeout=30) as response:
            self.size = int(response.headers.get("Content-Length", "0"))
            self.etag = response.headers.get("ETag")
            self.last_modified = response.headers.get("Last-Modified")
        if self.size <= 0:
            raise ValueError("Archive size unavailable; no full-download fallback")

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        positions = {io.SEEK_SET: offset, io.SEEK_CUR: self.position + offset,
                     io.SEEK_END: self.size + offset}
        if whence not in positions or positions[whence] < 0:
            raise ValueError("Invalid remote archive seek")
        self.position = positions[whence]
        return self.position

    def read(self, size: int = -1) -> bytes:
        size = min(self.size - self.position, size if size >= 0 else self.size)
        if size <= 0:
            return b""
        if size > MAX_READ_BYTES or self.downloaded + size > MAX_TOTAL_BYTES:
            raise ValueError("Archive read exceeds the transfer budget")
        start, end = self.position, self.position + size - 1
        headers = dict(self.headers, Range=f"bytes={start}-{end}")
        validator = self.etag if self.etag and not self.etag.startswith("W/") else self.last_modified
        if validator:
            headers["If-Range"] = validator
        request = urllib.request.Request(self.url, headers=headers)
        with self.opener.open(request, timeout=30) as response:
            expected = f"bytes {start}-{end}/{self.size}"
            if response.status != 206 or response.headers.get("Content-Range") != expected:
                raise ValueError("Server ignored Range or archive changed during retrieval")
            if self.etag and response.headers.get("ETag") != self.etag:
                raise ValueError("Archive ETag changed during retrieval")
            data = response.read(size + 1)
        if len(data) != size:
            raise ValueError("Incomplete or oversized HTTP range response")
        self.position += size
        self.downloaded += size
        return data


def cpr_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    entries = archive.infolist()
    if len(entries) > MAX_ENTRIES:
        raise ValueError("Too many ZIP entries")
    members: list[zipfile.ZipInfo] = []
    total = 0
    for entry in entries:
        path = PurePosixPath(entry.filename)
        if (entry.is_dir() or path.suffix.lower() != ".cpr"
                or "__MACOSX" in path.parts or path.name.startswith("._")):
            continue
        if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                or "\0" in entry.filename or ":" in entry.filename):
            raise ValueError("Unsafe CPR member path")
        mode = entry.external_attr >> 16
        if stat.S_ISLNK(mode):
            raise ValueError("Symbolic links are not CPR files")
        if entry.flag_bits & 1:
            raise ValueError("Encrypted ZIP members are unsupported")
        if entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise ValueError("Unsupported CPR compression method")
        if not 0 < entry.file_size <= MAX_MEMBER_BYTES:
            raise ValueError("CPR member exceeds the size limit")
        if entry.file_size > max(entry.compress_size, 1) * 1000:
            raise ValueError("CPR compression ratio exceeds the limit")
        total += entry.file_size
        if total > MAX_TOTAL_BYTES:
            raise ValueError("Uncompressed CPR total exceeds the size limit")
        members.append(entry)
    if not members:
        raise ValueError("No CPR members found")
    return members


def _safe_name(member: str) -> str:
    basename = PurePosixPath(member).name
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", basename)[:160]
    key = hashlib.sha256(member.encode("utf-8")).hexdigest()[:12]
    return f"{key}_{stem}"


def extract_member(archive: zipfile.ZipFile, entry: zipfile.ZipInfo, target: Path,
                   expected_sha256: str | None = None) -> dict:
    """Verify CRC while streaming, hash, and publish exclusively without overwrite."""
    if target.is_symlink():
        raise ValueError("Corpus destination must not be a symbolic link")
    target.mkdir(parents=True, exist_ok=True)
    destination = target / _safe_name(entry.filename)
    digest = hashlib.sha256()
    count = 0
    prefix = b""
    fd, temporary = tempfile.mkstemp(prefix=".cpr-", suffix=".part", dir=target)
    try:
        with os.fdopen(fd, "wb") as output, archive.open(entry) as source:
            while chunk := source.read(MIB):
                count += len(chunk)
                if count > entry.file_size or count > MAX_MEMBER_BYTES:
                    raise ValueError("CPR expands beyond its declared size")
                if not prefix:
                    prefix = chunk[:16]
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        if count != entry.file_size:
            raise ValueError("CPR size mismatch")
        sha256 = digest.hexdigest()
        if expected_sha256 is not None and sha256 != expected_sha256:
            raise ValueError("CPR SHA-256 differs from the pinned corpus manifest")
        try:
            os.link(temporary, destination)
        except FileExistsError:
            if destination.is_symlink() or not destination.is_file():
                raise ValueError("Existing destination is not a regular CPR file") from None
            with destination.open("rb") as existing:
                old = _file_sha256(existing)
            if old != sha256:
                raise ValueError("Existing CPR differs; refusing to overwrite") from None
        return {"archiveMember": entry.filename, "localPath": str(destination),
                "bytes": count, "sha256": sha256, "crc32": f"{entry.CRC:08x}",
                "headerHex": prefix.hex()}
    finally:
        os.unlink(temporary)


def _file_sha256(source: BinaryIO) -> str:
    digest = hashlib.sha256()
    while chunk := source.read(MIB):
        digest.update(chunk)
    return digest.hexdigest()


def fetch_one(spec: dict, output: Path) -> dict:
    identifier = spec["id"]
    if not re.fullmatch(r"[a-z0-9-]+", identifier):
        raise ValueError("Invalid corpus identifier")
    with HTTPRangeFile(spec["url"]) as remote, zipfile.ZipFile(remote) as archive:
        members = cpr_members(archive)
        pins = {entry["archiveMember"]: entry["sha256"] for entry in spec.get("projects", [])}
        if pins and set(pins) != {entry.filename for entry in members}:
            raise ValueError("CPR member list differs from the pinned corpus manifest")
        files = [extract_member(archive, entry, output / identifier,
                                expected_sha256=pins.get(entry.filename)) for entry in members]
        return {**spec, "archiveBytes": remote.size, "downloadedBytes": remote.downloaded,
                "etag": remote.etag, "lastModified": remote.last_modified,
                "retrievedAt": datetime.now(timezone.utc).isoformat(),
                "pinnedProjectHashesVerified": bool(pins),
                "files": files, "verification": "CRC32 and SHA-256 of extracted bytes; no DAW reopening"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("cubase_corpus.json"))
    parser.add_argument("--output", type=Path, required=True, help="Directory outside the repository")
    parser.add_argument("--id", action="append", help="Manifest ID; repeat to select multiple archives")
    parser.add_argument("--list", action="store_true", help="Show configured archives without downloading")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    archives = manifest["archives"]
    if args.id:
        unknown = set(args.id) - {entry["id"] for entry in archives}
        if unknown:
            parser.error(f"Unknown corpus IDs: {', '.join(sorted(unknown))}")
        archives = [entry for entry in archives if entry["id"] in args.id]
    if args.list:
        print(json.dumps(archives, indent=2))
        return 0
    output = args.output.resolve()
    repo_root = Path(__file__).resolve().parents[2]
    if output == repo_root or repo_root in output.parents:
        parser.error("Corpus must be outside the repository; copyrighted demos must not be committed")
    output.mkdir(parents=True, exist_ok=True)
    results = []
    failed = False
    for spec in archives:
        try:
            result = fetch_one(spec, output)
        except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
            failed = True
            result = {"id": spec["id"], "url": spec["url"], "error": str(error)}
        results.append(result)
        print(json.dumps(result), flush=True)
    # Each run receives a separate manifest; previous evidence is never replaced.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix="corpus-",
                                     suffix=".json", dir=output, delete=False) as report:
        json.dump({"schemaVersion": 1, "archives": results}, report, indent=2)
        print(f"Manifest: {report.name}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
