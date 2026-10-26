import 'dart:convert';

/// Merges a current native Release snapshot into its richer workflow document.
///
/// The native release owns its summary and project links. Workflow-only tracks,
/// custom metadata, and manually added assets remain in the workflow. Callers
/// must supply the current native snapshot, not optional form defaults.
class ReleaseNativeBridge {
  static Map<String, dynamic> mergeWorkspace({
    required Map<String, dynamic> workspace,
    required List<Map<String, dynamic>> nativeTracks,
    required List<Map<String, dynamic>> nativeAssets,
    required String title,
    String? description,
    String? releaseDate,
  }) {
    final result = _copy(workspace);
    result['title'] = title;
    // Explicit null clears known fields through the document store's partial
    // top-level merge; omitting them would restore the previously saved value.
    result['description'] = description;
    result['release_date'] = releaseDate;
    result['tracks'] = _mergeTracks(
      _records(result, 'tracks'),
      nativeTracks.map(_copy).toList(),
    );
    result['assets'] = _mergeAssets(
      _records(result, 'assets'),
      nativeAssets.map(_copy).toList(),
    );
    return result;
  }

  static List<Map<String, dynamic>> _mergeTracks(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> native,
  ) {
    final nativeByProject = <String, Map<String, dynamic>>{};
    for (final track in native) {
      final id = _requiredId(track);
      final project = _nonEmptyString(track['project_id']) ?? id;
      if (nativeByProject.containsKey(project)) {
        throw FormatException('Duplicate native project link: $project');
      }
      nativeByProject[project] = track;
    }

    final slots = <({Map<String, dynamic> row, String? project})>[];
    final linked = <String, List<Map<String, dynamic>>>{};
    for (final row in existing) {
      // Before project_id existed, the row ID was the native project ID.
      final id = _nonEmptyString(row['id']);
      final project =
          _nonEmptyString(row['project_id']) ??
          (nativeByProject.containsKey(id) ? id : null);
      if (project == null) {
        slots.add((row: row, project: null));
        continue;
      }
      final current = nativeByProject[project];
      if (current == null) continue; // Explicitly removed native project link.
      final merged = {...current, ...row, 'project_id': project};
      linked.putIfAbsent(project, () => []).add(merged);
      slots.add((row: merged, project: project));
    }

    final usedIds = {
      for (final slot in slots)
        if (slot.row['id'] is String) slot.row['id'] as String,
    };
    final ordered = <Map<String, dynamic>>[];
    for (final entry in nativeByProject.entries) {
      final matches = linked[entry.key];
      if (matches != null) {
        // Separate recordings may intentionally refer to the same project.
        ordered.addAll(matches);
      } else {
        final id = _availableId(_requiredId(entry.value), usedIds);
        ordered.add({...entry.value, 'id': id, 'project_id': entry.key});
      }
    }

    // Keep manual tracks in their surviving slots. Refill the linked slots in
    // native order, then append the remaining links without dropping metadata.
    var index = 0;
    return [
      for (final slot in slots)
        slot.project == null ? slot.row : ordered[index++],
      ...ordered.skip(index),
    ];
  }

  static List<Map<String, dynamic>> _mergeAssets(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> native,
  ) {
    final nativeById = <String, Map<String, dynamic>>{};
    for (final asset in native) {
      final id = _requiredId(asset);
      if (nativeById.containsKey(id)) {
        throw FormatException('Duplicate native asset ID: $id');
      }
      nativeById[id] = asset;
    }
    final matched = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final asset in existing) {
      final current = nativeById[asset['id']];
      if (current == null) {
        if (asset['native_release_asset'] != true) result.add(asset);
        continue;
      }
      matched.add(current['id'] as String);
      final merged = {
        ...current,
        ...asset,
        'path': current['path'],
        'native_release_asset': true,
      };
      if (current['path'] != asset['path']) _resetVerification(merged);
      result.add(merged);
    }
    for (final asset in nativeById.values) {
      if (matched.contains(asset['id'])) continue;
      final added = {...asset, 'native_release_asset': true};
      _resetVerification(added);
      result.add(added);
    }
    return result;
  }

  static void _resetVerification(Map<String, dynamic> asset) {
    asset['validation'] = 'unverified';
    for (final key in const [
      'sha256',
      'bytes',
      'verified_at',
      'resolved_path',
      'checked_at',
      'verification_error',
      'observed_sha256',
      'observed_bytes',
    ]) {
      asset.remove(key);
    }
  }

  static String _availableId(String preferred, Set<String> used) {
    if (used.add(preferred)) return preferred;
    final base = preferred.length > 100
        ? preferred.substring(0, 100)
        : preferred;
    var candidate = '$base-native';
    var suffix = 2;
    while (!used.add(candidate)) {
      candidate = '$base-native-${suffix++}';
    }
    return candidate;
  }

  static String _requiredId(Map<String, dynamic> record) {
    final id = _nonEmptyString(record['id']);
    if (id == null) throw const FormatException('Native record requires an ID');
    return id;
  }

  static String? _nonEmptyString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<Map<String, dynamic>> _records(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value == null) return [];
    if (value is! List || value.any((row) => row is! Map)) {
      throw FormatException('$key must be a list of records');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> source) =>
      jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}
