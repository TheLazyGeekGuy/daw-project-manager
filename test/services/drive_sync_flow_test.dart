import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/repository/sync_tombstones.dart';
import 'package:daw_project_manager/services/google_drive_sync_service.dart';

import '../helpers/fake_drive.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// The sync service end to end, against an in-memory Drive ([FakeDrive])
/// spoken to through the real googleapis client.
void main() {
  late Directory tempDir;
  late ProjectRepository projectRepo;
  late ProfileRepository profileRepo;
  late Profile profile;
  late FakeDrive fakeDrive;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    final profilesBox = await Hive.openBox<Profile>('profiles');
    final settingsBox = await Hive.openBox<String>('settings');
    profileRepo =
        ProfileRepository(profilesBox: profilesBox, settingsBox: settingsBox);
    profile = await profileRepo.createProfile('Studio');
    projectRepo = await HiveTestHelper.createRepository(profileId: profile.id);
    await Hive.openBox<String>('app_settings');
    fakeDrive = FakeDrive();
  });

  tearDown(() async {
    await HiveTestHelper.tearDown(tempDir);
  });

  Future<GoogleDriveSyncService> signedIn() async {
    final service = GoogleDriveSyncService()..driveApi = fakeDrive.api;
    await service.ensureAppDataFolder();
    return service;
  }

  String folderId() =>
      fakeDrive.files.values.firstWhere((f) => f.isFolder && f.parents.contains('root')).id;

  /// What another device's upload would leave on Drive.
  void seedBackupFromAnotherDevice(
    GoogleDriveSyncService service, {
    List<Map<String, dynamic>> projects = const [],
    List<Map<String, dynamic>> releases = const [],
    List<Map<String, dynamic>> deletedRecords = const [],
    String device = 'Laptop',
  }) {
    fakeDrive.seed(
      name: 'database_backup.json',
      parent: folderId(),
      description: device,
      content: utf8.encode(jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'device': device,
        'projects': projects,
        'releases': releases,
        'deletedRecords': deletedRecords,
      })),
    );
  }

  Map<String, dynamic> backupOnDrive() =>
      jsonDecode(fakeDrive.named('database_backup.json')!.text)
          as Map<String, dynamic>;

  Set<String> projectIdsOnDrive() => {
        for (final p in backupOnDrive()['projects'] as List) p['id'] as String,
      };

  group('syncDatabase', () {
    test('keeps what another device pushed instead of overwriting it', () async {
      // The bug: the sync page's Upload and the tray's "Backup now" replaced
      // Drive's copy outright, so a phone's project vanished from the backup
      // the moment the laptop uploaded.
      final service = await signedIn();
      seedBackupFromAnotherDevice(service, projects: [
        service.serializeProjectForTest(
          TestFactories.makeProject(id: 'from-phone', notes: 'phone notes'),
        ),
      ]);
      await projectRepo.projectsBox
          .put('local', TestFactories.makeProject(id: 'local'));

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectIdsOnDrive(), {'local', 'from-phone'});
      expect(projectRepo.projectsBox.get('from-phone')!.notes, 'phone notes');
    });

    test('uploads straight away when Drive has no backup yet', () async {
      final service = await signedIn();
      await projectRepo.projectsBox
          .put('local', TestFactories.makeProject(id: 'local'));

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectIdsOnDrive(), {'local'});
    });

    test('downloads the backup once, not twice', () async {
      final service = await signedIn();
      seedBackupFromAnotherDevice(service);
      fakeDrive.log.clear();
      final backupId = fakeDrive.named('database_backup.json')!.id;

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      // The merge's read, and the upload's read of the old media hashes.
      final reads =
          fakeDrive.log.where((l) => l == 'GET /drive/v3/files/$backupId');
      expect(reads.length, 2);
    });

    test('records a failure and clears it on the next success', () async {
      final service = await signedIn();
      fakeDrive.failWithStatus = 500;
      await expectLater(
        service.syncDatabase(projectRepo: projectRepo, profileRepo: profileRepo),
        throwsA(anything),
      );
      expect(await service.getLastFailure(), isNotNull);

      fakeDrive.failWithStatus = null;
      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      expect(await service.getLastFailure(), isNull);
      expect(await service.getLastSyncedAt(), isNotNull);
    });
  });

  group('newer backup on Drive', () {
    test('not after this device uploaded', () async {
      final service = await signedIn();
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      final info = await service.getBackupInfo();
      expect(info['isNewer'], isFalse);
      expect(info['remoteDevice'], GoogleDriveSyncService.deviceName);
    });

    test('once another device writes, and names that device', () async {
      final service = await signedIn();
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      seedBackupFromAnotherDevice(service, device: 'Phone');

      final info = await service.getBackupInfo();
      expect(info['isNewer'], isTrue);
      expect(info['remoteDevice'], 'Phone');
    });

    test('reading the backup without merging it does not hide it', () async {
      // The bug: downloadDatabase marked the backup as seen, so the upload's
      // own read of it — or a restore cancelled at its confirmation — made
      // "newer backup available" go away with nothing merged.
      final service = await signedIn();
      seedBackupFromAnotherDevice(service);

      await service.downloadDatabase();
      expect((await service.getBackupInfo())['isNewer'], isTrue);

      final fetched = await service.fetchBackup();
      await service.markMerged(fetched);
      expect((await service.getBackupInfo())['isNewer'], isFalse);
    });

    test('isRemoteNewer compares Drive times, with slack for old values', () {
      final t = DateTime.utc(2026, 5, 1, 12);
      expect(
        GoogleDriveSyncService.isRemoteNewer(remoteModified: null, lastSeen: t),
        isFalse,
      );
      expect(
        GoogleDriveSyncService.isRemoteNewer(remoteModified: t, lastSeen: null),
        isTrue,
      );
      expect(
        GoogleDriveSyncService.isRemoteNewer(remoteModified: t, lastSeen: t),
        isFalse,
      );
      expect(
        GoogleDriveSyncService.isRemoteNewer(
          remoteModified: t.add(const Duration(seconds: 1)),
          lastSeen: t,
        ),
        isTrue,
        reason: 'a Drive time is exact: a write a second later is news',
      );
      expect(
        GoogleDriveSyncService.isRemoteNewer(
          remoteModified: t.add(const Duration(seconds: 3)),
          lastSeen: t,
          lastSeenIsDriveTime: false,
        ),
        isFalse,
        reason: "an old build's own clock gets a few seconds' slack",
      );
      expect(
        GoogleDriveSyncService.isRemoteNewer(
          remoteModified: t.add(const Duration(minutes: 1)),
          lastSeen: t,
        ),
        isTrue,
      );
    });
  });

  group('upload', () {
    test('names this device in the file and the data', () async {
      final service = await signedIn();
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      expect(
        fakeDrive.named('database_backup.json')!.description,
        GoogleDriveSyncService.deviceName,
      );
      expect(backupOnDrive()['device'], GoogleDriveSyncService.deviceName);
    });
  });

  group('earlier backups', () {
    test('every overwrite keeps the backup it replaces, newest first', () async {
      final service = await signedIn();
      final times = <DateTime>[];
      for (var i = 0; i < 3; i++) {
        await service.uploadDatabase(
          projectRepo: projectRepo,
          profileRepo: profileRepo,
        );
        times.add(fakeDrive.named('database_backup.json')!.modifiedTime);
      }

      final snapshots = await service.listSnapshots();
      // The first upload replaced nothing; the next two each kept one.
      expect(snapshots.map((s) => s.takenAt), [times[1], times[0]]);
      expect(snapshots.first.device, GoogleDriveSyncService.deviceName);
    });

    test('keeps only the newest ${GoogleDriveSyncService.snapshotsKept}',
        () async {
      final service = await signedIn();
      for (var i = 0; i < GoogleDriveSyncService.snapshotsKept + 3; i++) {
        await service.uploadDatabase(
          projectRepo: projectRepo,
          profileRepo: profileRepo,
        );
      }
      expect(
        (await service.listSnapshots()).length,
        GoogleDriveSyncService.snapshotsKept,
      );
    });

    test('merging one back recovers what an overwrite lost', () async {
      final service = await signedIn();
      await projectRepo.projectsBox
          .put('precious', TestFactories.makeProject(id: 'precious'));
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      // The device loses it (say, a reinstall) and then overwrites Drive.
      await projectRepo.projectsBox.delete('precious');
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      expect(projectIdsOnDrive(), isNot(contains('precious')));

      final snapshots = await service.listSnapshots();
      await service.mergeData(
        remoteData: await service.downloadSnapshot(snapshots.single),
        projectRepo: projectRepo,
        profileRepo: profileRepo,
        downloadPreviewSongs: false,
      );

      expect(projectRepo.projectsBox.get('precious'), isNotNull);
    });

    test('snapshot names round-trip to the time they keep', () {
      final t = DateTime.utc(2026, 10, 15, 18, 42, 9);
      final name = GoogleDriveSyncService.snapshotFileName(t);
      expect(name, 'backup_20261015T184209Z.json');
      expect(GoogleDriveSyncService.snapshotTakenAt(name), t);
      expect(GoogleDriveSyncService.snapshotTakenAt('notes.txt'), isNull);
    });
  });

  group('deleteAllDriveData', () {
    test('removes the backup folder and everything in it', () async {
      final service = await signedIn();
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );
      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      ); // leaves a snapshot in history
      final oldFolder = folderId();

      await service.deleteAllDriveData();

      expect(fakeDrive.files.containsKey(oldFolder), isFalse);
      expect(fakeDrive.named('database_backup.json'), isNull);
      expect(await service.getRemoteBackupInfo(), isNull);
      expect(await service.getLastSyncedAt(), isNull);
      // This device keeps its data.
      expect(profileRepo.getAllProfiles(), isNotEmpty);
    });
  });

  group('deletions sync', () {
    // The bug: merging is a union, so a project deleted on one device came
    // straight back from any other device that still had it.
    test('a deletion here goes up with the backup', () async {
      final service = await signedIn();
      await projectRepo.projectsBox
          .put('gone', TestFactories.makeProject(id: 'gone'));
      await projectRepo.deleteProjectsPermanently(['gone']);

      await service.uploadDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      final deleted = tombstonesFromJson(backupOnDrive()['deletedRecords']);
      expect(deleted.map((t) => t.id), contains('gone'));
    });

    test('a deletion elsewhere removes the row here', () async {
      final service = await signedIn();
      await projectRepo.projectsBox.put(
        'gone',
        TestFactories.makeProject(id: 'gone', updatedAt: DateTime(2026, 1, 1)),
      );
      seedBackupFromAnotherDevice(service, deletedRecords: [
        SyncTombstone(
          id: 'gone',
          kind: TombstoneKind.project,
          deletedAt: DateTime.utc(2026, 2, 1),
        ).toJson(),
      ]);

      final result = await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectRepo.projectsBox.get('gone'), isNull);
      expect(result.projectsDeleted, 1);
      expect(projectIdsOnDrive(), isNot(contains('gone')));
    });

    test('a project edited after it was deleted elsewhere is kept', () async {
      final service = await signedIn();
      await projectRepo.projectsBox.put(
        'revived',
        TestFactories.makeProject(id: 'revived', updatedAt: DateTime(2026, 3, 1)),
      );
      seedBackupFromAnotherDevice(service, deletedRecords: [
        SyncTombstone(
          id: 'revived',
          kind: TombstoneKind.project,
          deletedAt: DateTime.utc(2026, 2, 1),
        ).toJson(),
      ]);

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectRepo.projectsBox.get('revived'), isNotNull);
    });

    test("another device's stale copy of a deleted project is not added back",
        () async {
      final service = await signedIn();
      final stale = TestFactories.makeProject(
        id: 'gone',
        updatedAt: DateTime(2026, 1, 1),
      );
      await projectRepo.projectsBox.put('gone', stale);
      await projectRepo.deleteProjectsPermanently(['gone']);
      seedBackupFromAnotherDevice(service, projects: [
        service.serializeProjectForTest(stale),
      ]);

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectRepo.projectsBox.get('gone'), isNull);
      expect(projectIdsOnDrive(), isNot(contains('gone')));
    });

    test('a release deleted here is not added back', () async {
      final service = await signedIn();
      final release = Release(
        id: 'rel',
        title: 'EP',
        releaseDate: DateTime(2026, 6, 1),
        trackIds: const [],
      );
      await projectRepo.releasesBox.put('rel', release);
      await projectRepo.deleteRelease('rel');
      seedBackupFromAnotherDevice(service, releases: [
        service.serializeReleaseForTest(release),
      ]);

      await service.syncDatabase(
        projectRepo: projectRepo,
        profileRepo: profileRepo,
      );

      expect(projectRepo.releasesBox.get('rel'), isNull);
    });
  });

  group('previewMerge', () {
    test('counts additions, updates and deletions without writing', () async {
      final service = await signedIn();
      await projectRepo.projectsBox.put(
        'edited',
        TestFactories.makeProject(
          id: 'edited',
          notes: 'old',
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await projectRepo.projectsBox.put(
        'same',
        TestFactories.makeProject(id: 'same', updatedAt: DateTime(2026, 1, 1)),
      );
      await projectRepo.projectsBox.put(
        'doomed',
        TestFactories.makeProject(id: 'doomed', updatedAt: DateTime(2026, 1, 1)),
      );
      final remote = {
        'projects': [
          service.serializeProjectForTest(
            TestFactories.makeProject(id: 'new-1'),
          ),
          service.serializeProjectForTest(
            TestFactories.makeProject(
              id: 'edited',
              notes: 'new',
              updatedAt: DateTime(2026, 2, 1),
            ),
          ),
          service.serializeProjectForTest(
            projectRepo.projectsBox.get('same')!,
          ),
        ],
        'deletedRecords': [
          SyncTombstone(
            id: 'doomed',
            kind: TombstoneKind.project,
            deletedAt: DateTime.utc(2026, 2, 1),
          ).toJson(),
        ],
      };

      final preview = await service.previewMerge(remote, profileRepo);

      expect(preview.projectsAdded, 1);
      expect(preview.projectsUpdated, 1);
      expect(preview.projectsDeleted, 1);
      expect(preview.changesNothing, isFalse);
      expect(projectRepo.projectsBox.get('doomed'), isNotNull,
          reason: 'a preview writes nothing');
    });

    test('an identical backup changes nothing', () async {
      final service = await signedIn();
      await projectRepo.projectsBox
          .put('same', TestFactories.makeProject(id: 'same'));
      final preview = await service.previewMerge({
        'projects': [
          service.serializeProjectForTest(projectRepo.projectsBox.get('same')!),
        ],
      }, profileRepo);
      expect(preview.changesNothing, isTrue);
    });
  });

  group('estimateUpload', () {
    test('counts the media files that exist, by size', () async {
      final service = GoogleDriveSyncService();
      final song = File('${tempDir.path}/song.wav')
        ..writeAsBytesSync(List.filled(1000, 1));
      final auto = File('${tempDir.path}/auto.wav')
        ..writeAsBytesSync(List.filled(500, 1));
      await projectRepo.projectsBox.put(
        'a',
        TestFactories.makeProject(id: 'a', previewSongPath: song.path),
      );
      await projectRepo.projectsBox.put(
        'b',
        TestFactories.makeProject(id: 'b', previewSongAutoPath: auto.path),
      );
      await projectRepo.projectsBox.put(
        'c',
        TestFactories.makeProject(id: 'c', previewSongPath: '/no/such/file.wav'),
      );

      final manualOnly = await service.estimateUpload(profileRepo: profileRepo);
      expect(manualOnly.files, 1);
      expect(manualOnly.bytes, 1000);

      final withAuto = await service.estimateUpload(
        profileRepo: profileRepo,
        includeAutoDetected: true,
      );
      expect(withAuto.files, 2);
      expect(withAuto.bytes, 1500);
    });
  });

  group('exclusive', () {
    test('runs one operation at a time', () async {
      final service = GoogleDriveSyncService();
      final order = <String>[];
      final first = service.exclusive(() async {
        order.add('first start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add('first end');
      });
      final second = service.exclusive(() async {
        order.add('second');
      });
      expect(service.isBusy, isTrue);
      await Future.wait([first, second]);
      expect(order, ['first start', 'first end', 'second']);
      expect(service.isBusy, isFalse);
    });
  });
}
