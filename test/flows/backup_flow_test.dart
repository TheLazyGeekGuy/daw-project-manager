// Local backup — Flatpak's only one — over real projects: a library with
// stacks, MIDI read from the projects, a collection, notes and a release is
// backed up, the database thrown away, and the backup read into the empty
// one. Everything comes back as it was, and a rescan adds nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/midi_collection.dart';
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/models/scan_mode.dart';
import 'package:daw_project_manager/services/backup_service.dart';
import 'package:daw_project_manager/ui/midi_collection_actions.dart' show collectionItemFor;

import '../helpers/hive_test_helper.dart';
import 'flow_library.dart';

/// What a row is, for comparing a library before and after.
Map<String, Object?> _row(MusicProject r) => {
      'path': r.filePath,
      'name': r.displayName,
      'notes': r.notes,
      'bpm': r.bpm,
      'key': r.musicalKey,
      'stack': r.stackId,
      'virtual': r.isVirtual,
      'stats': r.stats?.toMap(),
      'metadataScanned': r.metadataScanned,
    };

void main() {
  late FlowLibrary lib;

  setUp(() async => lib = await FlowLibrary.open(only: [
        'flstudio/MegaBeat - Save the Bass (FL 10 + FL 20)',
        'cubase/Klone - NN (Cubase 5)',
        'ableton/Audio Crawler vs Nordic Enigma - NN1 (Live 11)',
      ]));
  tearDown(() async => lib.close());

  test('back up, lose the database, restore: the library as it was', () async {
    await lib.repo.updateRootScanMode(lib.root.id, ScanMode.versionStack);
    await lib.scan();
    await lib.deepScan();

    // Things only the user made.
    final nn1 = lib.projects.singleWhere((r) => r.displayName == 'NN1');
    await lib.repo.updateProject(nn1.copyWith(notes: 'Collab with Nordic Enigma — send stems'));
    final stack = lib.projects.singleWhere((r) => r.isVirtual);
    await lib.repo.addRelease(Release(
      id: 'release-1',
      title: 'Night Drive EP',
      trackIds: [nn1.id, stack.id],
      releaseDate: DateTime.utc(2026, 11, 20),
    ));
    final stored = await lib.repo.midiClips.getAll();
    final collection = await lib.repo.midiCollections.create('Hooks');
    await lib.repo.midiCollections.addItems(collection.id, [
      for (final entry in stored.entries)
        for (final clip in entry.value.clips.take(2)) collectionItemFor(clip, projectId: entry.key),
    ]);

    final rowsBefore = {for (final r in lib.projects) r.id: _row(r)};
    final clipsBefore = {
      for (final e in stored.entries) e.key: [for (final c in e.value.clips) c.contentKey],
    };
    final collectionBefore = (await lib.repo.midiCollections.get(collection.id))!;
    expect(clipsBefore.values.expand((c) => c), isNotEmpty);

    final profiles = await HiveTestHelper.createProfileRepository();
    final backup = await BackupService.buildBackupJson(
      projectRepo: lib.repo,
      profileRepo: profiles,
      profileId: lib.profileId,
    );

    // A new machine: the project files, and no database.
    await lib.wipeDatabase();
    expect(lib.projects, isEmpty);

    final result = await BackupService.importBackupJson(
      backup,
      projectRepo: lib.repo,
      profileRepo: await HiveTestHelper.createProfileRepository(),
      currentProfileId: lib.profileId,
      importMode: ImportMode.replace,
    );
    expect(result.projectsCount, rowsBefore.length);

    expect({for (final r in lib.projects) r.id: _row(r)}, rowsBefore);
    final clipsAfter = await lib.repo.midiClips.getAll();
    expect({
      for (final e in clipsAfter.entries) e.key: [for (final c in e.value.clips) c.contentKey],
    }, clipsBefore);
    final collectionAfter = (await lib.repo.midiCollections.get(collection.id))!;
    expect(collectionAfter.name, 'Hooks');
    expect(collectionAfter.items.map((i) => i.clip.contentKey).toList(),
        collectionBefore.items.map((i) => i.clip.contentKey).toList());
    final release = lib.repo.getAllReleases().single;
    expect(release.title, 'Night Drive EP');
    expect(release.trackIds, [nn1.id, stack.id]);
    expect(lib.repo.getRoots().single.path, lib.projectsDir.path);

    // Scanning the restored library finds what it already holds.
    lib.root = lib.repo.getRoots().single;
    await lib.scan();
    expect({for (final r in lib.projects) r.id: _row(r)}, rowsBefore);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
