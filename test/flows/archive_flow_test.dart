// Archiving real projects and bringing them back: a Cubase SX 3 song with
// its Audio and Edits folders is zipped out of the library with its
// originals deleted, survives a rescan as an archived row (never "missing"),
// and is restored byte for byte, its MIDI and details intact.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/services/project_archive_service.dart';
import 'package:daw_project_manager/ui/dashboard_page.dart' show missingProjectIds;

import 'flow_library.dart';

/// Every file under [dir], by path relative to it, with its SHA-1.
Map<String, String> _contents(Directory dir) => {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: dir.path): sha1.convert(f.readAsBytesSync()).toString(),
    };

void main() {
  late FlowLibrary lib;

  setUp(() async => lib = await FlowLibrary.open(only: [
        'cubase/Another Dance (Cubase SX 3)',
        'flstudio/untitled3 (FL 8)',
      ]));
  tearDown(() async => lib.close());

  test('archive with the originals deleted, rescan, restore byte for byte', () async {
    await lib.scan();
    await lib.deepScan();
    final song = lib.fixtures.singleWhere((f) => f.daw == 'cubase');
    final file = song.projectFiles.single;
    var row = lib.projectOf(file);
    await lib.repo.updateProject(row.copyWith(notes: 'Final mix sent to the label'));
    row = lib.projectOf(file);
    final clips = (await lib.clipsOf(file))!.clips.length;
    expect(clips, greaterThan(0));
    final before = _contents(song.folder);
    expect(before.keys.where((k) => k.toLowerCase().endsWith('.wav')), isNotEmpty,
        reason: 'the song comes with its audio');

    // It has a folder of its own, so the folder goes with it.
    final scope = defaultScopeFor(row.filePath,
        allProjectPaths: lib.projects.map((r) => r.filePath));
    expect(scope, ArchiveScope.containingFolder);

    // Never into the scan folder: the next scan would index the zip back.
    await expectLater(
      archiveProject(row, p.join(lib.projectsDir.path, 'Archive'),
          scope: scope, deleteOriginals: true, scanRoots: lib.repo.getRoots()),
      throwsA(isA<ProjectArchiveException>()
          .having((e) => e.reason, 'reason', ArchiveError.destinationInScanRoot)),
    );
    expect(song.folder.existsSync(), isTrue, reason: 'a refused archive touches nothing');

    final archives = Directory(p.join(lib.scratch.path, 'Archive'));
    final result = await archiveProject(row, archives.path,
        scope: scope, deleteOriginals: true, scanRoots: lib.repo.getRoots());
    await lib.repo.updateProject(result.project);
    expect(result.originalsDeleted, isTrue);
    expect(result.warnings, isEmpty);
    expect(song.folder.existsSync(), isFalse);
    // The zip holds every file of the folder, byte for byte.
    final zip = ZipDecoder().decodeBytes(File(result.archivePath).readAsBytesSync());
    final inZip = {
      for (final e in zip.files.where((e) => e.isFile))
        p.joinAll(e.name.split('/').skip(1)): sha1.convert(e.content as List<int>).toString(),
    };
    expect(inZip, before);

    // Archived is not missing: a rescan keeps the row, and nothing offers
    // to delete it.
    await lib.scan();
    final archived = lib.projects.singleWhere((r) => r.id == row.id);
    expect(archived.isArchived, isTrue);
    expect(archived.isMissingFileCandidate, isFalse);
    expect(missingProjectIds(lib.projects, [row.id]), isEmpty);
    expect(archived.notes, 'Final mix sent to the label');
    expect((await lib.repo.midiClips.get(row.id))?.clips.length, clips);

    // Restored where it came from, exactly as it was.
    final restored = await restoreProject(archived, originalRestoreFolderFor(archived)!);
    await lib.repo.updateProject(restored);
    expect(p.normalize(restored.filePath), p.normalize(row.filePath));
    expect(restored.isArchived, isFalse);
    expect(_contents(song.folder), before);

    // And the library is as before: one row for it, nothing new.
    final ids = {for (final r in lib.projects) r.id};
    await lib.scan();
    expect({for (final r in lib.projects) r.id}, ids);
    expect(lib.projectOf(file).notes, 'Final mix sent to the label');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('archive keeping the originals, then undo: only the zip goes', () async {
    await lib.scan();
    final fl = lib.fixtures.singleWhere((f) => f.daw == 'flstudio');
    final row = lib.projectOf(fl.projectFiles.single);
    final before = _contents(fl.folder);
    final result = await archiveProject(row, p.join(lib.scratch.path, 'Archive'),
        scope: ArchiveScope.projectFileOnly, deleteOriginals: false, scanRoots: lib.repo.getRoots());
    expect(result.originalsDeleted, isFalse);
    expect(File(result.archivePath).existsSync(), isTrue);
    expect(_contents(fl.folder), before);

    final reverted = await undoArchive(result.project);
    expect(reverted.isArchived, isFalse);
    expect(File(result.archivePath).existsSync(), isFalse);
    expect(_contents(fl.folder), before);
  });
}
