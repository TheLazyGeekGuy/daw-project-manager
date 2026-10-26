# Native DPM catalog and music release workflows

Updated: **2026-10-26**. The Releases module now has integrated native Flutter
forms and local CRUD for catalog, rights, distribution and promotion records,
with profile-scoped persistence, validation, asset integrity and backup/Drive
metadata integration. The whole Flutter suite passed locally: **4,744 passed,
12 skipped** on Linux. Native desktop acceptance remains pending; see the
[dated validation record](validation-2026-10-26.md).

This is part of **DAW Project Manager for macOS Apple Silicon, macOS Intel and
Windows**, using shared Dart/Flutter services. It is not a separate application.
“Releases” means music release management inside DPM, not GitHub Release
publishing. No GitHub release, merge or external music-platform publication is
requested or performed by these forms.

## Domain boundaries

| Entity | Meaning and native editing surface |
|---|---|
| Artist | Stable profile-catalog identity, name, sort name, aliases and roles. Recording credits refer to artist IDs. |
| Musical work | The underlying composition, optional ISWC and editable rightsholder shares. It is separate from a particular recording. |
| Rightsholder | Catalog identity with name and optional IPI/ISNI. Shares link a holder and role to a work. |
| Recording/track | Stable identity, title, optional ISRC, work link, artist credits and an optional active-profile DPM project link. Multiple recordings may originate from one project. |
| Release collection | Album, EP, single or compilation metadata with an ordered list of recordings, credited artists, release date and optional UPC/EAN. |
| Playlist | Independently ordered selection of catalog recordings. A playlist does not imply an album, its own master files or a distribution route. |
| Asset | Master, mix, preview, stem, cover, lyrics, MIDI or document reference; optional track/parent association and dated integrity evidence. |
| Rights filing | Work, organization, reference, evidence, submission date, manually recorded state and history. Submission is distinct from acceptance. |
| Distribution delivery | Distributor-level metadata plus separate platform deliveries, URLs, identifiers, dates and history. A submitted delivery is not proof that a platform is live. |
| Campaign/communication | Campaign dates and linked tracks; individual posts with platform, text, assets, schedule/publication timestamps, URL and history. |
| Workflow task | Local task with state, deadline and prerequisites; dependencies contribute to blocked/overdue findings. |

The editor provides dedicated forms for multiple records and nested credits,
shares and platform deliveries. Add/edit/remove actions preserve stable IDs;
ordered tracks and playlists can be rearranged. Shared catalog removal checks
references in other saved release workspaces, not only the open release.
Removing a workflow association does not delete its source DAW project or media.

## Existing DPM integration

The existing Hive `Release`, `ReleaseFile` and project adapters remain in use.
The richer workspace and reusable catalog are JSON documents beside the active
library. `ReleaseNativeBridge` reconciles current native release summary,
project links and release assets with the workspace while retaining unrelated
workflow metadata, manual tracks and manual assets. Existing IDs/credits are
preserved when a linked project survives; distinct recordings can reference the
same source project. A changed native asset path clears stale verification
fields before another local check.

The release-detail page supplies the current profile's project choices and the
store location. Forms use `material_ui` and the application's localization
delegates. New labels have English and French translations; other application
locales currently use English fallback for these additions.

Typing and validation are separate from persistence. Optional fields may stay
empty; an intentional clear is returned as explicit `null` so a partial document
merge does not resurrect a previous value. Known-field edits keep unfamiliar
extension fields. Cancelling returns no edit and leaves the supplied records
unchanged. A calendar release date remains `YYYY-MM-DD`; scheduled events with
a time are converted to UTC instants. This distinction is covered by form tests
including a UTC+14 test run and an explicit `+14:00` timestamp.

## Catalog and workspace storage

Each profile has one shared catalog and one document per release:

| Document | Path relative to `release-workspaces/<profile-id>` | Version |
|---|---|---|
| Profile catalog | `catalog/library.json` | Schema 1 |
| Release workspace | `<release-id>.json` | Schema 2 |

The storage root follows the **active Hive library**, including isolated
development libraries and library moves; it is not independently guessed from
the operating system's default support path. The profile catalog contains
artists, holders, works, recordings and playlists. A release workspace holds
its ordered complete track records, assets, filings, deliveries, campaigns,
communications, tasks and release-level metadata. The UI keeps its edited
recordings in the profile catalog as well as the current release workspace.

`ReleaseWorkspaceStore` and `ReleaseCatalogStore` support expected-revision
checks, bounded JSON, process/file locking, staged writes, read-back hash
verification, unique previous snapshots and interrupted-publication recovery.
IDs and file/link boundaries are checked. Unknown properties survive
normalization. Workspace schema 1 migrates in memory to schema 2; reading alone
does not rewrite the file. The first explicit save preserves its exact previous
bytes. Missing legacy record IDs are derived deterministically without inventing
artist identities or external registration results.

An unscoped old workspace is imported only from an explicitly selected file
into a named destination profile, with release/profile checks and provenance.
The source is never moved or deleted. No file is assigned to the active profile
merely because its original ownership is unknown.

