# Release validation, integrity and local workflow

## Schema contracts

`ReleaseWorkflowValidator.validate(workspace, catalog: catalog)` accepts the
legacy workspace schema 1 and native workspace schema 2. Schema 2 uses stable
IDs for releases, tracks, filings, deliveries, posts, assets, campaigns and
tasks. `validateCatalog(catalog)` checks profile catalog schema 1: artists,
rightsholders, musical works, recordings, credits and reusable playlists.

The validator returns errors and never mutates its input. Unknown extension
fields are retained by callers. Malformed nested maps/lists become diagnostic
messages rather than unsafe type casts. Record collections are bounded.

Checks include:

- Duplicate/invalid identifiers, invalid collection types and lifecycle states.
- Nonempty entity names/titles where applicable.
- Catalog artist/work/holder/playlist references and workspace references among
  tracks, assets, campaigns, evidence files and tasks.
- Finite rightsholder shares in 0–100, totaling 100% when shares are provided.
- ISRC syntax when supplied; UPC-A/EAN-13 digit length and check digit.
- HTTP(S) public-link syntax, calendar dates, publication/scheduling timestamps,
  status history and campaign date order.
- Cycles in asset lineage or task dependencies.
- Integrity evidence fields for assets labelled verified.

Optional fields remain optional in drafts. An identifier format/checksum does
not prove assignment or ownership. Rights acceptance and platform delivery are
manually recorded states, not externally verified facts. No rule assumes every
release must be registered with SACEM or another rights organization.

Catalog references are checked only when a catalog is supplied. A legacy
schema-1 `artist_ids` entry that has no catalog record is preserved as an
advisory unresolved reference by the workflow engine. Native schema 2 requires
that reference to resolve. Stores/UI must validate every affected release
before deleting shared artists, works or tracks. Validation of a single
workspace cannot protect references in files the caller did not supply.

`project_id` is a typed link to an existing DPM project; the application must
resolve its existence against the active profile's project repository.

## Local asset integrity

`ReleaseAssetVerifier().verify(asset)` streams a local file into SHA-256 and
returns a new metadata map. It does not copy, modify, delete or execute the
asset. It preserves all unrelated fields.

The default maximum is 16 GiB with a five-minute total deadline. Timeout cancels
the stream. Symlink files, directories and non-regular files are not certified.
Pre/post file type, canonical path, size, modification/change timestamps and
streamed byte count detect observable changes during verification. This is
local integrity evidence, not protection against a hostile operating system.

| Result | Meaning |
|---|---|
| `verified` | A stable observed file matches its existing baseline, or establishes its first baseline. |
| `missing` | The selected file is not available at the supplied path. |
| `changed` | The observed bytes differ from the stored baseline, or the file changed during verification. |
| `unverified` | Invalid metadata, unsupported file kind, I/O error, limit or timeout prevented verification. |

A successful result contains `sha256`, `bytes`, `verified_at`, `checked_at` and
`resolved_path`. Observations are also retained as `observed_sha256` and
`observed_bytes`. A mismatch **does not replace** the prior digest/size baseline:
`verification_error` explains the discrepancy. A revised master should be
recorded as another asset/version with `parent_asset_id`, retaining lineage.

Verification does not certify audio quality, loudness, codec conformity,
artwork dimensions, distributor acceptance or copyright. The result describes
the observed file at the time checked.

## Workflow evaluation

`ReleaseWorkflowEngine.evaluate(workspace, catalog: catalog, now: clock)` returns
`ReleaseWorkflowEvaluation` with:

- Typed issues (`code`, `message`, `severity`, `recordId`).
- An actionable `nextAction`.
- Blocked and overdue task IDs, including inconsistent completed tasks with
  unfinished prerequisites.
- Assets requiring verification and tracks without associated promotion plans.
- A chronological promotion calendar based on scheduled/publication dates.
- `needs_attention` or `ready_for_manual_review` local readiness.

Date-only deadlines remain due through their local calendar day. Explicit
clock injection makes due-date tests deterministic. Cancelled communications
are excluded from promotion coverage and the active calendar. A campaign post
covers its linked track IDs; an asset by itself is not a publication plan.
Playlists do not require their own duplicate masters or distribution route.

`ready_for_manual_review` means the recorded local checklist has no outstanding
blocking/warning findings. It is not a release approval, rights certification or
confirmation that any platform is live. The JSON report always includes
`external_statuses_verified: false`.

## Verification performed

Local Flutter tests cover schema compatibility, malformed inputs, reference
protection, duplicate/cyclic relationships, split totals, identifiers/checksums,
dates/URLs/status history, hash baselines, unchanged source files, live changes
during hashing, deadline cancellation, missing/non-regular files, task
prerequisites, date-only deadlines, campaign coverage and calendar order.
No files were uploaded to rights, distribution or social platforms.

## Local backup and Drive snapshots

Native Releases metadata is included in the existing backup workflows:

