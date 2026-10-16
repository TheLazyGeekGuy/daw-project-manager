import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/models/stored_midi_clips.dart';
import 'package:daw_project_manager/models/todo_item.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/repository/project_trash.dart';
import 'package:daw_project_manager/repository/sync_tombstones.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// "Recently deleted": every deletion of projects keeps them whole for 30
/// days, and a restore puts them back as they were.
void main() {
  late Directory tempDir;
  late ProjectRepository repo;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    repo = await HiveTestHelper.createRepository();
  });

  tearDown(() async {
    await HiveTestHelper.tearDown(tempDir);
  });

  StoredMidiClips someClips() => StoredMidiClips(
        extractedAt: DateTime.utc(2026, 1, 1),
        sourceModifiedAt: DateTime.utc(2026, 1, 1),
        clips: [
          MidiClip(
            name: 'Bass',
            ppq: 960,
            lengthTicks: 3840,
            notes: const [],
          ),
        ],
      );

  test('deleting keeps the project whole in the trash', () async {
    final project = TestFactories.makeProject(
      id: 'p',
      notes: 'hook idea',
      todos: [TodoItem(id: 't', text: 'mix', createdAt: DateTime(2026))],
    );
    await repo.projectsBox.put('p', project);
    await repo.midiClips.put('p', someClips());

    await repo.deleteProjects(['p']);

    expect(repo.projectsBox.get('p'), isNull);
    final trashed = (await repo.trash.list()).single;
    expect(trashed.project.notes, 'hook idea');
    expect(trashed.project.todos.single.text, 'mix');
    expect(await repo.trash.clipsOf('p'), isNotNull);
    // The deletion still syncs.
    expect((await SyncTombstoneStore.all()).values.single.id, 'p');
  });

  test('restoring puts it back as it was, clips included', () async {
    await repo.projectsBox.put(
      'p',
      TestFactories.makeProject(id: 'p', notes: 'hook idea'),
    );
    await repo.midiClips.put('p', someClips());
    await repo.deleteProjects(['p']);

    final replaced = await repo.restoreFromTrash('p');

    expect(replaced, isFalse);
    expect(repo.projectsBox.get('p')!.notes, 'hook idea');
    expect((await repo.midiClips.get('p'))!.clips.single.name, 'Bass');
    expect(await repo.trash.list(), isEmpty);
  });

  test('a restore beats its own deletion, so it syncs back', () async {
    await repo.projectsBox.put('p', TestFactories.makeProject(id: 'p'));
    await repo.deleteProjects(['p']);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await repo.restoreFromTrash('p');

    final tombstone = (await SyncTombstoneStore.all()).values.single;
    expect(tombstone.beats(repo.projectsBox.get('p')!.updatedAt), isFalse);
  });

  test('restoring replaces the empty copy a scan added meanwhile', () async {
    final file = File('${tempDir.path}/song.als')..writeAsStringSync('x');
    await repo.upsertFromFileSystemEntity(file);
    final original = repo.getByPath(file.path)!;
    await repo.updateProject(original.copyWith(notes: 'my notes'));
    await repo.deleteProjects([original.id]);
    // The next scan finds the file again: a new, empty row.
    await repo.upsertFromFileSystemEntity(file);
    expect(repo.getByPath(file.path)!.id, isNot(original.id));

    final replaced = await repo.restoreFromTrash(original.id);

    expect(replaced, isTrue);
    final rows = repo.getAllProjects().where((p) => p.filePath == file.path);
    expect(rows.single.id, original.id);
    expect(rows.single.notes, 'my notes');
  });

  test('removing a scan folder keeps its projects in the trash', () async {
    final root = await repo.addRoot('${tempDir.path}${Platform.pathSeparator}songs');
    await repo.projectsBox.put(
      'p',
      TestFactories.makeProject(
        id: 'p',
        filePath: '${root.path}${Platform.pathSeparator}a.als',
      ),
    );
    await repo.removeRoot(root.id);
    expect((await repo.trash.list()).map((t) => t.project.id), ['p']);
  });

  test('excluding a project\'s own file removes that project', () async {
    // Excluding a path used to match only what was inside it, so excluding
    // one file (a project sharing its folder) removed nothing.
    final filePath = '${tempDir.path}${Platform.pathSeparator}a.als';
    await repo.projectsBox.put('p', TestFactories.makeProject(id: 'p', filePath: filePath));
    await repo.addIgnoredPath(filePath);
    expect(repo.projectsBox.get('p'), isNull);
    expect((await repo.trash.list()).single.project.id, 'p');
  });

  test('deleting for good, and emptying', () async {
    await repo.projectsBox.putAll({
      'a': TestFactories.makeProject(id: 'a'),
      'b': TestFactories.makeProject(id: 'b'),
      'c': TestFactories.makeProject(id: 'c'),
    });
    await repo.deleteProjects(['a', 'b', 'c']);
    await repo.deleteFromTrash(['a']);
    expect((await repo.trash.list()).map((t) => t.project.id).toSet(), {'b', 'c'});
    await repo.trash.empty();
    expect(await repo.trash.list(), isEmpty);
  });

  test('anything older than 30 days goes for good', () async {
    final trash = ProjectTrash(repo.profileId);
    await trash.add(
      [TestFactories.makeProject(id: 'old')],
      at: DateTime.utc(2026, 1, 1),
    );
    await trash.add(
      [TestFactories.makeProject(id: 'new')],
      at: DateTime.utc(2026, 1, 25),
    );
    final left = await trash.list(now: DateTime.utc(2026, 2, 5));
    expect(left.map((t) => t.project.id), ['new']);
    expect(left.single.expiresAt, DateTime.utc(2026, 2, 24));
  });

  test('newest first', () async {
    final trash = ProjectTrash(repo.profileId);
    await trash.add([TestFactories.makeProject(id: 'first')], at: DateTime.utc(2026, 3, 1));
    await trash.add([TestFactories.makeProject(id: 'second')], at: DateTime.utc(2026, 3, 2));
    final ids = (await trash.list(now: DateTime.utc(2026, 3, 3))).map((t) => t.project.id);
    expect(ids, ['second', 'first']);
  });
}
