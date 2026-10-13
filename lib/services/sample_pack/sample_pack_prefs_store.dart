import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../player_volume_store.dart';

/// What the sample pack export was last run with, offered again next time.
///
/// Device-local, like the archive folder: the library folders are paths on
/// this machine, and which profiles to export is a choice made here — so
/// neither Drive sync nor local backup carries it.
class SamplePackPrefs {
  const SamplePackPrefs({
    this.libraryFolders = const [],
    this.includeOwnAudio = false,
    this.includeMidi = true,
    this.profileIds,
  });

  final List<String> libraryFolders;
  final bool includeOwnAudio;
  final bool includeMidi;

  /// The profiles last exported; null (never run) means all of them.
  final List<String>? profileIds;

  Map<String, dynamic> toJson() => {
    'libraryFolders': libraryFolders,
    'includeOwnAudio': includeOwnAudio,
    'includeMidi': includeMidi,
    'profileIds': ?profileIds,
  };

  static SamplePackPrefs fromJson(Object? json) {
    if (json is! Map) return const SamplePackPrefs();
    List<String>? strings(Object? v) =>
        v is List ? [for (final s in v) if (s is String) s] : null;
    return SamplePackPrefs(
      libraryFolders: strings(json['libraryFolders']) ?? const [],
      includeOwnAudio: json['includeOwnAudio'] == true,
      includeMidi: json['includeMidi'] != false,
      profileIds: strings(json['profileIds']),
    );
  }
}

class SamplePackPrefsStore {
  const SamplePackPrefsStore._();

  static const String key = 'sample_pack_prefs';

  static Future<SamplePackPrefs> load() async {
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      final raw = box.get(key);
      return raw == null
          ? const SamplePackPrefs()
          : SamplePackPrefs.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[SamplePackPrefs] failed to load: $e');
      return const SamplePackPrefs();
    }
  }

  static Future<void> save(SamplePackPrefs prefs) async {
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      await box.put(key, jsonEncode(prefs.toJson()));
    } catch (e) {
      debugPrint('[SamplePackPrefs] failed to save: $e');
    }
  }
}
