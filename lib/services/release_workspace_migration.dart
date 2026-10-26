import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Lossless envelope migrations for native release metadata.
///
/// These functions return new maps and never write to disk. Unknown fields and
/// list records are retained; saving an edit is a separate explicit operation.
class ReleaseWorkspaceMigration {
  static const currentVersion = 2;
  static const recordSections = [
    'tracks',
    'rights_filings',
    'distribution',
    'communications',
    'assets',
    'campaigns',
    'tasks',
  ];

  static Map<String, dynamic> empty(String releaseId, {String? profileId}) => {
    'schema_version': currentVersion,
    'revision': 0,
    'release_id': releaseId,
    'profile_id': ?profileId,
    'artist_ids': <String>[],
    'collection_type': 'album',
    for (final key in recordSections) key: <Object>[],
  };

  static Map<String, dynamic> migrate(
    Map<String, dynamic> source,
    String releaseId, {
    String? profileId,
  }) {
    final version = source['schema_version'];
    if (source['release_id'] != releaseId ||
        (version != 1 && version != currentVersion)) {
      throw const FormatException('Release workspace ID/schema mismatch');
    }
    validateProfile(source, profileId);
    final result = {
      ...empty(releaseId, profileId: profileId),
      ...source,
      'schema_version': currentVersion,
      'profile_id': ?profileId,
    };
    validateRevision(result);
    final artists = result['artist_ids'];
    if (artists is! List || artists.any((entry) => entry is! String)) {
      throw const FormatException('artist_ids must be a list of strings');
    }
    if (result['collection_type'] is! String) {
      throw const FormatException('collection_type must be a string');
    }
    for (final section in recordSections) {
      validateRecordList(result, section);
    }
    if (version == 1) {
      for (final section in [
        'rights_filings',
        'distribution',
        'communications',
      ]) {
        final records = result[section] as List;
        result[section] = [
          for (var index = 0; index < records.length; index++)
            _legacyRecord(
              Map<String, dynamic>.from(records[index] as Map),
              releaseId,
              section,
              index,
            ),
        ];
      }
    }
    return result;
  }

  static Map<String, dynamic> _legacyRecord(
    Map<String, dynamic> record,
    String releaseId,
    String section,
    int index,
  ) {
    final originalId = record['id'];
    if (originalId == null || originalId == '') {
      final key = sha256
          .convert(utf8.encode('$releaseId:$section:$index'))
          .toString()
          .substring(0, 16);
      record['id'] = 'legacy-$section-$key';
    }
    if (section == 'communications' &&
        (record['title'] == null || record['title'] == '')) {
      final platform = record['platform'];
      record['title'] = platform is String && platform.trim().isNotEmpty
          ? platform.trim()
          : 'Communication ${index + 1}';
    }
    final platforms = record['platforms'];
    if (section == 'distribution' &&
        platforms is List &&
        platforms.every((entry) => entry is Map)) {
      record['platforms'] = [
        for (
          var platformIndex = 0;
          platformIndex < platforms.length;
          platformIndex++
        )
          _legacyRecord(
            Map<String, dynamic>.from(platforms[platformIndex] as Map),
            releaseId,
            'distribution-$index-platforms',
            platformIndex,
          ),
      ];
    }
    return record;
  }

  static void validateRevision(Map<String, dynamic> value) {
    final revision = value['revision'];
    if (revision is! int || revision < 0) {
      throw const FormatException('revision must be a non-negative integer');
    }
  }

  static void validateProfile(Map<String, dynamic> value, String? profileId) {
    final stored = value['profile_id'];
    if (stored != null && (stored is! String || stored.isEmpty)) {
      throw const FormatException('Invalid document profile identifier');
    }
    if (profileId != null && stored != null && stored != profileId) {
      throw const FormatException('Document belongs to another profile');
    }
  }

  static void validateRecordList(Map<String, dynamic> value, String section) {
    final records = value[section];
    if (records is! List || records.any((entry) => entry is! Map)) {
      throw FormatException('$section must be a list of records');
    }
  }
}