These are **single-document recoverable transactions**. Catalog, workspace and
legacy Hive changes are separate commits. A later conflict or I/O error may
leave earlier valid catalog changes in place; the user must reload/reconcile
and retry. Neither normal editing nor backup/Drive transfer claims global
atomicity across documents, profiles or devices. Filesystem durability remains
subject to operating-system/filesystem behavior. See
[Persistence](release-persistence.md) for the journal, migration and API contract.

## Asset integrity, validation and workflow

`ReleaseAssetVerifier` reads an explicitly associated local file and streams
SHA-256 with size/time limits and observable-change checks. It does not modify,
copy, execute or upload the file. Outcomes distinguish `verified`, `missing`,
`changed` and `unverified`. A changed file retains its old hash/size baseline;
observed current bytes are recorded separately. A new master version can be
linked through `parent_asset_id` instead of erasing its predecessor's evidence.

A hash proves the observed byte identity at a recorded time. It does not certify
audio quality, loudness, encoding, artwork suitability, copyright or distributor
acceptance. After restoring metadata to another machine, paths and historical
verification observations remain metadata; the new device must check local
availability and bytes again. Incoming assets labelled `verified` are marked
`unverified` with `imported_verification_requires_local_check`; their recorded
hash evidence is retained for comparison.

`ReleaseWorkflowValidator` checks known schema shapes, identifiers, duplicate
records, references, ISRC syntax, UPC/EAN check digits, shares, URLs, dates,
status history, lineage and task cycles. Draft storage can retain incomplete
rights allocations; workflow validation reports allocation/readiness problems
instead of inventing ownership. Identifier syntax and checksum checks do not
prove that an identifier was assigned by an authority.

`ReleaseWorkflowEngine` produces typed findings, a next action, blocked/overdue
tasks, assets needing verification, tracks without promotion coverage and a
chronological promotion calendar. Date-only deadlines remain valid through the
local calendar day. Cancelled communications do not count as active promotion.
The readiness result is `needs_attention` or `ready_for_manual_review`, and
reports keep `external_statuses_verified: false`. There is no requirement that
every release be registered with a particular rights organization.

See [Validation and workflow](release-validation.md) for precise checks,
verification limits and calendar/coverage rules.

## Local backup and Drive metadata

Native catalog and workspace metadata are included in the existing local JSON
backup and Drive database snapshot workflows. Local backup version 1.5 carries
`releaseWorkspace`; Drive snapshot version 1.8 carries explicit
`releaseWorkspacesByProfile` bundles. Older backups without these fields remain
readable and do not clear the newer metadata. The transfer follows the active
library root and exports saved workspaces for live Hive releases; orphan files
stay local instead of becoming new releases remotely.

The transfer preflights profile envelopes and document structure, merges known
collections by stable ID and uses UTC edit timestamps, not device-local revision
numbers, to select newer records. Equal/unknown conflicting clocks retain local
content and report conflicts. Missing remote records do not delete local ones;
explicit timestamped deletion records carry deletions, subject to reference
checks. Replaying an unchanged bundle does not create new revisions. Unknown
extensions survive in the selected complete record, and deliberate null clears
are retained.

Metadata includes local asset paths and dated integrity evidence, not the asset
bytes. These additions do not upload audio, documents or source projects. The
production backup/Drive services are covered by temporary-library and in-memory
Drive tests; no live Drive account was accessed for this validation. A failure
can occur after an earlier document committed: this is not a transaction across
Hive, all JSON files and remote devices. See
[Backup/Drive details and conflict rules](release-validation.md#local-backup-and-drive-snapshots).

## Observed verification and remaining gates

The local evidence covers persistence/migration and profile boundaries,
reference and malformed-data validation, asset baselines/change detection,
task/calendar behavior, native forms and backup/Drive snapshot flows. The
focused store suite passed 29 tests; the new typed-form suite passed seven tests,
including UTC+14, empty-choice/null-clearing and cancellation regressions.
Native workflow widget tests exercise persisted forms and linked records.
The focused backup/Drive run passed 207 tests, including 20 native metadata
transfer, local backup and in-memory Drive scenarios; no live account was used.
The **whole Flutter suite passed: 4,744 passed, 12 skipped**, using Flutter
3.47.8 / Dart 3.13.7 on Linux. Main-only branch CI did not prevent local tests.
The [validation record](validation-2026-10-26.md) distinguishes this pass from
analyzer informational findings and unobserved native-platform checks.

Before describing production acceptance as complete, record native
builds/smoke tests on macOS Apple Silicon, macOS Intel and Windows. Review realistic multi-release libraries, backup restoration and
reference changes across profiles. A separately authorized real Drive/device
exercise remains distinct from the in-memory service tests. External rights,
distributor and social-platform states remain manually recorded until explicit,
authenticated integrations are designed and verified.

Katsu contributed research ideas about stable identities, asset lineage, rights
evidence and promotion coverage. No Katsu source, connector, provider-specific
authentication or Suno-account dependency is introduced. This native module
works with the user's own catalog and local project library.
