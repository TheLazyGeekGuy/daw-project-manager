# Implementation backlog and observed delivery state

Updated: **2026-10-26**. These are repository-local task identifiers and tracked
acceptance criteria, not GitHub issue URLs. The initial fork API reported Issues
disabled; no issue was created merely by adding a row here.

The current implementation is integrated into **DAW Project Manager**. The
requested desktop targets are **macOS Apple Silicon, macOS Intel and Windows**,
using shared Dart/Flutter code. Local development and the observed automated
checks below ran on Linux; they do not replace native builds and smoke tests on
those three targets. This work does not require a separate Mac recovery app.

**Releases** below means DPM's music catalog and release-management module.
It does not mean publishing a GitHub Release. No software release publication,
merge to `main`, or automatic upload to a music platform is part of this change.
Branch CI remains **main-only** as requested. Local tests are run independently
of that trigger policy.

## Inspection, recovery and conversion

| ID | Milestone | Task | Traceability | Implemented state and remaining gate |
|---|---|---|---|---|
| TASK-001 | M1 | Flutter dependency-inspection interface | INSP-002 | Integrated project-detail action and direct project-file picker within DPM; native recovery, preservation and passive-scan controls, localization and focused widget tests. Native platform acceptance remains. |
| TASK-002 | M1 | Format signatures and version hardening | INSP-001 | Bounded RIFF/NUND framing, saved-version evidence, DAWproject ZIP/XML and MIDI preflight. Detection of legacy ALL/ARR by extension is only a hint. Wider version/variant corpus remains. |
| TASK-003 | M2 | CPR structural reader and unchanged reconstruction | QUAL-001 | Top-level framing reconstructed with opaque payloads retained; all seven official Cubase 12–15 CPRs passed exact SHA-256 equality. Object graph, reference rebasing and modified serialization are unverified. |
| TASK-004 | M2 | Versioned corpus and semantic comparison | QUAL-002 | Official CPR source/hash manifest, bounded range downloader, synthetic malformed-input tests and external specimen provenance exist. Licensed semantic expectations, complete media and native reopen/render comparisons remain. |
| TASK-005 | M3 | Installed VST2/VST3/AU/CLAP inventory | INSP-004 | Opt-in passive inventory, typed CPR UID evidence and declared-identifier/compatibility matching. Candidate identity does not certify vendor identity, licence, preset compatibility or loadability. |
| TASK-006 | M3 | Isolated plug-in load and licensing diagnostics | PLAT-002 | Not implemented. No third-party plug-in binary is loaded by the inventory. |
| TASK-007 | M4 | Verified backups and safe output publication | SAFE-001–007 | SHA-256 backups, bounded staging, source preservation, path/link checks and retained failure reports support current export actions. Full restore UX, hostile-writer/race coverage and platform durability acceptance remain before modified CPR writing. |
| TASK-008 | M5 | Modified CPR writer and real Cubase reopening | REPR-004 | Disabled. The unchanged-container prerequisite is observed; reference-aware mutations and reopening with presets/automation/routing preserved are still required. |
| TASK-009 | M6 | Plug-in state archive and migration profiles | REPR-001–005 | Compatibility declarations and bounded DAWproject embedded-state hash evidence exist. CPR preset extraction/translation and state migration remain unsupported. |
| TASK-010 | M6 | Automation, routing and side-chain mapping | REPR-006–007 | Readable observations do not constitute translation. Cross-DAW mappings and musical validation remain. |
| TASK-011 | M7 | Direct and pivot conversion execution | CONV-001–006 | Planner plus explicit DawVert pipeline of up to three steps, intermediate validation, cumulative report and stop-on-failure. Manual/unknown adapters are refused; route/version fidelity is still experimental. |
| TASK-012 | M7 | External converter bridges | SEC-002 | Opt-in DawVert subprocess adapter exercised with the real converter in both RPP → DAWproject and RPP → DAWproject → RPP. ProjectConverter remains a manual candidate; no unverified headless interface is invented. |
| TASK-013 | M8 | Semantic and audio fidelity evidence | CONV-005 | Reports compare supported track/name/plug-in observations; one generated audio fixture retained its exact media bytes through the real pipeline. Native playback, presets, automation, routing and mix-render equivalence remain unverified. |
| TASK-014 | M8 | Batch processing and backup exclusions | SAFE-003 | Managed backup/export directories are excluded from scanners. General batch scheduling, cleanup/restore UX and production acceptance remain. |
| TASK-015 | Upstream | Review and focused contribution sequence | Contribution | Changes prepared on the working branch; maintainer review, upstream sequencing and merge are separate actions. |
| TASK-016 | M2/M7 | Native legacy ALL MIDI recovery | CONV-001–006 | Attributed MIT AllToMidi Dart port integrated into DPM, verified backup, new MIDI/report output and explicit partial/unverified results. Synthetic positive layouts pass; the real TABSAX sample is unsupported. ARR/full-session recovery remains a research gate. |

