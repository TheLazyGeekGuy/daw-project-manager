import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Native DPM release metadata, stored independently from the legacy Hive
/// release adapter. This avoids breaking previously saved user profiles.
///
/// The store is local-only and never communicates with Katsu or any provider.
class ReleaseWorkspaceStore {
  const ReleaseWorkspaceStore(this.directory);
  final Directory directory;

  String _safeId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid release identifier');
    }
    return id;
  }

  File _file(String id) => File(p.join(directory.path, '${_safeId(id)}.json'));

  Future<Map<String, dynamic>> read(String releaseId) async {
    final file = _file(releaseId);
    if (!await file.exists()) {
      return {
        'schema_version': 1,
        'release_id': releaseId,
        'artist_ids': <String>[],
        'collection_type': 'album',
        'tracks': <Object>[],
        'rights_filings': <Object>[],
        'distribution': <Object>[],
        'communications': <Object>[],
      };
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['release_id'] != releaseId ||
        decoded['schema_version'] != 1) {
      throw const FormatException('Invalid release workspace document');
    }
    return decoded;
  }

  /// Publish a full new snapshot; never modify an existing source in-place.
  ///
  /// The caller must pass a valid release ID from DPM's Release record.
  Future<void> save(String releaseId, Map<String, dynamic> value) async {
    _safeId(releaseId);
    if (value['release_id'] != releaseId || value['schema_version'] != 1) {
      throw const FormatException('Release workspace ID/schema mismatch');
    }
    await directory.create(recursive: true);
    final destination = _file(releaseId);
    final staging = File(p.join(
      directory.path,
      '.${releaseId}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    ));
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert(value);
      await staging.writeAsString(encoded, flush: true);
      // Parse again before promotion to reject malformed/unserializable data.
      if (jsonDecode(await staging.readAsString()) is! Map) {
        throw const FormatException('Invalid staged release workspace');
      }
      // Keep each previous version as a recoverable snapshot.
      if (await destination.exists()) {
        final backup = File(p.join(
          directory.path,
          '.${releaseId}.${DateTime.now().microsecondsSinceEpoch}.previous.json',
        ));
        await destination.copy(backup.path);
      }
      await staging.rename(destination.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }
}
