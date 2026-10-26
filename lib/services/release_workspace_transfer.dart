import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../repository/project_repository.dart';
import '../utils/sync_time.dart';
import 'release_catalog_store.dart';
import 'release_workspace_migration.dart';
import 'release_workspace_store.dart';

/// The metadata carried by local backups and the existing Drive snapshot.
///
/// Asset paths and dated integrity evidence are metadata. This service never
/// reads, copies, uploads, removes, or certifies the referenced media files.
class ReleaseWorkspaceTransfer {
  const ReleaseWorkspaceTransfer({required this.root});

  final Directory root;
  static const maxBundleBytes = 64 * 1024 * 1024;
  static const maxWorkspaces = 10000;

  /// Follow the selected library, including isolated/dev/test Hive roots.
  /// Resolving the OS support directory independently could back up another
  /// library, or write into real user data during a temporary-library test.
  factory ReleaseWorkspaceTransfer.forRepository(ProjectRepository repo) {
    final boxPath = repo.projectsBox.path;
    if (boxPath == null || boxPath.isEmpty) {
      throw StateError('The active library has no local metadata directory');
    }
    return ReleaseWorkspaceTransfer(
      root: Directory(p.join(p.dirname(boxPath), 'release-workspaces')),
    );
  }

  Directory _profileDirectory(String id) =>
      Directory(p.join(root.path, ReleaseJsonDocumentStore.safeId(id)));

  /// [releaseIds] limits the snapshot to releases still present in Hive.
  /// Orphaned metadata remains on disk; a deleted release is not recreated.
  Future<Map<String, dynamic>> exportProfile(
    String profileId, {
    Set<String>? releaseIds,
  }) async {
    final directory = _profileDirectory(profileId);
    final store = ReleaseWorkspaceStore(directory, profileId: profileId);
    final catalog = await ReleaseCatalogStore(
      directory,
      profileId: profileId,
    ).read();
    final workspaces = <String, dynamic>{};
    var bytes = utf8.encode(jsonEncode(catalog)).length;
    for (final id in await store.listReleaseIds()) {
      if (releaseIds != null && !releaseIds.contains(id)) continue;
      final value = await store.read(id);
      bytes += utf8.encode(jsonEncode(value)).length;
      if (bytes > maxBundleBytes) {
        throw const FormatException('Release snapshot exceeds its size limit');
      }
      workspaces[id] = value;
    }
    return validateBundle({
      'schema_version': 1,
      'profile_id': profileId,
      'catalog': catalog,
      'workspaces': workspaces,
    });
  }