### Observed evidence and its limits

**CPR:** the seven official demo projects cover saved Cubase versions 12.0.0,
13.0.0, 14.0.5 and 15.0.0. Reconstructing the outer container and top-level chunk
framing retained every opaque payload and produced identical hashes on all
seven. This is an unchanged reconstruction check, not a verified CPR editor,
repair of corrupted internals, plug-in-state migration or Cubase reopen test.
The demo media was not downloaded into the validation corpus. See
[Sources and corpus](sources-and-corpus.md) for individual hashes and limits.

**Legacy ALL:** synthetic compact/fixed-layout fixtures exercise event timing,
repeated parts, channels, notes, controller/meta events, malformed input and
source preservation. The publicly shared `TABSAX.ALL` is a **negative** sample:
the upstream candidate predicate and DPM find no supported records, so recovery
is refused. Its Cubase version and reference MIDI are unconfirmed. There is no
positive real-song compatibility claim. The historical Steinberg ALL/ARR → CPR
workflow remains a separate manual route with known losses and legacy licence
constraints. See [Conversion execution](conversion-execution.md),
[Legacy Cubase](legacy-cubase.md) and
[Reverse-engineering scope](legacy-reverse-engineering.md).

**Real DawVert execution:** a generated one-second mono WAV and one-track RPP
passed through the actual subprocess adapter at DawVert revision
`c6c8be9e0660d9e75a3acecce43a13b0dbe0029c`. The two-step return RPP retained the
source project hash, track name/count and exact referenced WAV bytes:
`ac8b253193999a1510dce352420a9c7ef8e407d0f714daf2393cf9bfaecbbc3c`.
No DAW was opened and no audio render, plug-in-state, routing or automation
comparison was performed. See [Conversion execution](conversion-execution.md)
for runtime staging, timeout evidence, archive validation and remaining limits.

## Native Releases module

The release-detail editor now provides native typed forms and local CRUD for
catalog and workflow records. An advanced JSON editor is not required to edit
rights, distribution, promotion or multiple records. Existing Hive release and
project relationships are bridged to richer profile-local documents without a
new Hive adapter. See [Releases domain](releases-domain.md) for the current
feature and persistence contracts.

