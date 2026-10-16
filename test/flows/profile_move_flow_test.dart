// Songs between artists, and Recently deleted, over real projects in one
// database with two profiles: a stacked song moves to the collaboration's
// profile with its files, another moves leaving its files where they are,
// and a deleted project comes back from the trash — details, MIDI and all.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/scan_mode.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/services/profile_move_service.dart';
import 'package:daw_project_manager/services/scan_import_service.dart';

import '../helpers/hive_test_helper.dart';
import 'flow_library.dart';

Map<String, String> _contents(Directory dir) => {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: dir.path): sha1.convert(f.readAsBytesSync()).toString(),
    };

void main() {
  late FlowLibrary lib;
  late ProjectRepository collab;
  late Directory collabDir;

  setUp(() async {
    lib = await FlowLibrary.open(only: [
      'flstudio/MegaBeat - Save the Bass (FL 10 + FL 20)',
      'ableton/Audio Crawler vs Nordic Enigma - NN1 (Live 11)',
      'cubase/Klone - NN (Cubase 5)',
    ]);
    await lib.repo.updateRootScanMode(lib.root.id, ScanMode.versionStack);
    await lib.scan();
    await lib.deepScan();
    collab = await HiveTestHelper.createRepository(profileId: 'collab');
    collabDir = await Directory(p.join(lib.scratch.path, 'Collab')).create();
    await collab.addRoot(collabDir.path);
  });
  tearDown(() async => lib.close());

  Future<void> rescanCollab() async {
    final root = collab.getRoots().single;
    await importProjectsFromRoot(collab, root.id, root.path);
  }

  test('a stacked song moves with its files, versions and MIDI', () async {
    final megaBeat = lib.fixtures.singleWhere((f) => f.name.startsWith('MegaBeat'));
    final version = lib.projectOf(megaBeat.projectFiles.last);
    final stack = lib.projects.singleWhere((r) => r.id == version.stackId);
    await lib.repo.updateProject(stack.copyWith(notes: 'Remix for the collab EP'));
    final ids = {stack.id, for (final f in megaBeat.projectFiles) lib.projectOf(f).id};
    final files = _contents(megaBeat.folder);
    final clips = {for (final id in ids) id: (await lib.repo.midiClips.get(id))?.clips.length};

    final plan = planProfileMove(lib.repo, version);
    await moveSongToProfile(source: lib.repo, target: collab, plan: plan, destinationFolder: collabDir.path);

    // The files: moved, byte for byte, none left behind.
    final moved = Directory(p.join(collabDir.path, p.basename(megaBeat.folder.path)));
    expect(_contents(moved), files);
    expect(megaBeat.folder.existsSync(), isFalse);

    // The rows: the same song in the other profile — every version.
    expect(lib.projects.where((r) => ids.contains(r.id)), isEmpty);
    expect({for (final r in collab.getAllProjects()) r.id}, ids);
    expect(collab.getAllProjects().singleWhere((r) => r.isVirtual).notes, 'Remix for the collab EP');
    for (final id in ids) {
      expect((await collab.midiClips.get(id))?.clips.length, clips[id], reason: 'MIDI of $id');
      expect(await lib.repo.midiClips.get(id), isNull);
    }

    // Neither profile's next scan makes a second copy.
    await lib.scan();
    await rescanCollab();
    expect(lib.projects.where((r) => r.displayName.startsWith('MegaBeat')), isEmpty);
    expect({for (final r in collab.getAllProjects()) r.id}, ids);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a song moved without its files is left out of the old profile\'s scans', () async {
    final nn1 = lib.projects.singleWhere((r) => r.displayName == 'NN1');
    final plan = planProfileMove(lib.repo, nn1);
    await moveSongToProfile(source: lib.repo, target: collab, plan: plan);

    expect(File(nn1.filePath).existsSync(), isTrue, reason: 'the files stay where they are');
    expect(collab.getById(nn1.id), isNotNull);
    await lib.scan();
    expect(lib.projects.where((r) => p.normalize(r.filePath) == p.normalize(nn1.filePath)), isEmpty,
        reason: 'its path is excluded in the old profile, or the scan brings it back');
  });

  test('deleted, rescanned as new, restored from Recently deleted', () async {
    final nn = lib.projects.singleWhere((r) => r.filePath.endsWith('NN.cpr'));
    await lib.repo.updateProject(nn.copyWith(notes: 'Klone era, 2009'));
    final clips = (await lib.repo.midiClips.get(nn.id))!.clips.map((c) => c.contentKey).toList();
    expect(clips, isNotEmpty);

    await lib.repo.deleteProjects([nn.id]);
    expect(lib.repo.getById(nn.id), isNull);
    expect(await lib.repo.midiClips.get(nn.id), isNull);
    expect(await lib.repo.trash.get(nn.id), isNotNull);

    // Its folder isn't excluded, so the next scan adds it back — empty.
    await lib.scan();
    final rescanned = lib.projects.singleWhere((r) => p.normalize(r.filePath) == p.normalize(nn.filePath));
    expect(rescanned.id, isNot(nn.id));
    expect(rescanned.notes ?? '', isEmpty);

    // Restoring takes its place, with what it had.
    expect(await lib.repo.restoreFromTrash(nn.id), isTrue);
    final rows = lib.projects.where((r) => p.normalize(r.filePath) == p.normalize(nn.filePath)).toList();
    expect(rows.map((r) => r.id), [nn.id], reason: 'one row for the file: the restored one');
    expect(rows.single.notes, 'Klone era, 2009');
    expect((await lib.repo.midiClips.get(nn.id))!.clips.map((c) => c.contentKey).toList(), clips);
    expect(await lib.repo.trash.get(nn.id), isNull);
  });
}
