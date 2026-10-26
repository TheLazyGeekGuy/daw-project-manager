# Delivery plan and contribution strategy

Status: **proposal**, no implementation claimed.

## Incremental milestones

| Milestone | Deliverable | Exit gate |
|---|---|---|
| M0 | Requirements, architecture, format/capability matrix, license review | Upstream discussion and maintainers' feedback |
| M1 | Read-only format detection and plug-in inventory in Flutter | CI and fixture tests; duplicate names preserved |
| M2 | Independent CPR extractor comparison (CubaseTools/MyDAW/cpr2rpp) | Real CPR corpus; explicit unknown fields |
| M3 | Installed VST2/VST3/AU/CLAP inventory and broken-plugin diagnosis | Static/dynamic status separated; platform tests |
| M4 | Mandatory verified backups and staging output infrastructure | Fault injection, restore tests, original byte invariant |
| M5 | CPR no-op roundtrip / safe track rename on supported versions only | Byte-identical no-op and reopen in Cubase |
| M6 | Versioned VST2→VST3 replacement profiles, automation matching | Preset/reopen testing on approved plugin pairs |
| M7 | Adapter orchestrator, DawVert optional integration, direct routes | Direction/version-specific fidelity reports |
| M8 | Batch repair/conversion, semantic diff and reports | Corpus regression + adversarial input tests |

## Upstream PR sequence

1. Add format registry, structured read-only metadata and tests.
2. Add project dependency/plug-in inspection UI, with graceful unsupported statuses.
3. Add backup/reporting infrastructure (no CPR writer enabled yet).
4. Add optional external converter API with capability declarations.
5. Add experimental CPR repair UI only after the writer validation gates pass.

Separate engines should expose stable versioned JSON/CLI (or FFI) contracts. The host should not require DawVert, Python or external binary downloads merely to launch.

## Test corpus

- A public Cubase 10.5.20 Windows x64 CPR specimen: [MSDS](https://github.com/smadgerano/MSDS).
- Additional licensed fixtures for Cubase 5, 10, 11, 12, 13, 14, 15; both Windows and macOS when possible.
- Synthetic fixtures with duplicate track names, missing audio assets, inactive VST2, mixed VST2/VST3, automation, bus sends, side-chains, plugin state blobs, varied tempo maps, and malformed/truncated input.
- ALS, FLP, RPP, LOGICX, LMMS and DAWproject controlled sessions with semantically matching timelines.

Public fixtures are NOT evidence of full-format support. Secure explicit permission to redistribute third-party test sessions.

## Testing layers

- **Layer 0:** syntax/signatures/size validation, bounded parsing, fuzzing.
- **Layer 1:** identity parse/serialize: byte-for-byte equality on supported CPR versions.
- **Layer 2:** structural semantic diff of clips, tracks, inserts, UID, automations and routing.
- **Layer 3:** reopen actual project in the native target DAW.
- **Layer 4:** preset/automation interaction and audio render comparison where technically feasible.

No feature is called safe to write until it passes the appropriate layers on supported application versions.

## External components and license gates

- DAW Project Manager: MIT host.
- CubaseTools and bravoh-daw: MIT candidates.
- DawVert: GPL-3.0; require packaging/distribution compatibility review and independently selectable installation.
- MyDAW, cpr2rpp and other source candidates: verify license and per-commit provenance before copying code.

## Contribution etiquette

Open an upstream issue with requirements and a small PR proposal. Keep English documentation/comments, tests and changelog. Prefer opt-in features. Avoid modifying upstream core project database semantics without maintainers' review. No automatic PR or merge without explicit implementation review.
