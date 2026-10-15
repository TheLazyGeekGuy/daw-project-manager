import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// What kind of row a [SyncTombstone] stands for.
enum TombstoneKind { project, release }

/// A record that a project or release was deleted on purpose.
///
/// Drive sync merges by union — a row present in one copy and absent in the
/// other is kept — so a plain deletion is undone by the next sync from a
/// device that still has the row. The tombstone travels instead and wins
/// over any copy that was last changed before the deletion (a project
/// edited elsewhere *after* it was deleted here comes back, as the newer
/// side). Ids are random uuids, so a rescanned file arrives as a new row a
/// tombstone never matches.
class SyncTombstone {
  const SyncTombstone({
    required this.id,
    required this.kind,
    required this.deletedAt,
  });

  final String id;
  final TombstoneKind kind;
  final DateTime deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'deletedAt': deletedAt.toUtc().toIso8601String(),
      };

  static SyncTombstone? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = TombstoneKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final deletedAt = DateTime.tryParse('${json['deletedAt']}');
    if (id is! String || kind == null || deletedAt == null) return null;
    return SyncTombstone(id: id, kind: kind, deletedAt: deletedAt);
  }

  /// Whether this deletion beats a copy last changed at [updatedAt]. A
  /// release has no `updatedAt`, so a deleted release always stays deleted.
  bool beats(DateTime? updatedAt) =>
      updatedAt == null || deletedAt.isAfter(updatedAt);
}

/// Union of two tombstone sets, the later deletion winning per id.
Map<String, SyncTombstone> mergeTombstones(
  Map<String, SyncTombstone> a,
  Iterable<SyncTombstone> b,
) {
  final merged = Map<String, SyncTombstone>.of(a);
  for (final t in b) {
    final existing = merged[t.id];
    if (existing == null || t.deletedAt.isAfter(existing.deletedAt)) {
      merged[t.id] = t;
    }
  }
  return merged;
}

/// Tombstones decoded from a backup's `deletedRecords`, skipping anything
/// malformed. Absent on backups written before deletions synced.
List<SyncTombstone> tombstonesFromJson(Object? json) => [
      if (json is List)
        for (final entry in json) ?SyncTombstone.fromJson(entry),
    ];

/// The device's tombstones, in their own box — sync bookkeeping, not user
/// data, so they go to Drive but not into a local backup file (a backup is
/// a point-in-time copy; restoring one is meant to bring things back).
///
/// Tombstones older than [maxAge] are dropped on write: by then every device
/// that syncs at all has seen them.
class SyncTombstoneStore {
  static const boxName = 'sync_tombstones';
  static const maxAge = Duration(days: 365);

  static Future<Box<String>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<String>(boxName)
      : await Hive.openBox<String>(boxName);

  static Future<void> record(
    TombstoneKind kind,
    Iterable<String> ids, {
    DateTime? at,
  }) async {
    if (ids.isEmpty) return;
    final deletedAt = (at ?? DateTime.now()).toUtc();
    await putAll([
      for (final id in ids)
        SyncTombstone(id: id, kind: kind, deletedAt: deletedAt),
    ]);
  }

  static Future<Map<String, SyncTombstone>> all() async {
    final box = await _box();
    return {
      for (final raw in box.values)
        if (SyncTombstone.fromJson(_decode(raw)) case final t?) t.id: t,
    };
  }

  /// Merges [incoming] in (the later deletion wins) and returns the result.
  static Future<Map<String, SyncTombstone>> putAll(
    Iterable<SyncTombstone> incoming, {
    DateTime? now,
  }) async {
    final box = await _box();
    final merged = mergeTombstones(await all(), incoming);
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(maxAge);
    final stale = [
      for (final t in merged.values)
        if (t.deletedAt.isBefore(cutoff)) t.id,
    ];
    for (final id in stale) {
      merged.remove(id);
    }
    await box.deleteAll(stale);
    await box.putAll({
      for (final t in merged.values) t.id: jsonEncode(t.toJson()),
    });
    return merged;
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
