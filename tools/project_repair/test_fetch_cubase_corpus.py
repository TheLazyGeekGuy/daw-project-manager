"""Offline regression tests for bounded external corpus retrieval."""

import io
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from fetch_cubase_corpus import (
    HTTPRangeFile,
    MAX_READ_BYTES,
    cpr_members,
    extract_member,
    official_url,
)


URL = "https://download.steinberg.net/test.zip"


class Response(io.BytesIO):
    def __init__(self, body=b"", status=200, headers=None):
        super().__init__(body)
        self.status = status
        self.headers = headers or {}


def make_archive(name="project/test.cpr", body=b"RIFF0000NUNDROOTpayload"):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(name, body)
        archive.writestr("project/Audio/track.wav", b"not downloaded")
        archive.writestr("__MACOSX/project/._test.cpr", b"resource fork")
    buffer.seek(0)
    return zipfile.ZipFile(buffer)


class HTTPRangeTests(unittest.TestCase):
    def test_only_official_https_urls(self):
        self.assertEqual(official_url(URL), URL)
        for url in ("http://download.steinberg.net/test.zip",
                    "https://download.steinberg.net.evil.example/test.zip",
                    "https://user@download.steinberg.net/test.zip",
                    "https://download.steinberg.net:123/test.zip",
                    "file:///tmp/archive.zip"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                official_url(url)

    @patch("fetch_cubase_corpus.urllib.request.build_opener")
    def test_reads_only_requested_range(self, build):
        build.return_value.open.side_effect = [
            Response(headers={"Content-Length": "12", "ETag": '"a"'}),
            Response(b"ROOT", 206, {"Content-Range": "bytes 8-11/12", "ETag": '"a"'}),
        ]
        with HTTPRangeFile(URL) as source:
            source.seek(-4, io.SEEK_END)
            self.assertEqual(source.read(), b"ROOT")
            self.assertEqual(source.downloaded, 4)
            self.assertEqual(source.tell(), 12)
        request = build.return_value.open.call_args.args[0]
        self.assertEqual(request.headers["Range"], "bytes=8-11")
        self.assertEqual(request.headers["If-range"], '"a"')

    @patch("fetch_cubase_corpus.urllib.request.build_opener")
    def test_server_ignoring_range_is_rejected_before_read(self, build):
        body = Response(b"archive should not be read", 200)
        build.return_value.open.side_effect = [
            Response(headers={"Content-Length": "1000000000"}), body]
        with HTTPRangeFile(URL) as source, self.assertRaisesRegex(ValueError, "ignored Range"):
            source.read(1)
        self.assertTrue(body.closed)

    @patch("fetch_cubase_corpus.urllib.request.build_opener")
    def test_changed_archive_is_rejected(self, build):
        build.return_value.open.side_effect = [
            Response(headers={"Content-Length": "4", "ETag": '"old"'}),
            Response(b"RIFF", 206, {"Content-Range": "bytes 0-3/4", "ETag": '"new"'}),
        ]
        with HTTPRangeFile(URL) as source, self.assertRaisesRegex(ValueError, "ETag"):
            source.read(4)

    @patch("fetch_cubase_corpus.urllib.request.build_opener")
    def test_oversized_read_never_sends_request(self, build):
        build.return_value.open.return_value = Response(headers={"Content-Length": "1000000000"})
        with HTTPRangeFile(URL) as source, self.assertRaisesRegex(ValueError, "budget"):
            source.read(MAX_READ_BYTES + 1)
        self.assertEqual(build.return_value.open.call_count, 1)


class CorpusTests(unittest.TestCase):
    def test_only_project_members_selected(self):
        with make_archive() as archive:
            self.assertEqual([entry.filename for entry in cpr_members(archive)], ["project/test.cpr"])

    def test_traversal_members_rejected(self):
        for path in ("../bad.cpr", "/bad.cpr", "x/../../bad.cpr", "C:/bad.cpr", "x\\bad.cpr"):
            with self.subTest(path=path), make_archive(path) as archive:
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    cpr_members(archive)

    def test_symlink_member_rejected(self):
        buffer = io.BytesIO()
        info = zipfile.ZipInfo("linked.cpr")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr(info, "other.cpr")
        buffer.seek(0)
        with zipfile.ZipFile(buffer) as archive, self.assertRaisesRegex(ValueError, "Symbolic"):
            cpr_members(archive)

    def test_decompression_budget(self):
        with make_archive() as archive:
            archive.infolist()[0].file_size = 1024 * 1024 * 1024
            with self.assertRaisesRegex(ValueError, "size limit"):
                cpr_members(archive)

    def test_crc_failure_leaves_no_published_file(self):
        with tempfile.TemporaryDirectory() as folder, make_archive() as archive:
            entry = cpr_members(archive)[0]
            entry.CRC ^= 1
            with self.assertRaises(zipfile.BadZipFile):
                extract_member(archive, entry, Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_idempotent_download_preserves_existing_project(self):
        with tempfile.TemporaryDirectory() as folder, make_archive() as archive:
            entry = cpr_members(archive)[0]
            first = extract_member(archive, entry, Path(folder))
            second = extract_member(archive, entry, Path(folder))
            self.assertEqual(first, second)
            destination = Path(first["localPath"])
            self.assertEqual(destination.read_bytes(), b"RIFF0000NUNDROOTpayload")
            self.assertEqual(len(list(Path(folder).iterdir())), 1)

    def test_conflicting_destination_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder, make_archive() as archive:
            entry = cpr_members(archive)[0]
            result = extract_member(archive, entry, Path(folder))
            destination = Path(result["localPath"])
            destination.write_bytes(b"pre-existing different file")
            with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
                extract_member(archive, entry, Path(folder))
            self.assertEqual(destination.read_bytes(), b"pre-existing different file")
            self.assertEqual(len(list(Path(folder).iterdir())), 1)

    def test_manifest_hash_mismatch_leaves_no_file(self):
        with tempfile.TemporaryDirectory() as folder, make_archive() as archive:
            entry = cpr_members(archive)[0]
            with self.assertRaisesRegex(ValueError, "pinned corpus manifest"):
                extract_member(archive, entry, Path(folder), expected_sha256="0" * 64)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_symlink_destination_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder, make_archive() as archive:
            entry = cpr_members(archive)[0]
            real = Path(folder) / "real"
            real.mkdir()
            linked = Path(folder) / "linked"
            try:
                linked.symlink_to(real, target_is_directory=True)
            except OSError:
                self.skipTest("Creating symlinks requires additional OS permissions")
            with self.assertRaisesRegex(ValueError, "symbolic link"):
                extract_member(archive, entry, linked)
            self.assertEqual(list(real.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
