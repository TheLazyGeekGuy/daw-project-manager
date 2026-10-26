# Project inspection, recovery and inter-DAW conversion

Status, **2026-10-26**: integrated DPM implementation with observed local tests
and explicitly limited fidelity. This directory also tracks the native music
Releases module. The [backlog](BACKLOG.md) separates implemented behavior,
measured evidence and remaining acceptance gates.

The requested product target is **DAW Project Manager on macOS Apple Silicon,
macOS Intel and Windows**, using shared Dart/Flutter engines and UI. Linux is
the current development/test host; local passes do not establish acceptance on
those three desktop targets. No separate Mac utility is required. “Releases”
refers to the music-management module, not GitHub Release publishing.

## Current capability and evidence

| Area | Implemented and observed | Limit |
|---|---|---|
| Inspection | Project-detail and file-picker entry points; bounded structural reports, declared plug-in identity evidence and optional passive local inventory. | Plug-in installation/licence/loadability and native DAW behavior are not certified. |
| CPR preservation | Outer-container/top-level chunk reconstruction passed exact SHA-256 equality for seven official Cubase 12–15 projects, retaining opaque payloads. | No modified CPR writer, reference rebasing, preset translation or native Cubase reopen verification. |
| Native ALL recovery | Attributed MIT AllToMidi Dart port, consent, verified backup, new MIDI/report output and visible unverified/partial counts; synthetic supported layouts pass. | Real TABSAX.ALL is an unsupported negative sample. No positive real-song compatibility, ARR decoder or full-session recovery claim. |
| External conversion | Opt-in DawVert adapter and explicit pipelines of up to three steps. Real RPP → DAWproject → RPP retained a generated fixture's source and WAV hashes. | A media-byte check is not mix/render, preset, routing or automation equivalence; ProjectConverter remains manual. |
| Native Releases | Catalog/workspace forms and local CRUD, assets, rights, deliveries, promotion calendar, tasks, profile stores and backup/Drive metadata integration. | External statuses remain manual; no music-platform publication or global multi-document transaction. |

Focused analysis/unit/widget checks and the real-file/converter observations
are recorded in the linked documents. **The whole Flutter suite passed with
4,744 tests passed and 12 skipped**, and the 14 Python tool tests passed. The
broad Dart analyzer found 0 errors, 0 warnings and 91 informational findings.
Native platform builds/smoke tests remain pending. Branch CI stays main-only;
no merge or software release publication is implied.

## Implementation and evidence documents

- [Validation record, 2026-10-26](validation-2026-10-26.md) — actual commands, observed results and limits.
- [Backlog and acceptance state](BACKLOG.md) — current tasks, evidence and open gates.
- [Inspection](inspection.md) — UI/CLI report, passive inventory and preservation boundaries.
- [Conversion execution](conversion-execution.md) — native ALL engine, DawVert pipeline, validation and measured converter result.
- [DawVert quick start](dawvert-bridge.md) — user-selected external runtime and entry command.
- [Sources and CPR corpus](sources-and-corpus.md) — official demo provenance, seven reconstruction hashes and bounded opt-in downloader.
- [Legacy Cubase](legacy-cubase.md) — historical ALL/ARR → CPR procedure, loss and licence limits.
- [Legacy assistant and corpus CLI](legacy-cubase-and-demo-corpus.md) — manual workflow and corpus inspection command.
- [Reverse-engineering scope](legacy-reverse-engineering.md) — shared DPM decoder research and limits of binary evidence.
- [Native Releases domain](releases-domain.md) — music catalog, forms and workflow integration.
- [Release persistence](release-persistence.md) — profiles, schema migration, revisions and interrupted-write recovery.
- [Release validation and transfer](release-validation.md) — integrity checks, tasks/calendar, backup and Drive merge rules.

## Requirements and future gates

The [requirements](requirements.md), [architecture](architecture.md),
[interoperability matrix](interoperability.md) and [delivery plan](delivery-plan.md)
include broader goals. Their presence does not mean those features are enabled.
Modified CPR repair, plug-in replacement with retained presets, automation and
routing translation, arbitrary native-format conversion and audio/render parity
need their own implementation, corpus and native-DAW evidence. Direct routes
are preferred when their observed fidelity warrants them; DAWproject is not a
mandatory intermediate.

Original project files remain unchanged by DPM's recovery/export actions, and
verified backups precede output generation. Unknown/lost information stays
visible. A structurally valid file or matching count alone is insufficient for
a lossless-conversion claim.

Source roles, version pins and licensing boundaries are collected in
[Conversion execution](conversion-execution.md#source-roles-and-licensing) and
[Sources and corpus](sources-and-corpus.md#source-roles). The native AllToMidi
port is attributed under MIT; external DawVert is separately user-installed.
Research readers/writers and converter documentation do not establish modern
CPR editing safety or authorize automatic third-party software installation.