| Workflow | Snapshot field | Scope |
|---|---|---|
| Local JSON backup 1.5 | `releaseWorkspace` | The selected profile's catalog and saved release workspaces |
| Drive database snapshot 1.8 | `releaseWorkspacesByProfile` | An explicit bundle for each profile |

Both use `ReleaseWorkspaceTransfer`, backed by the active Hive library's sibling
`release-workspaces/<profileId>` directory. This follows isolated development
libraries and library moves; it does not independently select the OS default
support directory. Tests use temporary libraries. A bundle has schema 1,
`profile_id`, the complete profile `catalog`, and `workspaces` keyed by release ID.
The existing Hive adapters are unchanged. Older backups without the new field
remain readable and do not clear native Releases metadata.

`exportProfile(profileId, releaseIds: liveIds)` includes saved native workspaces
for the live Hive releases. Orphan files stay on disk, but are not uploaded as
new releases. The catalog includes artists, rightsholders, works, recordings and
playlists. Workspaces include assets, campaigns, communications, rights filings,
distribution, tasks and their history. No asset file is read, copied or uploaded
by this transfer. Paths and dated hash/verification evidence are preserved.
An accepted incoming asset marked `verified` becomes `unverified` with
`verification_error: imported_verification_requires_local_check`; its source
digest, byte count and verification date remain available as evidence and a
baseline. The workflow therefore requests a local check. A locally selected
newer/unchanged asset retains its local result, and replaying an identical
snapshot does not invalidate it again. A successful local verification clears
the imported-evidence message using the existing verifier.

`mergeProfile(bundle, targetProfileId: id, allowedReleaseIds: liveIds)` maps the
source envelope only to the chosen target profile. A local import into a new
profile preserves entity IDs while changing the document `profile_id`. Drive
requires the map key, bundle profile and destination profile to agree and never
falls back to copying a native bundle into every profile. Local backup also
rejects a repository/profile mismatch before accessing data, including a profile
switch while an asynchronous export/import action is being prepared.

### Merge rules

- Known entity collections merge by ID. A record missing from the incoming
  snapshot remains local. Incoming documents missing from the snapshot also
  remain local, including during the legacy backup's Replace operation.
- A strictly newer row `updated_at` selects that complete row. This preserves
  deliberately cleared optional fields. Unknown extension fields survive when
  present in the selected row, and envelope extension fields are retained.
  Editors must retain extensions when changing a record. Envelope optional
  fields are cleared using explicit `null`, not omission.
- Legacy rows with no timestamp key inherit their original document clock;
  the transfer materializes that clock before advancing the document timestamp.
  An explicit `updated_at: null` means unknown and never inherits a newer summary
  clock. Editors freeze untouched legacy rows this way before ordinary saves.
  Local revision numbers are concurrency checks, not synchronization clocks.
- Equal or unknown conflicting clocks retain local row content and return the
  row path in `conflicts`. The original local backup or previous Drive snapshot
  is the evidence for manual comparison. This is not a multi-writer conflict UI.
- Complete record membership lists, credits and shares follow the winning row;
  status history entries are retained from both records without exact duplicates.
  The newer envelope chooses track ordering, then any other local-only records
  are appended. This does not merge simultaneous edits within one platform row.
- Deletion is explicit: `deleted_records[section][id] = UTC instant`. The latest
  tombstone is retained. It suppresses a row with an older/equal or unknown
  clock; a later restored row survives. Absence alone never generates deletion.
  A catalog deletion that would break a saved active workspace, or a workspace
  deletion that would break a known local reference, aborts metadata import.

Structural preflight covers all incoming documents before native metadata is
saved, with a 64 MiB profile bundle limit, 10,000 workspace limit and the store's
8 MiB document limit. Bad profile envelopes, duplicate/missing IDs, malformed
deletions and unreadable metadata cause an error rather than silently omitting
data from a successful replacement snapshot. Each document is saved through its
recoverable store with `expectedRevision` and `preserveTimestamps: true`.
Replay of unchanged data does not create another revision.

Catalog, workspace and legacy Hive operations are separate transactions. A
concurrent edit or I/O failure can stop a transfer after earlier documents were
saved; the caller should reload and retry. The store's previous revisions and
existing backup/history remain available. This implementation does not provide
a transaction across multiple devices, profile files and Hive, nor does it
claim to resolve simultaneous editing of an identical record automatically.

`ImportResult.releaseMetadata` and `SyncResult.releaseMetadataByProfile` report
catalog/workspace changes, skipped orphan IDs and local-retained conflicts.
The optional transfer injection on backup methods and the Drive service exists
for alternate library roots and tests; production defaults to the active Hive
root. Tests exercise a real local backup roundtrip after discarding its temporary
Hive and metadata directories, new-profile remapping, older backups, profile
switch rejection, timestamp/tombstone conflicts, replay and an in-memory Drive
through the production Google APIs client. No live Drive account was accessed.
