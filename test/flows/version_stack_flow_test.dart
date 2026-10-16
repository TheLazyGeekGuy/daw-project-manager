// Version stacks over the collection's real song folders: in version stack
// mode a scan stacks each folder of versions — MegaBeat's three saves, one
// remix in eight across Cubase 4, 5 and 11 — and nothing else; the stack
// takes the details of the version that has some, rescans change nothing,
// and unstacking hands every version back what it had.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/scan_mode.dart';
import 'package:daw_project_manager/utils/version_stacks.dart';

import 'flow_library.dart';

void main() {
  late FlowLibrary lib;

  setUp(() async => lib = await FlowLibrary.open());
  tearDown(() async => lib.close());

  /// The fixtures holding one song's versions, and those holding one project.
  Iterable<String> versionFolders() => [
        for (final f in lib.fixtures)
          if (f.projectFiles.length > 1) p.normalize(f.folder.path),
      ];

  MusicProject? stackOf(MusicProject row) =>
      row.stackId == null ? null : lib.repo.getAllProjects().firstWhere((r) => r.id == row.stackId);

  test('each folder of versions becomes one stack, and only those', () async {
    expect(versionFolders(), hasLength(greaterThanOrEqualTo(4)),
        reason: 'the collection should hold several version folders');

    // Details on one version first, as a library scanned flat would have.
    await lib.scan();
    final megaBeat = lib.fixtures.singleWhere((f) => f.name.startsWith('MegaBeat'));
    final second = lib.projectOf(megaBeat.projectFiles[1]);
    await lib.repo.updateProject(second.copyWith(notes: 'v2: new bassline, keep it'));

    await lib.repo.updateRootScanMode(lib.root.id, ScanMode.versionStack);
    await lib.scan();

    for (final f in lib.fixtures) {
      final rows = [for (final file in f.projectFiles) lib.projectOf(file)];
      if (rows.length == 1) {
        expect(rows.single.stackId, isNull, reason: '$f is one project, not a stack');
        continue;
      }
      final stackIds = {for (final r in rows) r.stackId};
      expect(stackIds, hasLength(1), reason: 'every version of $f in one stack');
      final stack = stackOf(rows.first)!;
      expect(stack.isVirtual, isTrue);
      expect(stack.isMissingFileCandidate, isFalse,
          reason: 'a stack has no file, and must never be offered for deletion');
      expect(p.normalize(stack.filePath), p.normalize(f.folder.path));
      expect(lib.repo.stackMembers(stack).map((m) => m.id).toSet(), {for (final r in rows) r.id});
    }

    final stacks = lib.projects.where((r) => r.isVirtual).toList();
    expect(stacks, hasLength(versionFolders().length));
    // The library lists each song once.
    final singles = lib.fixtures.where((f) => f.projectFiles.length == 1).length;
    expect(collapseVersionStacks(lib.projects), hasLength(singles + stacks.length));

    // The stack took the details of the version that had them.
    expect(stackOf(lib.projectOf(megaBeat.projectFiles[1]))!.notes, 'v2: new bassline, keep it');

    // Rescans — plain and deep — leave the stacks exactly as they are.
    final before = {for (final r in lib.projects) r.id: r.stackId};
    await lib.scan();
    await lib.deepScan();
    expect({for (final r in lib.projects) r.id: r.stackId}, before);

    // Unstacking hands each version back its own details.
    final megaStack = stackOf(lib.projectOf(megaBeat.projectFiles[0]))!;
    await lib.repo.unstack(megaStack.id);
    final versions = [for (final file in megaBeat.projectFiles) lib.projectOf(file)];
    expect(versions.map((v) => v.stackId), everyElement(isNull));
    expect(lib.projects.where((r) => r.id == megaStack.id), isEmpty);
    expect(versions[1].notes, 'v2: new bassline, keep it');
    expect(versions[0].notes ?? '', isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('stacks survive a relaunch', () async {
    await lib.repo.updateRootScanMode(lib.root.id, ScanMode.versionStack);
    await lib.scan();
    final before = {for (final r in lib.projects) r.id: (r.stackId, r.isVirtual)};
    await lib.reopen();
    expect({for (final r in lib.projects) r.id: (r.stackId, r.isVirtual)}, before);
  });
}
