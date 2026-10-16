import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/project_event.dart';
import 'package:daw_project_manager/repository/project_repository.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// A scan that finds nothing new must leave a project as it was.
///
/// Every launch's scan re-saved every project with `updatedAt: now` — which
/// is what Drive sync's "newer copy wins" goes by — so an untouched desktop
/// copy beat a note just edited on a phone, and the next sync dropped the
/// note. It also kept the file's date to the microsecond, which never
/// equalled the millisecond copy Hive reads back after a restart.
void main() {
  late Directory tempDir;
  late Directory projectDir;
  late ProjectRepository repo;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    repo = await HiveTestHelper.createRepository();
    projectDir = await Directory.systemTemp.createTemp('scan_updated_at_');
  });

  tearDown(() async {
    await HiveTestHelper.tearDown(tempDir);
    if (await projectDir.exists()) await projectDir.delete(recursive: true);
  });

  Future<File> writeProject(String name) async {
    final file = File('${projectDir.path}/$name.als');
    await file.writeAsString('x');
    // Microseconds in the file's date, as Windows gives them.
    await file.setLastModified(DateTime(2026, 3, 1, 10, 0, 0, 123, 456));
    return file;
  }

  Future<MusicProject> scan(File file) async {
    await repo.upsertFromFileSystemEntity(file);
    return repo.getByPath(file.path)!;
  }

  /// What a restart does: everything read back from disk.
  Future<void> restart() async {
    await Hive.close();
    repo = await HiveTestHelper.createRepository();
  }

  test('rescanning an unchanged file keeps updatedAt', () async {
    final file = await writeProject('same');
    final first = await scan(file);
    // Make "now" later than the first scan so a bump would show.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final again = await scan(file);

    expect(again.updatedAt, first.updatedAt);
  });

  test('...including after a restart', () async {
    final file = await writeProject('same');
    final first = await scan(file);
    await restart();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final again = await scan(file);

    expect(
      again.updatedAt.millisecondsSinceEpoch,
      first.updatedAt.millisecondsSinceEpoch,
    );
  });

  test('a file that changed on disk does move updatedAt', () async {
    final file = await writeProject('edited');
    final first = await scan(file);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await file.writeAsString('saved again in the DAW');

    final again = await scan(file);

    expect(again.updatedAt.isAfter(first.updatedAt), isTrue);
  });

  test('file dates are kept at the precision Hive stores', () async {
    final file = await writeProject('precise');
    final project = await scan(file);
    expect(project.lastModifiedAt.microsecond, 0);
    expect(project.fileCreatedAt?.microsecond ?? 0, 0);
  });

  test('a restart and rescan logs no "file changed" event', () async {
    final file = await writeProject('quiet');
    await scan(file);
    await restart();
    await scan(file);

    final changed = repo.eventsBox.values
        .where((e) => e.eventType == ProjectEvent.fileChanged);
    expect(changed, isEmpty);
  });

  test("an untouched desktop rescan doesn't beat a phone's later edit", () async {
    // The data-loss case in full: the phone's copy is newer than the last
    // scan; after a launch scan the desktop's must still be older.
    final file = await writeProject('song');
    final scanned = await scan(file);
    final phoneEditAt = DateTime.now().add(const Duration(milliseconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final afterLaunchScan = await scan(file);

    expect(afterLaunchScan.updatedAt.isBefore(phoneEditAt), isTrue);
    expect(afterLaunchScan.updatedAt, scanned.updatedAt);
  });

  group('scanChangedProject', () {
    final base = TestFactories.makeProject(
      id: 'p',
      lastModifiedAt: DateTime(2026, 3, 1, 10, 0, 0, 123),
    );

    test('ignores microseconds Hive would drop anyway', () {
      expect(
        ProjectRepository.scanChangedProject(
          base,
          base.copyWith(lastModifiedAt: DateTime(2026, 3, 1, 10, 0, 0, 123, 456)),
        ),
        isFalse,
      );
    });

    test('sees what a scan really changes', () {
      expect(
        ProjectRepository.scanChangedProject(base, base.copyWith(fileSizeBytes: 9)),
        isTrue,
      );
      expect(
        ProjectRepository.scanChangedProject(base, base.copyWith(bpm: 140)),
        isTrue,
      );
      expect(
        ProjectRepository.scanChangedProject(
          base,
          base.copyWith(lastModifiedAt: DateTime(2026, 3, 2)),
        ),
        isTrue,
      );
    });

    test('a user edit is not a scan change', () {
      expect(
        ProjectRepository.scanChangedProject(base, base.copyWith(notes: 'hi')),
        isFalse,
        reason: 'scans never write notes; updateProject bumps for edits',
      );
    });
  });
}
