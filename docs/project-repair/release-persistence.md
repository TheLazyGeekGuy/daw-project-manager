# Release persistence and profile catalogs

## Storage contract

`ReleaseWorkspaceStore` and `ReleaseCatalogStore` operate on the active DPM
profile directory supplied by the application. They never select a profile by
guessing who owns an unscoped metadata file. The existing Hive release adapter
is unchanged.

| Document | Path relative to the profile directory | Schema |
|---|---|---|
| One release workspace | `<release-id>.json` | 2 |
| Shared music catalog | `catalog/library.json` | 1 |
| Previous committed bytes | `.<document-id>-<uuid>.previous.json` | Original, unchanged |
| Pending transaction | `.<document-id>.pending.json` | Internal recovery journal |
| Process lock | `.<document-id>.lock` | Internal coordination file |

The application resolves `release-workspaces/<profile-id>` beside the active
Hive library. This follows isolated development libraries and library moves;
it does not independently choose the operating system's default support path.
Catalog artifacts live inside its `catalog` child directory, so even a release
named `library` cannot collide with the shared catalog. UI, local backup and
Drive transfer use the same active-library root.

`listReleaseIds()` lists the active profile's regular workspace files in stable
order, excluding hidden transactions/snapshots and directories. It rejects
symlinked workspace candidates and caps directory traversal and document count.
Use it to check references from other releases before deleting shared catalog
records; enumeration does not lock the whole profile as a multi-document unit.

Both document types include an integer `revision`. A new document or an old
unversioned workspace reads as revision 0; every successful save increments it.
When `profileId` is provided, a document naming another profile is rejected.

Local edits stamp top-level `updated_at` in UTC. Transfer/merge callers may pass
`preserveTimestamps: true` to either save API to retain incoming timestamps and
avoid turning every synchronization into a newer local edit. Revisions are
device-local conflict counters and must not be used as cross-device clocks.
The store does not stamp unchanged records; record-level merge evidence comes
from their own timestamps or an explicitly documented document fallback.

## Save and conflict handling

```dart
final store = ReleaseWorkspaceStore(profileDirectory, profileId: profile.id);
final workspace = await store.read(release.id);
await store.save(
  release.id,
  {...workspace, 'collection_type': 'ep'},
  expectedRevision: workspace['revision'] as int,
);
final committed = await store.read(release.id);
```

`ReleaseCatalogStore(profileDirectory, profileId: profile.id)` provides the
same `read()` and `save(value, expectedRevision: ...)` pattern without a release
ID. A conflict throws `ReleaseRevisionConflict`, including the expected and
actual revisions. Reload and reconcile the user's changes; do not retry by
dropping the revision constraint. The optional argument preserves compatibility
with earlier callers, but interactive editors should always supply it.

Each save freezes its submitted JSON snapshot before asynchronous IO. An
in-process queue and operating-system file lock serialize cooperating readers
and writers. The new JSON is written to a unique staging file, flushed, read
back, hashed and schema-checked. The previous destination is copied into a
unique snapshot and independently verified before the transaction journal is
published. Finally, a same-directory rename publishes the new document, whose
hash is checked again before the journal is removed.

No cleanup process removes previous snapshots. Unknown top-level properties
are retained even when a caller submits a smaller editing view. Record lists
remain complete snapshots: editors must retain the unknown fields on records
they modify, as the native record editors do. A field is not deleted merely
because it is unfamiliar to this version of DPM.