  /// Full structural preflight, with no filesystem writes. Callers use this
  /// before changing their legacy Hive records. Unknown fields survive.
  static Map<String, dynamic> validateBundle(
    Object? value, {
    String? expectedProfileId,
  }) {
    if (value is! Map || value['schema_version'] != 1) {
      throw const FormatException('Unsupported release snapshot schema');
    }
    final encoded = utf8.encode(jsonEncode(value));
    if (encoded.length > maxBundleBytes) {
      throw const FormatException('Release snapshot exceeds its size limit');
    }
    final bundle = ReleaseJsonDocumentStore.decode(encoded);
    final profileId = bundle['profile_id'];
    if (profileId is! String ||
        (expectedProfileId != null && profileId != expectedProfileId)) {
      throw const FormatException('Release snapshot profile mismatch');
    }
    ReleaseJsonDocumentStore.safeId(profileId);
    final rawCatalog = bundle['catalog'];
    final rawWorkspaces = bundle['workspaces'];
    if (rawCatalog is! Map<String, dynamic> ||
        rawWorkspaces is! Map<String, dynamic> ||
        rawWorkspaces.length > maxWorkspaces) {
      throw const FormatException('Invalid release snapshot documents');
    }
    final catalog = ReleaseCatalogStore(
      Directory('.'),
      profileId: profileId,
    ).normalize(rawCatalog);
    _checkDocument(catalog, ReleaseCatalogStore.sections);
    final workspaces = <String, dynamic>{};
    for (final entry in rawWorkspaces.entries) {
      ReleaseJsonDocumentStore.safeId(entry.key);
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Invalid release workspace snapshot');
      }
      final workspace = ReleaseWorkspaceMigration.migrate(
        entry.value as Map<String, dynamic>,
        entry.key,
        profileId: profileId,
      );
      _checkDocument(workspace, ReleaseWorkspaceMigration.recordSections);
      workspaces[entry.key] = workspace;
    }
    return {...bundle, 'catalog': catalog, 'workspaces': workspaces};
  }

  /// Explicitly maps the source profile into the chosen destination profile.
  /// Rows absent from the snapshot are retained. Only timestamped tombstones
  /// delete rows, and a newer restored row wins over an older tombstone.
  ///
  /// All documents are merged and validated before any save. Each store save
  /// checks its local revision and is recoverable; the group is not a single
  /// filesystem/Hive transaction. On a concurrent edit, retry after reloading.
  Future<ReleaseWorkspaceTransferResult> mergeProfile(
    Object? value, {
    required String targetProfileId,
    Set<String>? allowedReleaseIds,
  }) async {
    final bundle = validateBundle(value);
    final directory = _profileDirectory(targetProfileId);
    final catalogStore = ReleaseCatalogStore(
      directory,
      profileId: targetProfileId,
    );
    final workspaceStore = ReleaseWorkspaceStore(
      directory,
      profileId: targetProfileId,
    );
    final conflicts = <String>[];
    final currentCatalog = await catalogStore.read();
    final incomingCatalog = {
      ...bundle['catalog'] as Map<String, dynamic>,
      'profile_id': targetProfileId,
    };
    final catalog = catalogStore.normalize(
      _mergeDocument(
        currentCatalog,
        incomingCatalog,
        ReleaseCatalogStore.sections,
        'catalog',
        conflicts,
      ),
    );
    _checkDocument(catalog, ReleaseCatalogStore.sections);
    final current = <String, Map<String, dynamic>>{};
    final merged = <String, Map<String, dynamic>>{};
    final skipped = <String>[];
    final incoming = bundle['workspaces'] as Map<String, dynamic>;
    for (final entry in incoming.entries) {
      if (allowedReleaseIds != null && !allowedReleaseIds.contains(entry.key)) {
        skipped.add(entry.key);
        continue;
      }
      final before = await workspaceStore.read(entry.key);
      current[entry.key] = before;
      final next = ReleaseWorkspaceMigration.migrate(
        _mergeDocument(
          before,
          {
            ...entry.value as Map<String, dynamic>,
            'profile_id': targetProfileId,
          },
          ReleaseWorkspaceMigration.recordSections,
          'release/${entry.key}',
          conflicts,
        ),
        entry.key,
        profileId: targetProfileId,
      );
      _checkDocument(next, ReleaseWorkspaceMigration.recordSections);
      merged[entry.key] = next;
    }
    // A catalog tombstone must not break a local release that the incoming
    // snapshot did not happen to include. Do not demand completed draft data.
    final referenced = {...merged};
    for (final id in await workspaceStore.listReleaseIds()) {
      if (allowedReleaseIds != null && !allowedReleaseIds.contains(id)) {
        continue;
      }
      referenced.putIfAbsent(id, () => <String, dynamic>{});
      if (referenced[id]!.isEmpty) {
        referenced[id] = await workspaceStore.read(id);
      }
    }
    for (final workspace in referenced.values) {
      _checkDeletedReferences(catalog, workspace);
    }

    var savedWorkspaces = 0;
    final catalogChanged = !_same(currentCatalog, catalog);
    if (catalogChanged) {
      await catalogStore.save(
        catalog,
        expectedRevision: currentCatalog['revision'] as int,
        preserveTimestamps: true,
      );
    }
    for (final entry in merged.entries) {
      if (_same(current[entry.key], entry.value)) continue;
      await workspaceStore.save(
        entry.key,
        entry.value,
        expectedRevision: current[entry.key]!['revision'] as int,
        preserveTimestamps: true,
      );
      savedWorkspaces++;
    }
    return ReleaseWorkspaceTransferResult(
      catalogChanged: catalogChanged,
      workspacesChanged: savedWorkspaces,
      skippedReleaseIds: skipped,
      conflicts: conflicts,
    );
  }

  static void _checkDocument(
    Map<String, dynamic> value,
    List<String> sections,
  ) {
    if (utf8.encode(const JsonEncoder.withIndent('  ').convert(value)).length >
        ReleaseJsonDocumentStore.maxDocumentBytes) {
      throw const FormatException('Release document exceeds its size limit');
    }
    for (final section in sections) {
      final ids = <String>{};
      for (final record in value[section] as List) {
        final id = record['id'];
        if (id is! String || id.trim().isEmpty || !ids.add(id)) {
          throw FormatException('Missing or duplicate $section identifier');
        }
      }
    }
    _tombstones(value);
  }

  static DateTime? _clock(Object? value) => tryParseSyncInstant(value)?.toUtc();

  static Map<String, Map<String, String>> _tombstones(
    Map<String, dynamic> document,
  ) {
    final raw = document['deleted_records'];
    if (raw == null) return {};
    if (raw is! Map) {
      throw const FormatException('deleted_records must be a section map');
    }
    final result = <String, Map<String, String>>{};
    for (final section in raw.entries) {
      if (section.key is! String || section.value is! Map) {
        throw const FormatException('Invalid release deletion section');
      }
      final rows = <String, String>{};
      for (final row in (section.value as Map).entries) {
        final instant = _clock(row.value);
        if (row.key is! String ||
            (row.key as String).isEmpty ||
            instant == null ||
            row.value is! String ||
            !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(row.value as String)) {
          throw const FormatException('Invalid timestamped release deletion');
        }
        rows[row.key as String] = syncInstant(instant);
      }
      result[section.key as String] = rows;
    }
    return result;
  }

  static Map<String, dynamic> _mergeDocument(
    Map<String, dynamic> local,
    Map<String, dynamic> incoming,
    List<String> sections,
    String context,
    List<String> conflicts,
  ) {
    final localTime = _clock(local['updated_at']);
    final incomingTime = _clock(incoming['updated_at']);
    final isNew = local['revision'] == 0;
    final takeIncoming =
        isNew ||
        (incomingTime != null &&
            (localTime == null || incomingTime.isAfter(localTime)));
    final first = takeIncoming ? incoming : local;
    final second = takeIncoming ? local : incoming;
    final result = {...second, ...first, 'revision': local['revision']};
    final tombstones = _tombstones(local);
    for (final section in _tombstones(incoming).entries) {
      final rows = tombstones.putIfAbsent(section.key, () => {});
      for (final row in section.value.entries) {
        final prior = _clock(rows[row.key]);
        if (prior == null || _clock(row.value)!.isAfter(prior)) {
          rows[row.key] = row.value;
        }
      }
    }
    if (tombstones.isNotEmpty) result['deleted_records'] = tombstones;
    for (final section in sections) {
      final localRows = _rows(local[section], localTime);
      final incomingRows = _rows(incoming[section], incomingTime);
      final order = <String>{
        ..._rows(first[section], null).keys,
        ..._rows(second[section], null).keys,
      };
      final rows = <Map<String, dynamic>>[];
      for (final id in order) {
        final old = localRows[id];
        final other = incomingRows[id];
        Map<String, dynamic> row;
        var fromIncoming = false;
        if (old == null) {
          row = other!;
          fromIncoming = true;
        } else if (other == null) {
          row = old;
        } else {
          final oldTime = _clock(old['updated_at']);
          final otherTime = _clock(other['updated_at']);
          final newer =
              otherTime != null &&
              (oldTime == null || otherTime.isAfter(oldTime));
          // Rows are complete snapshots. Spreading the losing row here would
          // revive optional fields deliberately cleared by the winning edit.
          row = Map<String, dynamic>.from(newer ? other : old);
          fromIncoming = newer;
          if (!newer &&
              (oldTime == null || otherTime == null || oldTime == otherTime) &&
              !_same(old, other) &&
              !(section == 'assets' &&
                  _same(_importedAsset(old), _importedAsset(other)))) {
            conflicts.add('$context/$section/$id');
          }
          // A status history is append-only evidence even when two editors
          // changed the same record. Ordered membership/share arrays remain
          // the selected record's complete value, avoiding invalid hybrids.
          if (old['history'] is List && other['history'] is List) {
            row['history'] = _unionHistory(old['history'], other['history']);
          }
        }
        if (section == 'assets' && fromIncoming) row = _importedAsset(row);
        final deleted = _clock(tombstones[section]?[id]);
        final rowTime = _clock(row['updated_at']);
        if (deleted != null && (rowTime == null || !rowTime.isAfter(deleted))) {
          continue;
        }
        rows.add(row);
      }
      result[section] = rows;
    }
    return result;
  }

  static Map<String, Map<String, dynamic>> _rows(
    dynamic value,
    DateTime? fallback,
  ) => {
    for (final row in value as List)
      row['id'] as String: {
        ...Map<String, dynamic>.from(row as Map),
        // Freeze a legacy record's inherited clock before another record
        // advances the document clock. Otherwise old rows look newly edited.
        if (!row.containsKey('updated_at') && fallback != null)
          'updated_at': syncInstant(fallback),
      },
  };

  static List<dynamic> _unionHistory(List first, List second) => [
    ...first,
    for (final entry in second)
      if (!first.any((old) => _same(old, entry))) entry,
  ];

  static Map<String, dynamic> _importedAsset(Map<String, dynamic> row) => {
    ...row,
    if (row['validation'] == 'verified') ...{
      'validation': 'unverified',
      'verification_error': 'imported_verification_requires_local_check',
    },
  };

  static bool _same(Object? first, Object? second) {
    if (first is Map && second is Map) {
      return first.length == second.length &&
          first.keys.every(
            (key) => second.containsKey(key) && _same(first[key], second[key]),
          );
    }
    if (first is List && second is List) {
      return first.length == second.length &&
          Iterable<int>.generate(
            first.length,
          ).every((index) => _same(first[index], second[index]));
    }
    return first == second;
  }

  static void _checkDeletedReferences(
    Map<String, dynamic> catalog,
    Map<String, dynamic> workspace,
  ) {
    Set<String> deleted(Map<String, dynamic> document, String section) {
      final present = {for (final row in document[section] as List) row['id']};
      return _tombstones(
            document,
          )[section]?.keys.where((id) => !present.contains(id)).toSet() ??
          {};
    }

    void check(Object? id, Set<String> removed, String section) {
      if (id is String && removed.contains(id)) {
        throw FormatException(
          'Release ${workspace['release_id']} still references deleted $section $id',
        );
      }
    }

    void checkMany(Object? ids, Set<String> removed, String section) {
      if (ids is List) {
        for (final id in ids) {
          check(id, removed, section);
        }
      }
    }

    final artists = deleted(catalog, 'artists');
    final works = deleted(catalog, 'works');
    final tracks = deleted(workspace, 'tracks');
    final assets = deleted(workspace, 'assets');
    final campaigns = deleted(workspace, 'campaigns');
    final tasks = deleted(workspace, 'tasks');
    checkMany(workspace['artist_ids'], artists, 'artist');
    for (final track in workspace['tracks'] as List) {
      check(track['work_id'], works, 'work');
      if (track['credits'] is List) {
        for (final credit in track['credits'] as List) {
          if (credit is Map) check(credit['artist_id'], artists, 'artist');
        }
      }
    }
    for (final filing in workspace['rights_filings'] as List) {
      check(filing['work_id'], works, 'work');
      checkMany(filing['evidence_asset_ids'], assets, 'asset');
    }
    for (final post in workspace['communications'] as List) {
      check(post['track_id'], tracks, 'track');
      check(post['campaign_id'], campaigns, 'campaign');
      checkMany(post['asset_ids'], assets, 'asset');
    }
    for (final asset in workspace['assets'] as List) {
      check(asset['track_id'], tracks, 'track');
      check(asset['parent_asset_id'], assets, 'asset');
    }
    for (final campaign in workspace['campaigns'] as List) {
      checkMany(campaign['track_ids'], tracks, 'track');
    }
    for (final task in workspace['tasks'] as List) {
      checkMany(task['depends_on'], tasks, 'task');
    }
  }
}

class ReleaseWorkspaceTransferResult {
  const ReleaseWorkspaceTransferResult({
    required this.catalogChanged,
    required this.workspacesChanged,
    this.skippedReleaseIds = const [],
    this.conflicts = const [],
  });

  final bool catalogChanged;
  final int workspacesChanged;

  /// Metadata for releases not in the destination's live Hive release set.
  final List<String> skippedReleaseIds;

  /// Same row, different content, no strictly newer incoming clock. Local
  /// content is retained. The original backup/snapshot remains the evidence.
  final List<String> conflicts;
}
