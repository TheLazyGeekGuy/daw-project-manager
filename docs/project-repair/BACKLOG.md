# Implementation backlog

GitHub Issues are **disabled on this fork** (GitHub API HTTP 410). These are tracked specifications, **not issue URLs**. Enable Settings → General → Features → Issues to migrate them to native issues.

| ID | Milestone | Ticket | Traceability | Status |
|---|---|---|---|---|
| TASK-001 | M1 | Flutter dependency-inspection interface | INSP-002 | Implemented UI entry point; build and cross-platform validation pending |
| TASK-002 | M1 | Format registry signature and version hardening | INSP-001 | In progress |
| TASK-003 | M2 | Structural CPR reader, no-op roundtrip | QUAL-001 | Planned |
| TASK-004 | M2 | Versioned licensed test corpus and semantic diff | QUAL-002 | Planned |
| TASK-005 | M3 | Installed VST2/VST3/AU/CLAP registry | INSP-004 | Static candidate scan and name-based comparison implemented; UID and load tests pending |
| TASK-006 | M3 | Sandboxed plug-in loadability and licensing checks | PLAT-002 | Planned |
| TASK-007 | M4 | Fail-closed verified backup and safe output publishing | SAFE-001–007 | In progress |
| TASK-008 | M5 | CPR rename/writer with real Cubase reopening | REPR-004 | Blocked by TASK-003 |
| TASK-009 | M6 | Plug-in state archive and migration profiles | REPR-001–005 | Partial: compatibility registry only; no state extraction |
| TASK-010 | M6 | Automation, routing and side-chain mapping | REPR-006–007 | Planned |
| TASK-011 | M7 | Conversion graph and direct/pivot route planner | CONV-001–006 | Partial: evidence-aware path enumeration, no converter execution |
| TASK-012 | M7 | External DawVert and ProjectConverter bridges | SEC-002 | Planned |
| TASK-013 | M8 | Fidelity, semantic and audio render validation | CONV-005 | Planned |
| TASK-014 | M8 | Batch processing and cleanup backup exclusions | SAFE-003 | Planned |
| TASK-015 | Upstream | Maintainer discussion and focused PR sequence | Contribution | Planned |

## Cross-cutting Definition of Done

- English code, comments, tests and documentation.
- Applicable requirements linked in PR.
- Security review of untrusted project and plug-in inputs.
- Automated tests plus observed run on supported platforms; otherwise explicitly marked untested.
- Original files unchanged, verified backups before writing, managed backups excluded from cleanup.
- No unsupported migration described as successful.

## Implementation order

TASK-002 → TASK-001 → TASK-005; TASK-003 + TASK-004 → TASK-008 → TASK-009/TASK-010. TASK-011 → TASK-012 → TASK-013; TASK-007 is a hard prerequisite for any writer.

## Implementation notes (2026-10-26)

Implemented in this branch: read-only inspection CLI, dependency-report Flutter widgets, bounded passive VST/VST3/AU/CLAP filesystem scan, migration-profile data model, conversion route candidate planner, verified backup helper, targeted tests and 3-platform CI workflow. No Flutter build/test result has been observed yet; statuses remain partial until green CI and full app integration. Modern CPR mutation, state migration, DAW reopening and audio validation remain blocked on real native fixtures and installed DAWs.

## Completion gate review (2026-10-26)

The backlog is **not complete**. Implemented components are foundations, not end-to-end outcomes. Explicit blockers for acceptance:

- Native CPR write/migration: lossless serializer for each supported era, pointer/reference rebasing, byte-for-byte identity and successful Cubase reopen with state and automation preservation.
- External DAW conversion: executable adapters, controlled fixture suite, semantic reports and host reopen/render checks.
- Optional plug-in load diagnostics: isolated host workers, licensing/error classification and testing on all supported platforms.
- UI: inspection dialog exists but is not yet invoked from normal project navigation.
- Managed backup: helper exists; file durability, symlink/race protection, cleanup exclusions and rollback workflow must be validated before any writer is enabled.
- All new services require green formatter/analyzer/unit/widget tests on Linux, Windows and macOS.

Never close tasks solely because a data model, placeholder adapter or draft UI exists.

## Native Releases extension backlog

| ID | Feature | Current status | Completion gate |
|---|---|---|---|
| REL-001 | Artists and stable artist credits | Pure Dart domain model | Profile-scoped CRUD, forms and migrations |
| REL-002 | Albums, EPs, singles and playlists | Domain model; existing Release/Playlist still separate | Unified UI and ordering/persistence |
| REL-003 | Track versions and asset lineage | Domain model | File verification, artwork/stem/lyrics UI |
| REL-004 | Musical works and rightsholder shares | Domain model and validation | Editable forms, evidence, ownership review |
| REL-005 | Rights filing across organizations | Domain model | Verified/manual statuses and history |
| REL-006 | Distributor/platform delivery | Domain model | Manual delivery tracking, platform URLs, IDs |
| REL-007 | Promotion campaigns | Domain model | Scheduling forms, assets and coverage views |
| REL-008 | Profile-safe release workspace persistence | JSON snapshot store | Migration, crash recovery, profile boundaries |
| REL-009 | Native release workflow editor | Release type and artist fields plus advanced JSON editor | Remaining dedicated rights/distribution/promotion forms and localization |
| REL-010 | Distribution and rights workflow verification | Advisory validator | Dataset tests, history and real-world workflow review |

These features are independent of Katsu. Its concepts were used as research only; no code connector or Suno account dependency is planned.

## Incremental delivery note (2026-10-26)

- The release-detail editor now exposes collection type and stable artist IDs in native Flutter controls, retaining an advanced JSON mode for still-unimplemented rights, distributor and promotional forms.
- Added widget test covering native input and profile-local JSON store persistence. This test is committed but not yet CI-verified; CI remains disabled on non-main branches by repository policy.
- No external Katsu integration was added. This work reuses only cross-platform music-industry concepts.
