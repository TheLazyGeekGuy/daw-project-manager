import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:daw_project_manager/models/drive_sync_status.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/services/drive_sync_errors.dart';
import 'package:daw_project_manager/services/google_drive_sync_service.dart';

import '../helpers/fake_drive.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// driveSyncStatusProvider is what the dashboard, the tray and the timer all
/// read — run here against a real service and an in-memory Drive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProjectRepository projectRepo;
  late ProfileRepository profileRepo;
  late FakeDrive fakeDrive;
  late GoogleDriveSyncService service;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    final profilesBox = await Hive.openBox<Profile>('profiles');
    final settingsBox = await Hive.openBox<String>('settings');
    profileRepo =
        ProfileRepository(profilesBox: profilesBox, settingsBox: settingsBox);
    final profile = await profileRepo.createProfile('Studio');
    projectRepo = await HiveTestHelper.createRepository(profileId: profile.id);
    await Hive.openBox<String>('app_settings');
    fakeDrive = FakeDrive();
    service = GoogleDriveSyncService()
      ..driveApi = fakeDrive.api
      ..desktopAuthClient = fakeDrive.authClient;
    await service.ensureAppDataFolder();
    container = ProviderContainer(overrides: [
      googleDriveSyncServiceProvider.overrideWithValue(service),
      profileRepositoryProvider.overrideWith((ref) async => profileRepo),
      repositoryProvider.overrideWith((ref) async => projectRepo),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await HiveTestHelper.tearDown(tempDir);
  });

  DriveSyncStatusNotifier notifier() =>
      container.read(driveSyncStatusProvider.notifier);
  DriveSyncStatus status() => container.read(driveSyncStatusProvider);

  test('a sync reports itself running, then up to date', () async {
    final seen = <bool>[];
    container.listen(
      driveSyncStatusProvider,
      (_, next) => seen.add(next.syncing),
      fireImmediately: true,
    );

    await notifier().syncNow();

    expect(seen.first, isFalse);
    expect(seen, contains(true));
    expect(status().syncing, isFalse);
    expect(status().lastSyncedAt, isNotNull);
    expect(status().indicator, DriveSyncIndicator.upToDate);
  });

  test('the automatic sync is quiet: the dashboard never spins for it',
      () async {
    // It runs at every launch and on a timer; a spinner each time was noise.
    final syncing = <bool>[];
    final background = <bool>[];
    container.listen(driveSyncStatusProvider, (_, next) {
      syncing.add(next.syncing);
      background.add(next.backgroundSyncing);
    });

    await notifier().syncNow(quiet: true);

    expect(syncing, everyElement(isFalse));
    expect(background, contains(true));
    expect(status().backgroundSyncing, isFalse);
    expect(status().lastSyncedAt, isNotNull);
  });

  test('a failed sync shows as failed, and the next success clears it',
      () async {
    // The bug: an automatic sync that failed only printed in debug builds,
    // so backups could stop for good with nothing on screen.
    fakeDrive.failWithStatus = 503;
    await expectLater(notifier().syncNow(), throwsA(anything));
    expect(status().indicator, DriveSyncIndicator.failed);
    expect(status().lastFailureKind, SyncErrorKind.other);

    fakeDrive.failWithStatus = null;
    await notifier().syncNow();
    expect(status().hasFailure, isFalse);
  });

  test('a quiet sync that fails still shows the failure', () async {
    fakeDrive.failWithStatus = 503;
    await expectLater(notifier().syncNow(quiet: true), throwsA(anything));
    expect(status().indicator, DriveSyncIndicator.failed);
  });

  test('a failure survives a restart', () async {
    fakeDrive.failWithStatus = 503;
    await expectLater(notifier().syncNow(), throwsA(anything));

    final fresh = ProviderContainer(overrides: [
      googleDriveSyncServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(fresh.dispose);
    await fresh.read(driveSyncStatusProvider.notifier).refresh(checkDrive: false);
    expect(fresh.read(driveSyncStatusProvider).hasFailure, isTrue);
  });

  test('refresh notices another device wrote to Drive, and which', () async {
    await notifier().syncNow();
    final folder = fakeDrive.files.values
        .firstWhere((f) => f.isFolder && f.parents.contains('root'));
    fakeDrive.seed(
      name: 'database_backup.json',
      parent: folder.id,
      description: 'Phone',
      content: utf8.encode(jsonEncode({'projects': []})),
    );

    await notifier().refresh();

    expect(status().indicator, DriveSyncIndicator.newerOnDrive);
    expect(status().remoteDevice, 'Phone');
  });

  test('syncNow honours the "upload auto-detected songs" setting', () async {
    // The tray's old "Backup now" always passed false.
    final song = File('${tempDir.path}/auto.wav')..writeAsBytesSync([1, 2, 3]);
    await projectRepo.projectsBox.put(
      'p',
      TestFactories.makeProject(id: 'p', previewSongAutoPath: song.path),
    );
    await Hive.box<String>('app_settings')
        .put(UploadAutoPreviewSongsNotifier.storageKey, 'true');

    await notifier().syncNow();

    final backup = jsonDecode(fakeDrive.named('database_backup.json')!.text)
        as Map<String, dynamic>;
    expect((backup['previewSongFiles'] as Map).keys, contains('p'));
  });
}
