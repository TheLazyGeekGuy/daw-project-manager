import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/services/backup_service.dart';
import 'package:daw_project_manager/services/release_catalog_store.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/services/release_workspace_transfer.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/release_transfer_fixture.dart';
import 'flow_library.dart';

void main() {
  late FlowLibrary lib;

  setUp(() async {
    lib = await FlowLibrary.open(only: ['cubase/Klone - NN (Cubase 5)']);
  });
  tearDown(() async => lib.close());

  Future<void> seed() async {
    await lib.scan();
    await lib.repo.addRelease(
      Release(
        id: 'release-1',
        title: 'Restorable EP',
        trackIds: lib.projects.map((project) => project.id).toList(),
      ),
    );
    final transfer = ReleaseWorkspaceTransfer.forRepository(lib.repo);
    final directory = Directory(p.join(transfer.root.path, lib.profileId));
    await ReleaseCatalogStore(directory, profileId: lib.profileId).save({
      ...transferCatalog(
        lib.profileId,
        artists: [
          {'id': 'artist', 'name': 'Studio artist'},
        ],
      ),
      'holders': [
        {'id': 'holder', 'name': 'Writer'},
      ],
      'works': [
        {
          'id': 'work',
          'title': 'Composition',
          'shares': [
            {'holder_id': 'holder', 'role': 'composer', 'percentage': 100},
          ],
        },
      ],
      'tracks': [
        {
          'id': 'recording',
          'title': 'Master',
          'work_id': 'work',
          'credits': [
            {'artist_id': 'artist', 'role': 'performer'},
          ],
        },
      ],
      'playlists': [
        {
          'id': 'playlist',
          'title': 'Launch set',
          'track_ids': ['recording'],
        },
      ],
    });
    await ReleaseWorkspaceStore(directory, profileId: lib.profileId).save(
      'release-1',
      {
        ...transferWorkspace(
          lib.profileId,
          tracks: [
            {
              'id': 'recording',
              'title': 'Master',
              'project_id': lib.projects.first.id,
              'work_id': 'work',
            },
          ],
        ),
        'artist_ids': ['artist'],
        'assets': [
          {
            'id': 'master-asset',
            'role': 'master',
            'path': '/not-transferred/master.wav',
            'validation': 'unverified',
          },
        ],
        'campaigns': [
          {
            'id': 'campaign',
            'title': 'Launch',
            'track_ids': ['recording'],
          },
        ],
        'communications': [
          {
            'id': 'post',
            'title': 'Announcement',
            'platform': 'Bandcamp',
            'status': 'draft',
            'campaign_id': 'campaign',
            'asset_ids': ['master-asset'],
          },
        ],
        'tasks': [
          {
            'id': 'task',
            'title': 'Approve artwork',
            'status': 'todo',
            'depends_on': [],
          },
        ],
        'future_extension': {
          'retain': [1, 2, 3],
        },
      },
    );
  }

  test(
    'actual backup survives loss of Hive and native metadata together',
    () async {
      await seed();
      final profiles = await HiveTestHelper.createProfileRepository();
      final original = await ReleaseWorkspaceTransfer.forRepository(
        lib.repo,
      ).exportProfile(lib.profileId);
      final backup = await BackupService.buildBackupJson(
        projectRepo: lib.repo,
        profileRepo: profiles,
        profileId: lib.profileId,
      );
      expect(jsonDecode(backup)['version'], '1.5');
      expect(
        jsonDecode(backup)['releaseWorkspace']['catalog']['playlists'],
        hasLength(1),
      );

      await lib.wipeDatabase();
      final result = await BackupService.importBackupJson(
        backup,
        projectRepo: lib.repo,
        profileRepo: await HiveTestHelper.createProfileRepository(),
        currentProfileId: lib.profileId,
        importMode: ImportMode.replace,
      );
      expect(result.releaseMetadata?.workspacesChanged, 1);
      expect(result.releaseMetadata?.catalogChanged, isTrue);
      expect(lib.repo.getAllReleases().single.id, 'release-1');
      final restored = await ReleaseWorkspaceTransfer.forRepository(
        lib.repo,
      ).exportProfile(lib.profileId);
      expect(restored['catalog']['works'][0]['shares'][0]['percentage'], 100);
      expect(
        restored['catalog']['playlists'],
        original['catalog']['playlists']
            .map(
              (row) => {
                ...row,
                'updated_at': original['catalog']['updated_at'],
              },
            )
            .toList(),
      );
      final workspace = restored['workspaces']['release-1'];
      expect(workspace['tasks'][0]['title'], 'Approve artwork');
      expect(workspace['assets'][0]['path'], '/not-transferred/master.wav');
      expect(workspace['communications'][0]['campaign_id'], 'campaign');
      expect(workspace['future_extension'], {
        'retain': [1, 2, 3],
      });
      expect(
        workspace['updated_at'],
        original['workspaces']['release-1']['updated_at'],
      );
    },
  );

  test('new-profile import remaps only the metadata envelope', () async {
    await seed();
    final profiles = await HiveTestHelper.createProfileRepository();
    final backup = await BackupService.buildBackupJson(
      projectRepo: lib.repo,
      profileRepo: profiles,
      profileId: lib.profileId,
    );
    final result = await BackupService.importBackupJson(
      backup,
      projectRepo: lib.repo,
      profileRepo: profiles,
      currentProfileId: lib.profileId,
      importMode: ImportMode.createNewProfile,
      newProfileName: 'Restored copy',
    );
    final id = result.newProfileId!;
    expect(id, isNot(lib.profileId));
    final transfer = ReleaseWorkspaceTransfer.forRepository(lib.repo);
    final restored = await transfer.exportProfile(id);
    expect(restored['catalog']['profile_id'], id);
    expect(restored['workspaces']['release-1']['profile_id'], id);
    expect(restored['workspaces']['release-1']['tracks'][0]['id'], 'recording');
    expect(
      (await transfer.exportProfile(lib.profileId))['catalog']['profile_id'],
      lib.profileId,
    );
  });

  test(
    'older backup and profile switch mismatch cannot erase new metadata',
    () async {
      await seed();
      final profiles = await HiveTestHelper.createProfileRepository();
      final before = await ReleaseWorkspaceTransfer.forRepository(
        lib.repo,
      ).exportProfile(lib.profileId);
      await BackupService.importBackupJson(
        jsonEncode({'version': '1.4'}),
        projectRepo: lib.repo,
        profileRepo: profiles,
        currentProfileId: lib.profileId,
        importMode: ImportMode.merge,
      );
      expect(
        await ReleaseWorkspaceTransfer.forRepository(
          lib.repo,
        ).exportProfile(lib.profileId),
        before,
      );
      await expectLater(
        BackupService.buildBackupJson(
          projectRepo: lib.repo,
          profileRepo: profiles,
          profileId: 'another-profile',
        ),
        throwsFormatException,
      );
      await expectLater(
        BackupService.importBackupJson(
          jsonEncode({'version': '1.5'}),
          projectRepo: lib.repo,
          profileRepo: profiles,
          currentProfileId: 'another-profile',
          importMode: ImportMode.replace,
        ),
        throwsException,
      );
      expect(lib.repo.getAllReleases().single.id, 'release-1');
    },
  );
}