| ID | Feature | Current implementation | Remaining acceptance gate |
|---|---|---|---|
| REL-001 | Artists and credits | Profile catalog CRUD for stable artists, aliases, roles and recording credits; shared-reference checks before removal. | Native platform UX and realistic multi-release dataset review. |
| REL-002 | Albums, EPs, singles and playlists | Collection metadata, ordered release tracks, DPM project links and reusable ordered catalog playlists. Native release bridge preserves workflow metadata. | Broader existing-library compatibility and platform acceptance. |
| REL-003 | Asset versions and lineage | Native audio/cover/stem/lyrics/MIDI/document forms, parent links, evidence associations and streamed SHA-256 verification with baseline preservation. | Real workflow review; hash integrity is not audio quality or distributor certification. |
| REL-004 | Works and rightsholder shares | Catalog works/holders, ISWC/IPI/ISNI fields, editable credit/share records and reference/share validation. | User review of actual ownership; no registry or legal verification is implied. |
| REL-005 | Rights registrations | Multiple organizations, evidence links, references, manual states and status history. | Authenticated external submission/verification is outside current scope. |
| REL-006 | Distributor/platform deliveries | Multiple distributor records, nested platform deliveries, UPC/EAN validation, URLs, dates, manual states and history. | Real external acceptance/publication remains a manual fact to verify. |
| REL-007 | Campaigns and communications | Native campaign/post forms, associated tracks/assets, calendar, coverage findings and publication history. | Live platform posting is not implemented. |
| REL-008 | Profile-safe persistence | Catalog/workspace stores, v1 → v2 migration in memory, explicit legacy-file import, revision checks, unique previous snapshots and interrupted-write recovery. | Wider filesystem/native-platform acceptance; no global catalog/workspace/Hive transaction. |
| REL-009 | Native workflow UI | Dedicated add/edit/remove forms, ordered lists, validation, unsaved-change handling and local asset checks. Form regression tests include explicit-null clearing and UTC/calendar semantics. | Whole local suite passed; native desktop builds/smoke tests remain. |
| REL-010 | Workflow readiness | Local validation, task dependencies, overdue/blocked tasks, asset verification findings, promotion calendar and next-action guidance. | Real-world workflow review; readiness never certifies rights or delivery. |
| REL-011 | Local backup and Drive metadata | Native profile catalog/workspaces included in backup/Drive snapshots, ID-based merge, timestamps, explicit deletion records and preflight; focused tests use temporary storage and an in-memory Drive. | Full-suite completion and a separately authorized live-device/account exercise; no asset upload or multi-document atomicity claim. |

These features are native DPM concepts. Katsu informed domain research only;
there is no Katsu connector, copied provider code or Suno-account dependency.

## Validation checkpoint

Observed local checks include real CPR reconstruction, real DawVert execution,
synthetic native ALL recovery, negative real ALL refusal, store recovery/profile
boundaries, workflow/asset tests and widget interaction. In particular:

- The 29 focused persistence tests passed using real temporary files.
- The 12 inspection/recovery/panel widget tests passed, including French labels,
  cancellation, busy/error states, partial counts and selected-file identity.
- The seven typed-form tests passed, including a UTC+14 run that would expose a
  calendar date shifted through UTC, unknown-field preservation and cancellation.
- The 207-test focused backup/Drive regression run passed, including 20 native
  metadata transfer/backup/Drive cases. These exercise the production services
  with temporary libraries and an in-memory Drive client; no live account is
  used. Imported verified assets require a new local check.
- Focused analysis for the changed inspection and typed-form widgets is clean.

**Whole Flutter application suite: 4,744 passed, 12 skipped** on Linux with
Flutter 3.47.8 / Dart 3.13.7. The 14 Python corpus-tool tests also passed. The
broad 77-path Dart analysis had 0 errors, 0 warnings and 91 informational
findings; this is not a blanket clean-analysis claim. See the
[dated validation record](validation-2026-10-26.md) for commands and scope. CI
remains main-only. Native macOS Apple Silicon, macOS Intel and Windows
builds/smoke tests, native DAW reopening and render comparisons remain unobserved.

## Definition of done and ordering

An acceptance claim needs English code/documentation, linked requirements,
meaningful automated checks and recorded platform evidence. Untrusted files
must remain bounded; originals and verified backups must survive failures.
Unknown or lossy behavior must remain visible in reports and UI.

Modified CPR work remains gated by TASK-003/004 semantic coverage, TASK-007
write safety and TASK-008 native reopen checks before state/routing migrations.
Wider conversion support follows TASK-011/012 with TASK-013 fidelity evidence.
Releases acceptance continues with native-platform results,
profile/reference integrity and realistic local workflow review. A data model,
export file or green unit test alone does not close those product gates.
