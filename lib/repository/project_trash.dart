import 'package:hive_ce/hive.dart';

import '../models/music_project.dart';
import '../models/stored_midi_clips.dart';

/// A project in "Recently deleted", and when it went there.
class TrashedProject {
  const TrashedProject({required this.project, required this.deletedAt});
  final MusicProject project;
  final DateTime deletedAt;

  /// When it is removed for good.
  DateTime get expiresAt => deletedAt.add(ProjectTrash.keepFor);
}

/// "Recently deleted" for one profile: projects deleted from the library are
/// kept here — whole, notes, to-dos, work time and MIDI clips included — for
/// [keepFor], and can be put back exactly as they were.
///
/// Device-local, like an OS's trash: it is in neither Drive sync nor local
/// backup. The deletion itself still syncs (as a tombstone), and a restore
/// syncs back as the newer change.
class ProjectTrash {
  ProjectTrash(this.profileId);

  final String profileId;

  static const keepFor = Duration(days: 30);

  static String projectsBoxName(String profileId) => '${profileId}_trash';
  static String infoBoxName(String profileId) => '${profileId}_trash_info';
  static String clipsBoxName(String profileId) => '${profileId}_trash_midi';

  Future<Box<MusicProject>> _projects() async {
    final name = projectsBoxName(profileId);
    return Hive.isBoxOpen(name)
        ? Hive.box<MusicProject>(name)
        : Hive.openBox<MusicProject>(name);
  }

  // id -> when it was deleted (ISO 8601, UTC).
  Future<Box<String>> _info() async {
    final name = infoBoxName(profileId);
    return Hive.isBoxOpen(name) ? Hive.box<String>(name) : Hive.openBox<String>(name);
  }

  // id -> StoredMidiClips.toMap(); lazy, as clips are only read on restore.
  Future<LazyBox<Map>> _clips() async {
    final name = clipsBoxName(profileId);
    return Hive.isBoxOpen(name) ? Hive.lazyBox<Map>(name) : Hive.openLazyBox<Map>(name);
  }

  /// Keeps [projects] (and their [clips], by project id).
  Future<void> add(
    Iterable<MusicProject> projects, {
    Map<String, StoredMidiClips> clips = const {},
    DateTime? at,
  }) async {
    final list = projects.toList();
    if (list.isEmpty) return;
    final when = (at ?? DateTime.now()).toUtc().toIso8601String();
    final projectsBox = await _projects();
    final infoBox = await _info();
    final clipsBox = await _clips();
    await projectsBox.putAll({for (final p in list) p.id: p});
    await infoBox.putAll({for (final p in list) p.id: when});
    for (final p in list) {
      final c = clips[p.id];
      if (c != null) await clipsBox.put(p.id, c.toMap());
    }
  }

  /// Everything in the trash, most recently deleted first. Anything past
  /// [keepFor] is removed for good first.
  Future<List<TrashedProject>> list({DateTime? now}) async {
    await purgeExpired(now: now);
    final projectsBox = await _projects();
    final infoBox = await _info();
    final items = [
      for (final p in projectsBox.values)
        TrashedProject(
          project: p,
          deletedAt: DateTime.tryParse(infoBox.get(p.id) ?? '') ?? DateTime.now().toUtc(),
        ),
    ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<TrashedProject?> get(String id) async {
    final p = (await _projects()).get(id);
    if (p == null) return null;
    final at = DateTime.tryParse((await _info()).get(id) ?? '');
    return TrashedProject(project: p, deletedAt: at ?? DateTime.now().toUtc());
  }

  Future<StoredMidiClips?> clipsOf(String id) async =>
      StoredMidiClips.tryParse(await (await _clips()).get(id));

  /// Replaces each kept project [change] returns a new value for (null: leave
  /// it), keeping when it was deleted — so it still expires on the same day.
  /// Returns how many changed.
  Future<int> update(MusicProject? Function(MusicProject project) change) async {
    final projectsBox = await _projects();
    final changed = <String, MusicProject>{
      for (final project in projectsBox.values) project.id: ?change(project),
    };
    if (changed.isNotEmpty) await projectsBox.putAll(changed);
    return changed.length;
  }

  /// Takes [ids] out of the trash (restored, or deleted for good).
  Future<void> remove(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (await _projects()).deleteAll(list);
    await (await _info()).deleteAll(list);
    await (await _clips()).deleteAll(list);
  }

  Future<void> empty() async {
    await (await _projects()).clear();
    await (await _info()).clear();
    await (await _clips()).clear();
  }

  Future<void> purgeExpired({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(keepFor);
    final infoBox = await _info();
    final expired = [
      for (final key in infoBox.keys.cast<String>())
        if ((DateTime.tryParse(infoBox.get(key) ?? '') ?? cutoff).isBefore(cutoff)) key,
    ];
    await remove(expired);
  }
}
