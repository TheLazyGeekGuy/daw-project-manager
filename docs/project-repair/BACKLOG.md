# Implementation backlog

GitHub Issues are **disabled on this fork** (GitHub API HTTP 410). These are tracked specifications, **not issue URLs**. Enable Settings → General → Features → Issues to migrate them to native issues.

| ID | Milestone | Ticket | Traceability | Status |
|---|---|---|---|---|
| TASK-001 | M1 | Flutter dependency-inspection interface | INSP-002 | Partial: widget/dialog implemented, navigation wiring pending |
| TASK-002 | M1 | Format registry signature and version hardening | INSP-001 | In progress |
| TASK-003 | M2 | Structural CPR reader, no-op roundtrip | QUAL-001 | Planned |
| TASK-004 | M2 | Versioned licensed test corpus and semantic diff | QUAL-002 | Planned |
| TASK-005 | M3 | Installed VST2/VST3/AU/CLAP registry | INSP-004 | Partial: bounded static scan; IDs and validation pending |
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
