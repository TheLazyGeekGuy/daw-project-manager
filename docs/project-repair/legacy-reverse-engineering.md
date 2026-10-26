# Legacy Cubase format research for integrated DPM conversion

Status: **research and bounded native-reader development**. Reviewed 2026-10-26.

## Product target

The intended delivery is a shared Dart conversion engine **inside DAW Project
Manager**, with the same workflow on:

| DPM target | Required acceptance |
|---|---|
| macOS Apple Silicon, including M4 | Native ARM64 build, file selection, inspection, safe conversion and report |
| macOS Intel | Native x86-64 build with the same parser and expected results |
| Windows | Native DPM build with the same parser and expected results |

This is not a separate Mac-only converter or a requirement to install a second
Windows application. Parser development and synthetic tests on Linux are useful
additional evidence, but they do not replace the three product smoke tests.

The existing `LegacyAllMidiDecoder` is the shared Dart baseline derived from
[OnjLouis/AllToMidi](https://github.com/OnjLouis/AllToMidi), with attribution to
the reviewed MIT source. It targets the ALL record patterns its reader
understands. Its presence does not prove coverage of Atari ARR, all ALL
generations, audio arrangements, VST states or direct CPR serialization.

The distinction between **Cubase 3.x** and **Cubase SE/SL/SX 3** matters: the
latter products' importers are reference candidates for understanding earlier
song formats. An installer name is not evidence that every historical file
shares one layout.

## Official reference candidates

The [Steinberg conversion article](https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format)
links these legacy packages:

| Candidate | Official package |
|---|---|
| SE 3.0.3 Windows | [ZIP installer](https://download.steinberg.net/downloads_legacy/Cubase_VST_Song_Conversion/Cubase_SE_3.0.3_Installer_win.zip) |
| SE 3.0.2 Mac | [DMG installer](https://download.steinberg.net/downloads_legacy/Cubase_VST_Song_Conversion/Cubase_SE_3.0.2_Installer_mac.dmg) |
| SX 3.1 Windows | [ZIP installer](https://download.steinberg.net/downloads_legacy/Cubase_VST_Song_Conversion/Cubase_SX_3.1_CD_Installer_win.zip) |
| SX 3.1 Mac | [DMG installer](https://download.steinberg.net/downloads_legacy/Cubase_VST_Song_Conversion/Cubase_SX_3.1_CD_Installer_mac.dmg) |

Treat these as static analysis inputs. Reading an archive directory or a binary
header does not require launching the legacy program on an M4. Running an
importer for reference output is a separate optional validation activity on a
compatible licensed installation; [legacy-cubase.md](legacy-cubase.md) records
that manual route and its known losses.

### Initial static observation

The SE 3.0.3 Windows ZIP directory was inspected with HTTP byte ranges. Its
observed size was **190,373,504 bytes**; 4,609 bytes were sufficient to read its
directory. `Cubase_SE_3_03_Installer/Setup.exe` is listed as 48,752,252 bytes.
Only its first **65,536 bytes** were read for the following observations:

| Observation | Result |
|---|---|
| DOS header | `MZ` |
| PE header file offset | `0xD0` / 208 |
| PE signature | `50 45 00 00` |
| COFF Machine | `0x014C` |
| Optional-header magic | `0x010B` |
| SHA-256 of the 65,536-byte prefix | `911593402a66010f8aa543d5bbb5866f88da6f0a9bfd93c72f8196728a53a3dc` |
| Archive ETag | `7559b5a6f63b11902358844e7b33bbf3-23` |

This identifies the inspected installer prefix as PE32/x86; it does not identify
the architecture of every bundled component or locate the song parser. The
installer was not executed, unpacked fully or decompiled. Its full-file hash is
not claimed. The Mac SE package's HTTP length was 81,125,358 bytes; its inner
executable was not inspected.

The machine/magic interpretation follows Microsoft's
[PE/COFF specification](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).

## Research sequence

1. **Freeze provenance.** Record official URL, package version, retrieved size,
   full-file hash when available, archive member path and executable hash. Keep
   source binaries outside the DPM repository. Distinguish the executable's
   build from the source song's generating version.
2. **Inventory without execution.** Examine archive membership, executable
   architecture, resources, imports, strings, class names and diagnostic text.
   Locate candidate ALL/ARR import routines by cross-referencing format names,
   record tags and error messages. A matching string is a lead, not a decoded
   field definition.
3. **Trace parser decisions.** Document each branch's signature, byte order,
   lengths, pointer interpretation, record ownership and bounds. Separate
   arrangement, tempo, controller, SysEx, audio-reference and plug-in-state
   records. Record byte offsets and function references for the specific build.
4. **Correlate with specimens.** Compare the inferred layout with public demo
   files and lawfully supplied projects. Use minimal pairs with one changed
   property when a compatible reference host is available. Do not generalize a
   single file's offsets to all Cubase versions.
5. **Implement format facts in Dart.** Add bounded readers and explicit variant
   identification to DPM. Retain unknown records as evidence, report unsupported
   features and reject ambiguous layouts. Publish independently written format
   documentation and tests rather than bundling proprietary executables.
6. **Verify musical semantics.** Compare decoded tracks, absolute event times,
   note durations, channels, tempo/signature changes, controller data and SysEx
   payloads with independent reference output. Export MIDI or DAWproject only
   for supported data. A structurally valid output is not sufficient evidence
   of the intended song.
7. **Run platform smoke tests.** Open a source from DPM on all three targets,
   review diagnostics, convert to a new location and verify source hashes,
   output metadata and user-visible failure behavior. Keep actual test status
   per platform rather than inferring all platforms from the shared language.

## Evidence record for each inferred field

| Field | Required evidence |
|---|---|
| Variant identity | Candidate signatures and explicit negative cases |
| Source identity | Song SHA-256, source provenance, known or unknown host version |
| Binary reference | Package/executable hash, routine address and relevant file offset |
| Interpretation | Byte order, width, units, scaling, ownership and limits |
| Confidence | Observed, independently reproduced, inferred or unknown |
| Positive cases | Public or permitted corpus entries that exercise the field |
| Negative cases | Truncation, overflow, conflicting references and other variants |
| Musical comparison | Reference host/export, comparator version and unresolved differences |

Never promote an inferred version or event unit to verified simply because an
exporter produced a file. Preserve separate states for parser acceptance,
container validity, event equivalence and target-DAW reopening.

## Current external negative fixture

`TABSAX.ALL` was publicly supplied by its author for diagnosis in
[this Steinberg forum thread, post 7](https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292/7).
The sample is 23,826 bytes, SHA-256
`3e21a5946814d5b8b999f3ade02530ca55f3e852d4940e4b6d7654e1ea717daf`.
Its generating Cubase version is unknown. No paired reference MIDI was supplied.

The current AllToMidi-pattern reader finds no matching track records, and the
same predicate from upstream finds no candidates. This is evidence of an
**unsupported ALL variant**, not proof that the sample is corrupted. Keep it as
an external negative fixture for honest rejection until its format is decoded.
The author's report of opening it in SX3 has not been independently reproduced.

The public atari2cubase demo is a further source of interoperability observations,
not an assumed licensed dependency. Its reported support and output must be
verified against concrete files before it informs a DPM capability claim.

Its public demo action references
[`MANILOVE.ARR`](https://atari2cubase.robert-068.workers.dev/MANILOVE.ARR?v=0.31),
which was retrieved as an external specimen: 86,800 bytes, SHA-256
`a46e16ab120746f0e5e8df70b55adf94a0ddef566c7935fec27a0588d88234f0`.
It is an ARR specimen, not a positive AllToMidi ALL fixture. No independent
reference MIDI or exact generating Cubase version was supplied. Neither song
file is committed to DPM.
