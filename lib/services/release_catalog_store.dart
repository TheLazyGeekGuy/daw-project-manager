import 'dart:io';

import 'release_workspace_migration.dart';
import 'release_workspace_store.dart';

/// Shared artists, rightsholders, works, recordings and playlists for one DPM
/// profile. Catalog transactions are independent of release-workspace writes.
class ReleaseCatalogStore {
  const ReleaseCatalogStore(this.directory, {this.profileId});

  static const sections = [
    'artists',
    'holders',
    'works',
    'tracks',
    'playlists',
  ];
  final Directory directory;
  final String? profileId;

  Map<String, dynamic> _empty() => {
    'schema_version': 1,
    'revision': 0,
    if (profileId != null) 'profile_id': profileId,
    for (final section in sections) section: <Object>[],
  };

  ReleaseJsonDocumentStore get _store {
    if (profileId != null) ReleaseJsonDocumentStore.safeId(profileId!);
    return ReleaseJsonDocumentStore(
      directory,
      'library',
      subdirectory: 'catalog',
      empty: _empty,
      normalize: _normalize,
    );
  }

  Future<Map<String, dynamic>> read() => _store.read();

  /// Validates a proposed catalog without reading or writing profile files.
  /// Used by transfer preflight before starting independent document commits.
  Map<String, dynamic> normalize(Map<String, dynamic> value) =>
      _normalize(value);

  Future<void> save(
    Map<String, dynamic> value, {
    int? expectedRevision,
    bool preserveTimestamps = false,
  }) => _store.save(
    value,
    expectedRevision: expectedRevision,
    preserveTimestamps: preserveTimestamps,
  );

  Map<String, dynamic> _normalize(Map<String, dynamic> source) {
    if (source['schema_version'] != 1) {
      throw const FormatException('Unsupported music catalog schema');
    }
    ReleaseWorkspaceMigration.validateProfile(source, profileId);
    final result = {
      ..._empty(),
      ...source,
      if (profileId != null) 'profile_id': profileId,
    };
    ReleaseWorkspaceMigration.validateRevision(result);
    final ids = <String, Set<String>>{};
    for (final section in sections) {
      ReleaseWorkspaceMigration.validateRecordList(result, section);
      final known = <String>{};
      for (final record in result[section] as List) {
        final id = record['id'];
        if (id is! String || id.trim().isEmpty || !known.add(id)) {
          throw FormatException('Missing or duplicate $section identifier');
        }
        final titleField = section == 'artists' || section == 'holders'
            ? 'name'
            : 'title';
        final title = record[titleField];
        if (title is! String || title.trim().isEmpty) {
          throw FormatException('$section records need a $titleField');
        }
      }
      ids[section] = known;
    }
    for (final artist in result['artists'] as List) {
      _strings(artist['aliases'], 'artist aliases', optional: true);
      _strings(artist['roles'], 'artist roles', optional: true);
    }
    for (final work in result['works'] as List) {
      final shares = work['shares'];
      if (shares == null) continue;
      if (shares is! List) {
        throw const FormatException('Work shares must be a list');
      }
      var total = 0.0;
      for (final share in shares) {
        if (share is! Map || !ids['holders']!.contains(share['holder_id'])) {
          throw const FormatException(
            'Work share references an unknown rightsholder',
          );
        }
        final percentage = share['percentage'];
        if (percentage is! num ||
            !percentage.isFinite ||
            percentage < 0 ||
            percentage > 100) {
          throw const FormatException(
            'Work share must be a percentage between 0 and 100',
          );
        }
        total += percentage;
      }
      // An unfinished rights allocation is allowed; oversubscription is not.
      if (total > 100.000001) {
        throw const FormatException('Work shares exceed 100 percent');
      }
    }
    for (final track in result['tracks'] as List) {
      final workId = track['work_id'];
      if (workId != null && workId != '' && !ids['works']!.contains(workId)) {
        throw const FormatException('Track references an unknown work');
      }
      final credits = track['credits'];
      if (credits == null) continue;
      if (credits is! List) {
        throw const FormatException('Track credits must be a list');
      }
      for (final credit in credits) {
        if (credit is! Map || !ids['artists']!.contains(credit['artist_id'])) {
          throw const FormatException(
            'Track credit references an unknown artist',
          );
        }
      }
    }
    for (final playlist in result['playlists'] as List) {
      final trackIds = playlist['track_ids'];
      _strings(trackIds, 'playlist track_ids');
      if ((trackIds as List).any((id) => !ids['tracks']!.contains(id))) {
        throw const FormatException('Playlist references an unknown track');
      }
    }
    return result;
  }

  static void _strings(dynamic value, String name, {bool optional = false}) {
    if (value == null && optional) return;
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$name must be a list of strings');
    }
  }
}
