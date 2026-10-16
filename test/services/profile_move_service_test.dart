import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/models/project_event.dart';
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/models/stored_midi_clips.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/repository/sync_tombstones.dart';
import 'package:daw_project_manager/services/profile_move_service.dart';
import 'package:daw_project_manager/services/project_move_service.dart';
import 'package:daw_project_manager/utils/root_overlap.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// Moving a song from one artist's profile to another's.
void main() {
  late Directory tempDir;
  late Directory disk;
  late ProjectRepository solo; // "Audio Crawler"
  late ProjectRepository collab; // "Audio Crawler vs Reisser"
  late String soloRoot;
  late String collabRoot;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    disk = await Directory.systemTemp.createTemp('profile_move_');
    solo = await HiveTestHelper.createRepository(profileId: 'solo');
    collab = await HiveTestHelper.createRepository(profileId: 'collab');
    soloRoot = p.join(disk.path, 'Audio Crawler');
    collabRoot = p.join(disk.path, 'Collabs');
    await Directory(soloRoot).create();
    await Directory(collabRoot).create();
    await solo.addRoot(soloRoot);
    await collab.addRoot(collabRoot);
  });

  tearDown(() async {
    await HiveTestHelper.tearDown(tempDir);
    if (await disk.exists()) await disk.delete(recursive: true);
  });

  /// A song in a folder of its own under the solo root.
  Future<String> songFile(String name, {String? folder}) async {
    final dir = Directory(p.join(soloRoot, folder ?? name));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$name.cpr'));
    await file.writeAsString('session data for $name');
    await File(p.join(dir.path, 'lyrics.txt')).writeAsString('la la');
    return file.path;
  }

  StoredMidiClips clips() => StoredMidiClips(
        extractedAt: DateTime.utc(2026),
        sourceModifiedAt: DateTime.utc(2026),
        clips: const [MidiClip(name: 'Lead', ppq: 960, lengthTicks: 3840, notes: [])],
      );

  test('keeping the files: everything moves, and the old profile stops scanning it',
      () async {
    final file = await songFile('Follow My Voice');
    await solo.projectsBox.put(
      'fmv',
      TestFactories.makeProject(id: 'fmv', filePath: file, notes: 'hook'),
    );
    await solo.midiClips.put('fmv', clips());
    await solo.eventsBox.put(
      'e1',
      ProjectEvent(
        id: 'e1',
        projectId: 'fmv',
        eventType: ProjectEvent.statusChange,
        occurredAt: DateTime(2026),
      ),
    );

    final plan = planProfileMove(solo, solo.getById('fmv')!);
    final result = await moveSongToProfile(source: solo, target: collab, plan: plan);

    expect(solo.getById('fmv'), isNull);
    final moved = collab.getById('fmv')!;
    expect(moved.notes, 'hook');
    expect(moved.filePath, file, reason: 'files stayed');
    expect((await collab.midiClips.get('fmv'))!.clips.single.name, 'Lead');
    expect(collab.eventsBox.get('e1'), isNotNull);
    expect(solo.eventsBox.get('e1'), isNull);
    // Its folder is excluded in the old profile, so a scan there won't
    // bring it back as a new, empty project.
    expect(result.excludedPath, p.dirname(file));
    expect(solo.getIgnoredPaths().map((i) => i.path), contains(p.dirname(file)));
    // A move is not a deletion.
    expect(await solo.trash.list(), isEmpty);
    // Other devices: gone from this profile only, new in the other.
    final t = (await SyncTombstoneStore.all()).values.single;
    expect((t.id, t.profileId), ('fmv', 'solo'));
  });

  test('moving the files: the folder goes into the new artist\'s folder', () async {
    final file = await songFile('Follow My Voice');
    await solo.projectsBox.put(
      'fmv',
      TestFactories.makeProject(id: 'fmv', filePath: file).copyWith(
        previewSongPath: p.join(p.dirname(file), 'bounce.wav'),
      ),
    );

    final plan = planProfileMove(solo, solo.getById('fmv')!);
    final result = await moveSongToProfile(
      source: solo,
      target: collab,
      plan: plan,
      destinationFolder: collabRoot,
    );

    final newFolder = p.join(collabRoot, 'Follow My Voice');
    expect(result.movedTo, newFolder);
    expect(result.excludedPath, isNull, reason: 'nothing left to exclude');
    expect(Directory(p.dirname(file)).existsSync(), isFalse);
    expect(File(p.join(newFolder, 'lyrics.txt')).existsSync(), isTrue,
        reason: 'the whole folder moved, not just the project file');
    final moved = collab.getById('fmv')!;
    expect(moved.filePath, p.join(newFolder, 'Follow My Voice.cpr'));
    expect(moved.previewSongPath, p.join(newFolder, 'bounce.wav'));
  });

  test('a song sharing its folder moves just its file', () async {
    final a = await songFile('A', folder: 'loose');
    final b = p.join(soloRoot, 'loose', 'B.cpr');
    await File(b).writeAsString('b');
    await solo.projectsBox.putAll({
      'a': TestFactories.makeProject(id: 'a', filePath: a),
      'b': TestFactories.makeProject(id: 'b', filePath: b),
    });

    final plan = planProfileMove(solo, solo.getById('a')!);
    expect((plan.path, plan.pathIsFolder), (a, false));
    await moveSongToProfile(source: solo, target: collab, plan: plan);

    expect(solo.getById('b'), isNotNull, reason: 'its neighbour stays');
    expect(solo.getIgnoredPaths().map((i) => i.path), [a]);
  });

  test('a version moves with its whole stack', () async {
    final v1 = await songFile('Song v1', folder: 'Song');
    final v2 = p.join(soloRoot, 'Song', 'Song v2.cpr');
    await File(v2).writeAsString('v2');
    await solo.projectsBox.putAll({
      'v1': TestFactories.makeProject(id: 'v1', filePath: v1),
      'v2': TestFactories.makeProject(id: 'v2', filePath: v2),
    });
    final stack = await solo.stackProjects(memberIds: ['v1', 'v2']);

    final plan = planProfileMove(solo, solo.getById('v2')!);
    expect(plan.song.id, stack.id);
    expect(plan.ids, {stack.id, 'v1', 'v2'});
    await moveSongToProfile(
      source: solo,
      target: collab,
      plan: plan,
      destinationFolder: collabRoot,
    );

    for (final id in [stack.id, 'v1', 'v2']) {
      expect(solo.getById(id), isNull);
      expect(collab.getById(id), isNotNull);
    }
    expect(collab.getById('v2')!.stackId, stack.id, reason: 'still one song');
    expect(collab.getById('v2')!.filePath, p.join(collabRoot, 'Song', 'Song v2.cpr'));
  });

  test("a hand-made stack across folders won't move its files, but can stay",
      () async {
    final v1 = await songFile('Song v1', folder: 'Song');
    final elsewhere = await songFile('Song v2', folder: 'Older');
    await solo.projectsBox.putAll({
      'v1': TestFactories.makeProject(id: 'v1', filePath: v1),
      'v2': TestFactories.makeProject(id: 'v2', filePath: elsewhere),
    });
    final stack = await solo.stackProjects(memberIds: ['v1', 'v2']);
    final plan = planProfileMove(solo, solo.getById(stack.id)!);
    expect(plan.outlyingFiles, isNotEmpty);

    await expectLater(
      moveSongToProfile(
        source: solo,
        target: collab,
        plan: plan,
        destinationFolder: collabRoot,
      ),
      throwsA(isA<ProfileMoveException>().having(
        (e) => e.block,
        'block',
        ProfileMoveBlock.versionsInSeveralFolders,
      )),
    );
    expect(solo.getById('v1'), isNotNull, reason: 'refused before anything changed');

    await moveSongToProfile(source: solo, target: collab, plan: plan);
    expect(
      solo.getIgnoredPaths().map((i) => i.path),
      containsAll([plan.path, ...plan.outlyingFiles]),
    );
  });

  test("it comes off the old artist's releases", () async {
    final file = await songFile('Track');
    await solo.projectsBox.put('t', TestFactories.makeProject(id: 't', filePath: file));
    await solo.releasesBox.put(
      'ep',
      Release(id: 'ep', title: 'EP', trackIds: const ['x', 't']),
    );

    final plan = planProfileMove(solo, solo.getById('t')!);
    expect(plan.releasesUsing.map((r) => r.id), ['ep']);
    await moveSongToProfile(source: solo, target: collab, plan: plan);

    expect(solo.releasesBox.get('ep')!.trackIds, ['x']);
  });

  test('an empty copy a scan made in the target gives way', () async {
    final file = await songFile('Song');
    await solo.projectsBox.put('mine', TestFactories.makeProject(id: 'mine', filePath: file, notes: 'n'));
    await collab.projectsBox.put('scanned', TestFactories.makeProject(id: 'scanned', filePath: file));

    await moveSongToProfile(
      source: solo,
      target: collab,
      plan: planProfileMove(solo, solo.getById('mine')!),
    );

    expect(collab.getById('scanned'), isNull);
    expect(collab.getById('mine')!.notes, 'n');
  });

  test('a copy in the target with details of its own is refused, untouched',
      () async {
    final file = await songFile('Song');
    await solo.projectsBox.put('mine', TestFactories.makeProject(id: 'mine', filePath: file));
    await collab.projectsBox.put(
      'theirs',
      TestFactories.makeProject(id: 'theirs', filePath: file, notes: 'their notes'),
    );

    await expectLater(
      moveSongToProfile(
        source: solo,
        target: collab,
        plan: planProfileMove(solo, solo.getById('mine')!),
      ),
      throwsA(isA<ProfileMoveException>().having(
        (e) => e.block,
        'block',
        ProfileMoveBlock.targetHasOwnCopy,
      )),
    );
    expect(solo.getById('mine'), isNotNull);
    expect(collab.getById('theirs')!.notes, 'their notes');
  });

  test('an archived project is refused', () {
    final archived = TestFactories.makeProject(id: 'z', archivePath: '/a/z.zip');
    expect(
      () => planProfileMove(solo, archived),
      throwsA(isA<ProfileMoveException>()),
    );
  });

  test('a project alone in a scan folder never takes the scan folder along', () async {
    final file = p.join(soloRoot, 'alone.cpr');
    await File(file).writeAsString('x');
    await solo.projectsBox.put('alone', TestFactories.makeProject(id: 'alone', filePath: file));
    final plan = planProfileMove(solo, solo.getById('alone')!);
    expect((plan.path, plan.pathIsFolder), (file, false));
  });

  group('copying across drives', () {
    test('a copy that came out short is caught before the original goes', () async {
      final src = Directory(p.join(disk.path, 'src'))..createSync();
      File(p.join(src.path, 'a.wav')).writeAsStringSync('0123456789');
      final dst = Directory(p.join(disk.path, 'dst'))..createSync();
      File(p.join(dst.path, 'a.wav')).writeAsStringSync('01234');
      expect(await firstCopyMismatch(src.path, dst.path), p.join(src.path, 'a.wav'));

      File(p.join(dst.path, 'a.wav')).writeAsStringSync('0123456789');
      expect(await firstCopyMismatch(src.path, dst.path), isNull);
    });

    test('copy-then-delete moves a folder whole', () async {
      final src = Directory(p.join(disk.path, 'song'))..createSync();
      File(p.join(src.path, 'song.cpr')).writeAsStringSync('x' * 100);
      final dst = p.join(disk.path, 'moved');
      await copyEntityThenDelete(src.path, dst, isDirectory: true);
      expect(src.existsSync(), isFalse);
      expect(File(p.join(dst, 'song.cpr')).lengthSync(), 100);
    });
  });

  group('findRootOverlaps', () {
    final music = p.join(Directory.systemTemp.path, 'Music');
    final roots = {
      'Audio Crawler': [p.join(music, 'Audio Crawler')],
      'ATLAS': [p.join(music, 'Collabs', 'ATLAS')],
    };

    test('the same folder, one inside, one around', () {
      final same = findRootOverlaps(p.join(music, 'Audio Crawler'), roots);
      expect(same.single.kind, RootOverlapKind.same);
      expect(same.single.profileName, 'Audio Crawler');

      final inside = findRootOverlaps(p.join(music, 'Audio Crawler', '2025'), roots);
      expect(inside.single.kind, RootOverlapKind.inside);

      final around = findRootOverlaps(p.join(music, 'Collabs'), roots);
      expect(around.single.kind, RootOverlapKind.contains);
      expect(around.single.profileName, 'ATLAS');
    });

    test('a sibling folder overlaps nothing', () {
      expect(findRootOverlaps(p.join(music, 'Audio Crawler 2'), roots), isEmpty);
      expect(findRootOverlaps(p.join(music, 'Reisser'), roots), isEmpty);
    });
  });
}
