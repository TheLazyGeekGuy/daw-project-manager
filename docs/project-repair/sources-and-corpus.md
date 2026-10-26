# Sources and external CPR validation corpus

Reviewed and first retrieved: **2026-10-26**.

## Source roles

| Source | Confirmed role | Integration boundary |
|---|---|---|
| [Steinberg legacy conversion guide](https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format) | Vendor-supported historical import procedure | Manual bridge with known losses; see [Legacy Cubase](legacy-cubase.md) |
| [Steinberg Cubase demo projects](https://www.steinberg.net/cubase/demo-projects/) | Published project packages for real-file validation | External corpus, not a redistributable fixture license |
| [bitwig/dawproject](https://github.com/bitwig/dawproject) | DAWproject specification, XML schemas and reference classes | ZIP/XML interchange reference; does not define CPR internals |
| [roex-audio/DAWproject-py](https://github.com/roex-audio/DAWproject-py) | Python implementation of DAWproject objects and loading/saving | Candidate test tooling; its README does not establish native CPR conversion |
| [git-moss/ProjectConverter](https://github.com/git-moss/ProjectConverter) | REAPER to/from DAWproject conversion | Candidate external converter; validate each direction and object type |

The DAWproject reference describes audio, notes, automation and embedded plug-in states. Its ZIP contains `project.xml` and `metadata.xml`. Its expressive scope does not prove that a given exporting/importing DAW preserves every field. [Format reference](https://github.com/bitwig/dawproject/blob/main/README.md).

ProjectConverter documents VST2, VST3 and CLAP devices with their states, plus track, clip and routing data for its REAPER/DAWproject pair. These are upstream capability claims, not a DPM validation result; its manual also lists unsupported constructs. [Converter manual](https://github.com/git-moss/ProjectConverter/blob/main/README.md).

DAWproject-py's README demonstrates `DawProject.load_project`, ZIP serialization and XML serialization. It is useful for independent interoperability checks; DPM must not infer an ALL/ARR/CPR reader from that API. [Python library README](https://github.com/roex-audio/DAWproject-py/blob/main/README.md).

### Review provenance

The following README blob hashes were read through the GitHub API on the review date. They identify the reviewed document content; they are not release versions or executable version pins.

| Repository | README blob SHA |
|---|---|
| `bitwig/dawproject` | `0c4fa0c5ae954fa5da6df83d1199ab715030d065` |
| `roex-audio/DAWproject-py` | `331ce020a10a08782df845a110835c75d3f7308b` |
| `git-moss/ProjectConverter` | `373826483bf4dcf7e2cb6511d3b0cbe4d49e1f9c` |

## Official Cubase corpus

The [machine-readable manifest](../../tools/project_repair/cubase_corpus.json) records the five supplied download URLs and the hashes of their seven CPR members. Corpus generation is the package label, not a claim about a decoded build number.

| Pack | CPR members | Project bytes | ZIP bytes | Bytes transferred for first retrieval |
|---|---:|---:|---:|---:|
| Cubase 15 — Austin Hull | 1 | 11,190,483 | 92,146,828 | 2,833,468 |
| Cubase 14 — Austin Hull | 1 | 7,964,203 | 92,649,856 | 1,273,241 |
| Cubase 13 — Austin Hull | 1 | 15,347,699 | 125,895,961 | 5,054,813 |
| Cubase 12 — Austin Hull | 2: mixed and unmixed | 21,844,224 | 128,287,376 | 7,344,247 |
| Cubase 12 — Mendel Bij De Leij | 2: mixed and unmixed | 6,949,527 | 1,014,186,401 | 967,735 |
| **Total** | **7** | **63,296,136** | **1,453,166,422** | **17,473,504** |

These are observed byte counts from the retrieval tool. HTTP byte ranges avoid downloading audio and other assets. All seven CPR files had a `RIFF` container marker and `NUNDROOT` at the expected beginning; container interpretation and round-trip validation are separate tests.

### Recorded container round-trip result

The Dart `CubaseLosslessContainer` was run against all seven retrieved CPRs on
2026-10-26. **7/7 passed exact SHA-256 equality** after reconstruction of the
outer container and its chunk framing. The same bytes were retained for every
opaque chunk payload. This check was run locally rather than through a branch
CI workflow.

| Project | Decoded saved Cubase version | Source SHA-256 = reconstructed SHA-256 |
|---|---|---|
| Cubase 12 Austin Hull, mixed | 12.0.0 | `b22b699232970644ef91dc5d6ef89074dabe3a2dab260cb8743d5225c6876a35` |
| Cubase 12 Austin Hull, unmixed | 12.0.0 | `9f817ee2bc9173b13b8dcfdd0bb0922fd9126f60e762a772c8b33a13f7a7f38e` |
| Cubase 12 Mendel Bij De Leij, mixed | 12.0.0 | `6644d45375a601ee94c1af2f6c64b0897c0fb67374ccf9f523cf8b05644b9139` |
| Cubase 12 Mendel Bij De Leij, unmixed | 12.0.0 | `50bdd6d0978da5883b988579842786ac00865ffc46d94874922625b4c57d539a` |
| Cubase 13 Austin Hull | 13.0.0 | `52c1ae0a1ecea55646253ae59fb3f1db0731ec47f05dcd8f0bc68f5e173315c1` |
| Cubase 14 Austin Hull | 14.0.5 | `7b61c5ba3520bff2aba48208b44e835941b6dfaf996599f0533e8556efff65be` |
| Cubase 15 Austin Hull | 15.0.0 | `04bdaed7c2a99797b43628998e360e1935388f6aa2da763e0609075a3a9664c4` |

All reports keep `mutations_enabled: false`, `reference_rebasing: unsupported`,
`plugin_state_translation: unsupported` and `native_daw_reopen: not-run`.
Object-graph completeness is unverified. This evidence meets the byte
preservation prerequisite for these specific inputs; it does not validate track
renaming, plug-in replacement, preset migration or audible equivalence.

### Fetch only the project files

Run from the repository root with Python 3.10 or later:

```bash
python3 tools/project_repair/fetch_cubase_corpus.py --output /tmp/dpm-corpus
```

On Windows, choose a writable directory outside the checkout, for example:

```powershell
py -3 tools/project_repair/fetch_cubase_corpus.py --output C:\Temp\dpm-corpus
```

Select one or several packs with repeatable `--id` arguments:

```bash
python3 tools/project_repair/fetch_cubase_corpus.py \
  --output /tmp/dpm-corpus \
  --id cubase15-austin-hull \
  --id cubase12-mendel-bij-de-leij
```

Add `--list` to print the manifest selection without downloading. The script is opt-in development tooling and is not invoked automatically by DPM or CI.

### Retrieval guarantees

- Only HTTPS downloads from `download.steinberg.net` are accepted, including redirects.
- Each request must return the requested byte range; the tool refuses a full-download fallback.
- ZIP reads, total transfers, individual project sizes, compression ratios and decompressed totals are bounded.
- Path traversal, symbolic links, encrypted entries and unsupported compression methods are rejected. Audio and AppleDouble resource forks are skipped.
- ZIP CRC32 is checked during extraction; SHA-256 must match the pinned project hash before publication.
- A differing existing file is never overwritten. Matching files can be reused on subsequent runs.
- Every run creates its own JSON provenance report with source URL, archive metadata, member paths, sizes and hashes. Subsequent runs do not replace earlier reports.
- The destination must be outside the checkout. The project files and media are not added to this repository.

The SHA-256 pins represent the reviewed downloads. If Steinberg updates a package, investigate the changes and update pins explicitly; do not silently accept a different project as the same test input.

### Offline tool tests

```bash
python3 -m unittest discover -s tools/project_repair -p 'test_*.py' -v
```

The tests exercise byte-range refusal, source-change detection, request budgets, path traversal, symlinks, decompression bounds, CRC failures, hash mismatch, idempotence and overwrite protection. They use synthetic archives and mocked HTTP responses; they do not download demos.

## What this corpus can and cannot establish

Use the extracted CPRs to check bounded parsing, version identification, decoded dependency inventories, preservation of unknown bytes and exact no-op reconstruction. Record each input hash alongside the parser version and test result.

The project-only corpus cannot establish successful media resolution, available instruments, musical fidelity or reopening in Cubase. It deliberately omits media. Functional acceptance requires an appropriately licensed installation, the complete demo package where needed, and explicit checks of tracks, automation, routing, presets and rendered output. A parser round trip must not be promoted to that acceptance level.

The demos do not cover `.ALL`/`.ARR` import, every Cubase edition, every point release, third-party plug-in state layouts or damaged CPRs. Synthetic malformed-input tests and lawfully supplied legacy projects remain necessary complementary evidence.
