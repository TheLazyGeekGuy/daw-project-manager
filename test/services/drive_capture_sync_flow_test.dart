import 'dart:io';

import 'package:daw_project_manager/models/plugin_capture.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/services/google_drive_sync_service.dart';
import 'package:daw_project_manager/services/plugin_capture_sync.dart';
import 'package:daw_project_manager/utils/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/fake_drive.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

/// The DAW plugin's latest captures through Drive sync, end to end: the real
/// sync service against an in-memory Drive ([FakeDrive]). The app's data
/// folder is a temp folder on every platform (`debugLocalAppDataOverride` on
/// Windows, a fake path provider elsewhere), so nothing touches the machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory appData;
  late ProjectRepository projectRepo;
  late ProfileRepository profileRepo;
  late Profile profile;
  late FakeDrive fakeDrive;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    appData = await Directory.systemTemp.createTemp('dpm_capture_sync_');
    debugLocalAppDataOverride = appData.path;
    PathProviderPlatform.instance = _FakePathProvider(appData.path);
    final profilesBox = await Hive.openBox<Profile>('profiles');
    final settingsBox = await Hive.openBox<String>('settings');
    profileRepo = ProfileRepository(profilesBox: profilesBox, settingsBox: settingsBox);
    profile = await profileRepo.createProfile('Studio');
    projectRepo = await HiveTestHelper.createRepository(profileId: profile.id);
    await Hive.openBox<String>('app_settings');
    fakeDrive = FakeDrive();
  });

  tearDown(() async {
    debugLocalAppDataOverride = null;
    await HiveTestHelper.tearDown(tempDir);
    if (await appData.exists()) await appData.delete(recursive: true);
  });

  Future<GoogleDriveSyncService> signedIn() async {
    final service = GoogleDriveSyncService()..driveApi = fakeDrive.api;
    await service.ensureAppDataFolder();
    return service;
  }

  Future<String> pluginDir() async => p.join(await getPreviewSongsPath(), 'plugin');

  /// A capture the plugin left on this device: its file and the slot.
  Future<PluginCapture> captureHere(String projectId, String name, List<int> bytes, DateTime at) async {
    final file = File(p.join(await pluginDir(), projectId, name));
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    final capture = PluginCapture(path: file.path, capturedAt: at, durationSeconds: 42);
    final project = projectRepo.projectsBox.get(projectId) ?? TestFactories.makeProject(id: projectId);
    await projectRepo.projectsBox.put(projectId, project.copyWith(latestCapture: capture));
    return capture;
  }

  Map<String, CaptureEntry> capturesOnDrive(Map<String, dynamic> backup) =>
      captureEntriesFrom(backup['pluginCaptures']);

  final t0 = DateTime.utc(2026, 10, 21, 18);

  test('a capture goes up with the backup, file and all', () async {
    final service = await signedIn();
    await captureHere('p1', 'take.flac', [1, 2, 3, 4], t0);

    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);

    final entry = capturesOnDrive(await service.downloadDatabase())[captureEntryKey(profile.id, 'p1')]!;
    expect(entry.name, 'take.flac');
    expect(entry.capturedAt.isAtSameMomentAs(t0), isTrue);
    expect(fakeDrive.files[entry.fileId]!.content, [1, 2, 3, 4]);
  });

  test('an unchanged capture is not uploaded again', () async {
    final service = await signedIn();
    await captureHere('p1', 'take.flac', [1, 2, 3, 4], t0);
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);
    final first = capturesOnDrive(await service.downloadDatabase())[captureEntryKey(profile.id, 'p1')]!;
    final writtenAt = fakeDrive.files[first.fileId]!.modifiedTime;

    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);

    final second = capturesOnDrive(await service.downloadDatabase())[captureEntryKey(profile.id, 'p1')]!;
    expect(second.fileId, first.fileId);
    expect(fakeDrive.files[first.fileId]!.modifiedTime, writtenAt);
  });

  test('a newer take overwrites the same file on Drive', () async {
    final service = await signedIn();
    await captureHere('p1', 'take.flac', [1, 2, 3, 4], t0);
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);
    final first = capturesOnDrive(await service.downloadDatabase())[captureEntryKey(profile.id, 'p1')]!;

    await captureHere('p1', 'take2.flac', [9, 9, 9], t0.add(const Duration(minutes: 5)));
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);

    final second = capturesOnDrive(await service.downloadDatabase())[captureEntryKey(profile.id, 'p1')]!;
    expect(second.fileId, first.fileId, reason: 'one Drive file per project, overwritten in place');
    expect(fakeDrive.files[second.fileId]!.content, [9, 9, 9]);
    expect(second.name, 'take2.flac');
  });

  test("another device's capture comes down, bytes and all", () async {
    final service = await signedIn();
    await captureHere('p1', 'take.flac', [1, 2, 3, 4], t0);
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);
    final backup = await service.downloadDatabase();

    // This device, before it had that capture: the project, no file.
    await Directory(await pluginDir()).delete(recursive: true);
    final project = projectRepo.projectsBox.get('p1')!;
    await projectRepo.projectsBox.put('p1', project.copyWith(clearLatestCapture: true));

    await service.mergeData(remoteData: backup, projectRepo: projectRepo, profileRepo: profileRepo);

    final kept = projectRepo.projectsBox.get('p1')!.latestCapture!;
    expect(p.isWithin(await pluginDir(), kept.path), isTrue);
    expect(await File(kept.path).readAsBytes(), [1, 2, 3, 4]);
    expect(kept.capturedAt.isAtSameMomentAs(t0), isTrue);
    expect(kept.durationSeconds, 42);
  });

  test('a merge never replaces a newer take here with an older one from Drive', () async {
    final service = await signedIn();
    await captureHere('p1', 'old.flac', [1, 1], t0);
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);
    final backup = await service.downloadDatabase();

    final newer = await captureHere('p1', 'new.flac', [2, 2], t0.add(const Duration(hours: 1)));
    await service.mergeData(remoteData: backup, projectRepo: projectRepo, profileRepo: profileRepo);

    expect(projectRepo.projectsBox.get('p1')!.latestCapture, newer);
    expect(await File(newer.path).readAsBytes(), [2, 2]);
  });

  test('a merge that skips audio skips captures too', () async {
    final service = await signedIn();
    await captureHere('p1', 'take.flac', [1, 2, 3, 4], t0);
    await service.uploadDatabase(projectRepo: projectRepo, profileRepo: profileRepo);
    final backup = await service.downloadDatabase();
    await Directory(await pluginDir()).delete(recursive: true);
    await projectRepo.projectsBox.put('p1', projectRepo.projectsBox.get('p1')!.copyWith(clearLatestCapture: true));

    await service.mergeData(
      remoteData: backup,
      projectRepo: projectRepo,
      profileRepo: profileRepo,
      downloadPreviewSongs: false,
    );

    expect(projectRepo.projectsBox.get('p1')!.latestCapture, isNull);
  });
}