Omitting a top-level property is not a deletion. Native forms represent an
intentional optional-field clear as explicit `null`, which survives this merge.
Row timestamps and explicit deletion records for synchronization are defined in
[the transfer contract](release-validation.md#merge-rules); store revisions are
not cross-device clocks.

## Interrupted publication

The next operation checks a pending journal while holding the document lock.
It accepts an already-published destination only if its hash matches the
journal; otherwise it can finish a verified staged publication. If both the
new output and destination are missing, a verified previous snapshot can be
restored. A differing destination, invalid journal path or corrupted staging
file is reported as an error and retained for investigation.

This is a single-document transaction. Catalog and workspace commits are
independent: save the catalog first, then the workspace, with their respective
expected revisions. If the second commit fails, the catalog may contain unused
records. Keep those records and reload/reconcile the workspace; do not claim
that the two documents were committed atomically.

Durability depends on the filesystem and operating system. The implementation
flushes files and recovers interrupted publication; it does not claim a
cross-filesystem transaction, protection from arbitrary non-cooperating local
writers, or guaranteed survival of every hardware/power failure.

## Workspace migration and explicit legacy import

Schema 1 is migrated to schema 2 **in memory** during reads. Existing artist
IDs, collection type, ordered tracks, rights filings, distribution entries and
communication records are retained. Missing `assets`, `campaigns` and `tasks`
arrays are added. Unknown properties remain present. A future unsupported
schema is rejected rather than rewritten.

Older filings, distributor entries and communication records without IDs receive
deterministic IDs derived from the release, section and original list position.
Nested platform-delivery records receive the same treatment. Existing IDs are
retained, including duplicates so that validation can report them instead of
silently changing relationships. A missing communication title uses its existing
platform label, or a generic numbered label when unavailable. No artist identity,
publication date or registration result is invented. The generated IDs become
persistent on the first explicit save and remain unchanged by later reordering.

The source file remains byte-for-byte unchanged until an explicit save. The
first save preserves the exact old file as a previous snapshot before
publishing schema 2.

To import a selected unscoped file:

```dart
await store.importLegacy(
  selectedFile,
  releaseId: release.id,
  destinationProfileId: profile.id,
);
```

Import requires a matching release identifier and explicitly named destination
profile. By default the destination must not already exist, including an old
revision-0 workspace. Replacing an existing destination requires its explicit
`expectedRevision`. The source is never moved or deleted. The imported document
records its source SHA-256, source profile if present, destination profile and
import time. Importing a file onto itself is rejected. There is no automatic
reassignment of unscoped files to whichever profile happens to be active.

## Catalog integrity

The shared catalog contains `artists`, `holders`, `works`, `tracks` and
`playlists` arrays. Each record needs a stable ID and name/title; IDs are unique
within their section. Artist aliases and roles are string lists. Work shares
refer to existing holders, track credits refer to artists, track work references
refer to works, and ordered playlist references refer to tracks. Playlists may
repeat a track. Partial rights allocations are allowed; invalid percentages or
totals above 100 percent are rejected.

These checks validate stored relationships. They do not establish legal rights,
registration acceptance or distribution readiness; those are separate workflow
decisions. Project IDs are retained as external DPM references rather than
inventing an implicit catalog project registry.

## Boundaries and verification

Documents are limited to 8 MiB. Path-like identifiers, linked profile/catalog
directories, linked documents and linked transaction artifacts are refused.
Recovery paths must match the expected document's internal filenames.

The local tests use real temporary files to exercise schema migration without
rewriting, exact previous snapshots, profile isolation, concurrent/stale-editor
conflicts, interrupted replacement and rollback, journal traversal, symlinks,
explicit imports, catalog relationships and preservation of unknown metadata.
They do not require network access or branch CI.

The focused store suite passed 29 tests locally, and the whole Flutter suite
passed with **4,744 passed, 12 skipped** on Linux. See the
[validation record](validation-2026-10-26.md) for commands and analyzer scope.
Native macOS Apple Silicon, macOS Intel and Windows filesystem/build acceptance
has not been observed here. Main-only CI configuration does not prevent local tests.

```bash
flutter test --no-pub \
  test/services/release_workspace_store_test.dart \
  test/services/release_workspace_transactions_test.dart \
  test/services/release_catalog_store_test.dart
```

Native catalog/workspace metadata are also included in local backup and Drive
snapshots. See [Releases domain](releases-domain.md) for integration and
[backup/Drive validation](release-validation.md#local-backup-and-drive-snapshots)
for profile envelopes, timestamps, deletion records and the separate-document
transaction boundary. Asset bytes are not uploaded by this metadata transfer.
