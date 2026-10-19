import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/models/project_attachment.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// Relocating a scan folder whose files the user moved themselves — a cloud
/// drive emptied on one disk and downloaded again on another. The basics
/// (file and preview paths) are covered in project_repository_test; these are
/// the paths a relocation used to leave behind, each of which made the next
/// scan treat the files at their new place as new, empty projects, or broke
/// something the user had set up.
void main() {
  late Directory tempDir;
  late String oldRoot;
  late String newRoot;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    oldRoot = p.join(tempDir.path, 'C', 'Proton Drive', 'Music');
    newRoot = p.join(tempDir.path, 'D', 'Proton Drive', 'Music');
  });

  tearDown(() async {
    await HiveTestHelper.tearDown(tempDir);
  });

  ProjectAttachment attachment(String id, ProjectAttachmentKind kind, String target) =>
      ProjectAttachment(id: id, kind: kind, target: target, label: '', addedAt: DateTime(2026));

  test('attachments in the folder follow it; links and files elsewhere do not', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    final elsewhere = p.join(tempDir.path, 'Downloads', 'contract.pdf');
    await repo.updateProject(TestFactories.makeProject(
      id: 'p1',
      filePath: p.join(oldRoot, 'Song', 'Song.als'),
      attachments: [
        attachment('a1', ProjectAttachmentKind.file, p.join(oldRoot, 'Song', 'lyrics.txt')),
        attachment('a2', ProjectAttachmentKind.file, elsewhere),
        attachment('a3', ProjectAttachmentKind.link, 'https://example.com/stems'),
      ],
    ));

    await repo.relocateRoot(root.id, newRoot);

    final targets = repo.getById('p1')!.attachments.map((a) => a.target).toList();
    expect(targets, [p.join(newRoot, 'Song', 'lyrics.txt'), elsewhere, 'https://example.com/stems']);
  });

  test('the newer mixdown the user turned down stays turned down', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    await repo.updateProject(TestFactories.makeProject(
      id: 'p1',
      filePath: p.join(oldRoot, 'Song', 'Song.als'),
      ignoredNewerSongPath: p.join(oldRoot, 'Song', 'Mixdown v2.wav'),
    ));

    await repo.relocateRoot(root.id, newRoot);

    expect(repo.getById('p1')!.ignoredNewerSongPath, p.join(newRoot, 'Song', 'Mixdown v2.wav'));
  });

  test('a relocated project counts as changed, so the move syncs', () async {
    // Drive sync keeps the newer copy. Left at its old updatedAt, an untouched
    // copy of the old path elsewhere ties with it, or beats it.
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    final before = DateTime(2026, 1, 1);
    await repo.projectsBox.put('p1', TestFactories.makeProject(
      id: 'p1',
      filePath: p.join(oldRoot, 'Song.als'),
      updatedAt: before,
    ));
    await repo.projectsBox.put('other', TestFactories.makeProject(
      id: 'other',
      filePath: p.join(tempDir.path, 'Elsewhere', 'Other.als'),
      updatedAt: before,
    ));

    await repo.relocateRoot(root.id, newRoot);

    expect(repo.getById('p1')!.updatedAt.isAfter(before), isTrue);
    expect(repo.getById('other')!.updatedAt, before, reason: 'a project outside the folder did not move');
  });

  test('excluded paths in the folder follow it, or what was excluded comes back', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    await repo.addIgnoredPath(p.join(oldRoot, 'Old sketches'));
    await repo.addIgnoredPath(p.join(oldRoot, 'Song', 'Song backup.als'));
    final unrelated = p.join(tempDir.path, 'Elsewhere', 'Junk');
    await repo.addIgnoredPath(unrelated);
    final addedAt = {for (final i in repo.getIgnoredPaths()) i.id: i.addedAt};

    await repo.relocateRoot(root.id, newRoot);

    final ignored = repo.getIgnoredPaths();
    expect(
      ignored.map((i) => i.path).toSet(),
      {p.join(newRoot, 'Old sketches'), p.join(newRoot, 'Song', 'Song backup.als'), unrelated},
    );
    for (final i in ignored) {
      expect(i.addedAt, addedAt[i.id], reason: 'the same exclusion, only its path changed');
    }
  });

  test('a project in Recently deleted from the folder restores to the new place', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    await repo.updateProject(TestFactories.makeProject(id: 'gone', filePath: p.join(oldRoot, 'Gone.als')));
    await repo.deleteProjects(['gone']);
    final deletedAt = (await repo.trash.get('gone'))!.deletedAt;

    await repo.relocateRoot(root.id, newRoot);

    final kept = (await repo.trash.get('gone'))!;
    expect(kept.project.filePath, p.join(newRoot, 'Gone.als'));
    expect(kept.deletedAt, deletedAt, reason: 'still expires when it would have');
  });

  test('a folder next to it whose name starts the same is left alone', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    final sibling = p.join('${oldRoot}2', 'Song.als');
    await repo.updateProject(TestFactories.makeProject(id: 'sib', filePath: sibling));

    final count = await repo.relocateRoot(root.id, newRoot);

    expect(count, 0);
    expect(repo.getById('sib')!.filePath, sibling);
  });

  test('a version stack and its members move with the folder', () async {
    final repo = await HiveTestHelper.createRepository();
    final root = await repo.addRoot(oldRoot);
    final folder = p.join(oldRoot, 'Song');
    await repo.updateProject(TestFactories.makeProject(id: 'stack', filePath: folder, isVirtual: true));
    await repo.updateProject(TestFactories.makeProject(id: 'v1', filePath: p.join(folder, 'Song.als')));

    await repo.relocateRoot(root.id, newRoot);

    expect(repo.getById('stack')!.filePath, p.join(newRoot, 'Song'));
    expect(repo.getById('v1')!.filePath, p.join(newRoot, 'Song', 'Song.als'));
  });
}
