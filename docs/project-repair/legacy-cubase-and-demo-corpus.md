# Legacy Cubase and official demo corpus

Current evidence: [Sources and corpus](sources-and-corpus.md) records the seven
official CPR files and their observed byte-identical unchanged reconstruction.
[Conversion execution](conversion-execution.md) describes the integrated native
ALL MIDI recovery engine, synthetic positive tests and unsupported real TABSAX
sample. The manual legacy import workflow below remains a separate route.

## Classic Cubase .ALL/.ARR → .CPR

Official guide:
https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format

Steinberg confirms that **Cubase SE 3, SL 3 and SX 3** are the final
applications that import original Cubase VST songs/arrangements. **SE 3**
is Steinberg's preferred bridge where available and licensed.
These are 2004-era applications. They require supported old operating
systems and compatible licenses; using them on current computers is not
guaranteed. The original macOS releases target PowerPC, not Apple silicon.

Workflow:

1. Keep the original `.ALL` or `.ARR` file unchanged. Use the DPM
   **Legacy Cubase .ALL/.ARR** assistant to create a verified SHA-256
   backup before opening the legacy source externally.
2. In a compatible licensed Cubase SE/SL/SX 3 instance, choose
   **File → Import → Cubase Song**, then select the classic song.
3. Save as a `.CPR` into a new folder. Prefer **Save Project to New
   Folder** so Steinberg collects referenced audio.
4. Select the resulting CPR in DPM to run read-only structure and dependency
   inspection. Check that the saved Cubase version can be identified.
5. Open the result in the target Cubase version. Compare tracks, event
   positions, audio files, VST instruments, mixer channels, plug-in presets,
   automation and routing. Record unsupported or missing items manually.

**The official import is explicitly lossy.** Steinberg states audio and
MIDI tracks/parts retain sample-level timing, but used VST effects and
instruments plus mixer settings are lost. Neither this legacy bridge nor
DPM's CPR inspector can reconstruct unsupported lost VST states.

This manual bridge relies on Steinberg's importer and existing usable licences;
DPM does not circumvent those licence checks. Separately, the native Dart
recovery engine decodes selected ALL MIDI layouts, with no ARR/full-session
claim. Do not claim lossless conversion solely because a resulting CPR opens.

## Versioned modern .CPR demo corpus

The official directory:
https://www.steinberg.net/cubase/demo-projects/

The versioned source manifest is:
[`cubase-demo-corpus.json`](cubase-demo-corpus.json)

The manifest references public Steinberg ZIP archives for Cubase **12,
13, 14 and 15**, including two distinct Cubase 12 example productions.
It contains **no downloaded ZIP files, CPR binaries, plug-ins or music**.
All downloads must be initiated manually, under Steinberg's terms. Demo
packages can be large, so DPM does not download them silently.

Extract the archives into separate version-named folders. Verify each
resulting `.cpr` with the read-only DPM corpus CLI:

```sh
dart run bin/project_repair_corpus.dart "/path/to/extracted-demos" \
  --output "/path/to/cubase-corpus-report.json"
```

The report records: SHA-256, actual saved app version, track count,
top-level CPR chunks and ARCH blocks, plug-in names and **declared** UID
records. A demo ZIP advertised for Cubase 15 does not guarantee every CPR
inside was saved with that exact major version; record the detected value.

Next required test layers per *actual* installed Cubase version:

- **Structural**: safe bounded parse, version identification and
  top-level chunk handling; malformed/truncated/adversarial cases.
- **Unchanged reconstruction**: implemented for outer/top-level CPR framing
  with opaque payloads retained; seven official Cubase 12–15 projects passed
  exact hash equality. Broader versions, reference-aware edits and native
  reopening remain separate gates; see [the results](sources-and-corpus.md#recorded-container-round-trip-result).
- **Semantic**: note timing, clips, channels, plug-in IDs and states,
  FX chains, automation, buses and side-chain graphs (not implemented).
- **Native DAW**: Cubase reopen and playback/render parity (requires
  licensed application plus plug-ins and user testing).
- **Release regression**: record exact fixture hash plus version; rerun
  with changes, never redistribute Steinberg content automatically.

Existing older public CPR specimen: Cubase 10.5.20 Windows x64,
`MSDS`, SHA-256
`03819e64419d25045de04ea6ea0e18ec048e4c869c426f076218465b84b7141b`.
It has 14 top-level chunks and seven ARCH blocks. UID attributes must be
interpreted as serialized evidence, not a plug-in identity certification.

## Open-source converters and their actual scope

| Tool | License | Verified advertised scope | Use in DPM |
|---|---|---|---|
| [Bitwig DAWproject](https://github.com/bitwig/dawproject) | MIT | DAWproject exchange data models and serialization | Optional canonical interchange schema |
| [RoEx dawproject-py](https://github.com/roex-audio/dawproject-py) | MIT | Read/write/validate DAWproject ZIP and XML; track/notes/automation models | Optional Python library, not a CPR reader |
| [ProjectConverter](https://github.com/git-moss/ProjectConverter) | LGPL-3.0 | REAPER ↔ DAWproject, including VST2/VST3/CLAP state within documented limits | Optional operator-driven converter; no documented Cubase legacy importer |
| [DawVert](https://github.com/DawVert/DawVert) | GPL-3.0-or-later | Multiple input/output plug-ins, platform/version-dependent fidelity | Optional local CLI bridge; no native CPR writer promised |

ProjectConverter's manual lists notable omissions: AU, parameter
automations for VST/MIDI, complex routing, continuous tempo and some nested
clips. These limitations must remain visible in DPM capability reports.

DAWproject should be used **only when a given route provides enough fidelity**.
A verified direct transformation may preserve more than an intermediate
DAWproject export.

For a current format matrix, recording corpus results is the first step:
source code and public demonstrations alone cannot verify native DAW
application reopening or audio fidelity.
