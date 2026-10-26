import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/repository/sync_tombstones.dart';
import 'package:daw_project_manager/services/google_drive_sync_service.dart';
import 'package:daw_project_manager/services/release_catalog_store.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/services/release_workspace_transfer.dart';

import '../helpers/fake_drive.dart';
import '../helpers/hive_test_helper.dart';
import '../helpers/release_transfer_fixture.dart';

void main() {
  late Directory temp;
  late ProjectRepository repo;
  late ProfileRepository profiles;
  late Profile profile;
  late FakeDrive drive;
  late GoogleDriveSyncService service;

  ReleaseWorkspaceStore store(String id) => ReleaseWorkspaceStore(
    Directory(p.join(temp.path, 'release-workspaces', id)),
    profileId: id,
  );
  ReleaseCatalogStore catalog(String id) => ReleaseCatalogStore(
    Directory(p.join(temp.path, 'release-workspaces', id)),
    profileId: id,
  );

  setUp(() async {
    temp = await HiveTestHelper.setUp();
    profiles = await HiveTestHelper.createProfileRepository();
    profile = await profiles.createProfile('Studio');
    repo = await HiveTestHelper.createRepository(profileId: profile.id);
    drive = FakeDrive();
    service = GoogleDriveSyncService()..driveApi = drive.api;
    await service.ensureAppDataFolder();
  });
  tearDown(() async {
    service.dispose();
    await HiveTestHelper.tearDown(temp);
  });

  void remote(Map<String, dynamic> value) {
    final folder = drive.files.values.firstWhere(
      (f) => f.isFolder && f.parents.contains('root'),
    );
    drive.seed(
      name: 'database_backup.json',
      parent: folder.id,
      content: utf8.encode(jsonEncode(value)),
    );
  }

  Map<String, dynamic> uploaded() =>
      jsonDecode(drive.named('database_backup.json')!.text)
          as Map<String, dynamic>;

  test(
    'real sync merges then uploads native metadata in separate profiles',
    () async {
      final other = await profiles.createProfile('Other studio');
      await repo.addRelease(
        Release(id: 'release-1', title: 'Main EP', trackIds: []),
      );
      final otherBox = await Hive.openBox<Release>('${other.id}_releases');
      await otherBox.put(
        'release-1',
        Release(id: 'release-1', title: 'Other EP', trackIds: []),
      );
      await store(profile.id).save(
        'release-1',
        transferWorkspace(
          profile.id,
          tracks: [
            {'id': 'local', 'title': 'Local track'},
          ],
        ),
        preserveTimestamps: true,
      );
      await catalog(profile.id).save(
        transferCatalog(
          profile.id,
          artists: [
            {'id': 'local-artist', 'name': 'Here'},
          ],
        ),
        preserveTimestamps: true,
      );
      await store(other.id).save(
        'release-1',
        transferWorkspace(
          other.id,
          tracks: [
            {'id': 'isolated', 'title': 'Other profile only'},
          ],
        ),
        preserveTimestamps: true,
      );
      remote({
        'version': '1.8',
        'releaseWorkspacesByProfile': {
          profile.id: transferBundle(
            profile.id,
            catalog: transferCatalog(
              profile.id,
              updatedAt: '2026-02-01T00:00:00Z',
              artists: [
                {'id': 'remote-artist', 'name': 'Phone'},
              ],
            ),
            workspaces: {
              'release-1': {
                ...transferWorkspace(
                  profile.id,
                  updatedAt: '2026-02-01T00:00:00Z',
                  tracks: [
                    {'id': 'remote', 'title': 'Phone track'},
                  ],
                ),
                'assets': [
                  {
                    'id': 'master',
                    'role': 'master',
                    'path': '/never-upload/master.wav',
                    'validation': 'unverified',
                  },
                ],
              },
            },
          ),
        },
      });
      final result = await service.syncDatabase(
        projectRepo: repo,
        profileRepo: profiles,
        downloadPreviewSongs: false,
      );
      expect(result.releaseMetadataByProfile[profile.id]?.workspacesChanged, 1);
      final snapshots = uploaded()['releaseWorkspacesByProfile'];
      expect(
        (snapshots[profile.id]['workspaces']['release-1']['tracks'] as List)
            .map((row) => row['id'])
            .toSet(),
        {'local', 'remote'},
      );
      expect(
        snapshots[other.id]['workspaces']['release-1']['tracks'][0]['id'],
        'isolated',
      );
      expect(
        (snapshots[profile.id]['catalog']['artists'] as List)
            .map((row) => row['id'])
            .toSet(),
        {'local-artist', 'remote-artist'},
      );
      expect(
        snapshots[profile.id]['workspaces']['release-1']['assets'][0]['path'],
        '/never-upload/master.wav',
      );
      expect(
        drive.files.values.where((file) => file.name == 'master.wav'),
        isEmpty,
      );
    },
  );

  test(
    'release tombstone excludes orphan workspace from the uploaded snapshot',
    () async {
      await repo.addRelease(
        Release(id: 'release-1', title: 'Deleted EP', trackIds: []),
      );
      await store(profile.id).save('release-1', transferWorkspace(profile.id));
      final bundle = await ReleaseWorkspaceTransfer.forRepository(
        repo,
      ).exportProfile(profile.id);
      remote({
        'deletedRecords': [
          SyncTombstone(
            id: 'release-1',
            kind: TombstoneKind.release,
            profileId: profile.id,
            deletedAt: DateTime.utc(2026, 3, 1),
          ).toJson(),
        ],
        'releaseWorkspacesByProfile': {profile.id: bundle},
      });
      final result = await service.syncDatabase(
        projectRepo: repo,
        profileRepo: profiles,
        downloadPreviewSongs: false,
      );
      expect(repo.getAllReleases(), isEmpty);
      expect(result.releaseMetadataByProfile[profile.id]?.skippedReleaseIds, [
        'release-1',
      ]);
      expect(
        uploaded()['releaseWorkspacesByProfile'][profile.id]['workspaces'],
        isEmpty,
      );
      expect(await store(profile.id).listReleaseIds(), ['release-1']);
    },
  );

  test(
    'unknown native profile fails before any incoming profile is written',
    () async {
      remote({
        'profiles': [
          {
            'id': profile.id,
            'name': 'Should not be written',
            'createdAt': releaseTransferTime,
          },
        ],
        'releaseWorkspacesByProfile': {'unknown': transferBundle('unknown')},
      });
      final before = drive.named('database_backup.json')!.text;
      await expectLater(
        service.syncDatabase(
          projectRepo: repo,
          profileRepo: profiles,
          downloadPreviewSongs: false,
        ),
        throwsFormatException,
      );
      expect(profiles.getProfileById(profile.id)!.name, 'Studio');
      expect(drive.named('database_backup.json')!.text, before);
    },
  );

  test(
    'mismatched profile envelope aborts sync before replacing Drive data',
    () async {
      remote({
        'releaseWorkspacesByProfile': {
          profile.id: transferBundle('another-profile'),
        },
      });
      final before = drive.named('database_backup.json')!.text;
      await expectLater(
        service.syncDatabase(
          projectRepo: repo,
          profileRepo: profiles,
          downloadPreviewSongs: false,
        ),
        throwsFormatException,
      );
      expect(drive.named('database_backup.json')!.text, before);
      expect(await store(profile.id).listReleaseIds(), isEmpty);
    },
  );
}
