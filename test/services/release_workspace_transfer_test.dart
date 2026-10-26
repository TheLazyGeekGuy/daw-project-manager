import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/services/release_catalog_store.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/services/release_workspace_transfer.dart';
import 'package:daw_project_manager/services/release_workflow_engine.dart';

import '../helpers/release_transfer_fixture.dart';

void main() {
  late Directory root;
  late ReleaseWorkspaceTransfer transfer;

  ReleaseWorkspaceStore workspaces(String profile) => ReleaseWorkspaceStore(
    Directory(p.join(root.path, profile)),
    profileId: profile,
  );
  ReleaseCatalogStore catalog(String profile) => ReleaseCatalogStore(
    Directory(p.join(root.path, profile)),
    profileId: profile,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm_release_transfer_');
    transfer = ReleaseWorkspaceTransfer(root: root);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'unions profiles explicitly, retains extensions, replays idempotently',
    () async {
      await catalog('local').save({
        ...transferCatalog(
          'local',
          artists: [
            {'id': 'local-artist', 'name': 'Local artist'},
          ],
        ),
        'local_extension': {'keep': true},
      }, preserveTimestamps: true);
      await workspaces('local').save(
        'release-1',
        transferWorkspace(
          'local',
          tracks: [
            {'id': 'same', 'title': 'Old title', 'old_extension': 7},
            {'id': 'local-track', 'title': 'Only here'},
          ],
        ),
        preserveTimestamps: true,
      );
      await catalog('remote').save({
        ...transferCatalog(
          'remote',
          updatedAt: '2026-01-03T12:00:00Z',
          artists: [
            {'id': 'remote-artist', 'name': 'Remote artist'},
          ],
        ),
        'future_extension': {'version': 9},
      }, preserveTimestamps: true);
      await workspaces('remote').save('release-1', {
        ...transferWorkspace(
          'remote',
          updatedAt: '2026-01-03T12:00:00Z',
          tracks: [
            {'id': 'remote-track', 'title': 'Incoming first'},
            {'id': 'same', 'title': 'New title', 'old_extension': 7},
          ],
        ),
        'assets': [
          {
            'id': 'master',
            'role': 'master',
            'path': '/not-read/master.wav',
            'validation': 'unverified',
          },
        ],
      }, preserveTimestamps: true);
      final sourceFile = File(p.join(root.path, 'remote', 'release-1.json'));
      final sourceBytes = await sourceFile.readAsBytes();
      final bundle = await transfer.exportProfile('remote');
      final result = await transfer.mergeProfile(
        bundle,
        targetProfileId: 'local',
      );

      expect(result.workspacesChanged, 1);
      expect(result.catalogChanged, isTrue);
      expect(result.conflicts, isEmpty);
      final restored = await workspaces('local').read('release-1');
      expect(restored['profile_id'], 'local');
      expect((restored['tracks'] as List).map((r) => r['id']), [
        'remote-track',
        'same',
        'local-track',
      ]);
      expect((restored['tracks'] as List)[1]['title'], 'New title');
      expect((restored['tracks'] as List)[1]['old_extension'], 7);
      final mergedCatalog = await catalog('local').read();
      expect((mergedCatalog['artists'] as List).map((r) => r['id']).toSet(), {
        'local-artist',
        'remote-artist',
      });
      expect(mergedCatalog['local_extension'], {'keep': true});
      expect(mergedCatalog['future_extension'], {'version': 9});
      expect(await sourceFile.readAsBytes(), sourceBytes);

      final again = await transfer.mergeProfile(
        bundle,
        targetProfileId: 'local',
      );
      expect(again.workspacesChanged, 0);
      expect(again.catalogChanged, isFalse);
      expect(
        (await workspaces('local').read('release-1'))['revision'],
        restored['revision'],
      );
      expect(restored['updated_at'], '2026-01-03T12:00:00Z');
    },
  );

  test(
    'freezes legacy row clocks before unrelated newer rows arrive',
    () async {
      await workspaces('local').save(
        'release-1',
        transferWorkspace(
          'local',
          tracks: [
            {'id': 'old', 'title': 'Original'},
          ],
        ),
        preserveTimestamps: true,
      );
      await transfer.mergeProfile(
        transferBundle(
          'remote',
          workspaces: {
            'release-1': transferWorkspace(
              'remote',
              updatedAt: '2026-01-10T00:00:00Z',
              tracks: [
                {'id': 'new', 'title': 'New song'},
              ],
            ),
          },
        ),
        targetProfileId: 'local',
      );
      var saved = await workspaces('local').read('release-1');
      final old = (saved['tracks'] as List).singleWhere(
        (r) => r['id'] == 'old',
      );
      expect(old['updated_at'], releaseTransferTime);
      await transfer.mergeProfile(
        transferBundle(
          'remote',
          workspaces: {
            'release-1': transferWorkspace(
              'remote',
              updatedAt: '2026-01-05T00:00:00Z',
              tracks: [
                {'id': 'old', 'title': 'Intermediate edit'},
              ],
            ),
          },
        ),
        targetProfileId: 'local',
      );
      saved = await workspaces('local').read('release-1');
      expect(
        (saved['tracks'] as List).singleWhere((r) => r['id'] == 'old')['title'],
        'Intermediate edit',
      );
      expect(saved['updated_at'], '2026-01-10T00:00:00Z');
    },
  );

  test(
    'a newer complete record keeps optional fields deliberately cleared',
    () async {
      await workspaces('local').save(
        'release-1',
        transferWorkspace(
          'local',
          tracks: [
            {
              'id': 'remote-wins',
              'title': 'Song',
              'work_id': 'old-work',
              'isrc': 'OLD',
            },
            {
              'id': 'local-wins',
              'title': 'Song',
              'updated_at': '2026-01-10T00:00:00Z',
            },
          ],
        ),
        preserveTimestamps: true,
      );
      await transfer.mergeProfile(
        transferBundle(
          'remote',
          workspaces: {
            'release-1': transferWorkspace(
              'remote',
              updatedAt: '2026-01-05T00:00:00Z',
              tracks: [
                {'id': 'remote-wins', 'title': 'Song'},
                {'id': 'local-wins', 'title': 'Song', 'work_id': 'stale-work'},
              ],
            ),
          },
        ),
        targetProfileId: 'local',
      );
      final saved = await workspaces('local').read('release-1');
      for (final track in saved['tracks'] as List) {
        expect(track.containsKey('work_id'), isFalse);
        expect(track.containsKey('isrc'), isFalse);
      }
    },
  );

  test(
    'an explicit unknown row clock never inherits a later summary edit',
    () async {
      await workspaces('local').save(
        'release-1',
        transferWorkspace(
          'local',
          updatedAt: '2026-02-01T00:00:00Z',
          tracks: [
            {'id': 'old', 'title': 'Untouched legacy row', 'updated_at': null},
          ],
        ),
        preserveTimestamps: true,
      );
      await transfer.mergeProfile(
        transferBundle(
          'remote',
          workspaces: {
            'release-1': transferWorkspace(
              'remote',
              updatedAt: '2026-01-05T00:00:00Z',
              tracks: [
                {
                  'id': 'old',
                  'title': 'Actual row edit',
                  'updated_at': '2026-01-05T00:00:00Z',
                },
              ],
            ),
          },
        ),
        targetProfileId: 'local',
      );
      final saved = await workspaces('local').read('release-1');
      expect(saved['updated_at'], '2026-02-01T00:00:00Z');
      expect(saved['tracks'][0]['title'], 'Actual row edit');
    },
  );

  test(
    'applies explicit tombstones and accepts a later restored record',
    () async {
      await workspaces('local').save(
        'release-1',
        transferWorkspace(
          'local',
          tracks: [
            {'id': 'gone', 'title': 'Old'},
            {
              'id': 'restored',
              'title': 'Newer restore',
              'updated_at': '2026-01-05T00:00:00Z',
            },
          ],
        ),
        preserveTimestamps: true,
      );
      final incoming = transferWorkspace(
        'remote',
        updatedAt: '2026-01-04T00:00:00Z',
      );
      incoming['deleted_records'] = {
        'tracks': {
          'gone': '2026-01-03T00:00:00Z',
          'restored': '2026-01-03T00:00:00Z',
        },
      };
      await transfer.mergeProfile(
        transferBundle('remote', workspaces: {'release-1': incoming}),
        targetProfileId: 'local',
      );
      var saved = await workspaces('local').read('release-1');
      expect((saved['tracks'] as List).map((r) => r['id']), ['restored']);
      final oldBackup = transferBundle(
        'remote',
        workspaces: {
          'release-1': transferWorkspace(
            'remote',
            tracks: [
              {'id': 'gone', 'title': 'Stale backup'},
            ],
          ),
        },
      );
      await transfer.mergeProfile(oldBackup, targetProfileId: 'local');
      saved = await workspaces('local').read('release-1');
      expect((saved['tracks'] as List).map((r) => r['id']), ['restored']);
      await transfer.mergeProfile(
        transferBundle(
          'remote',
          workspaces: {
            'release-1': transferWorkspace(
              'remote',
              updatedAt: '2026-01-06T00:00:00Z',
              tracks: [
                {'id': 'gone', 'title': 'Explicit restore'},
              ],
            ),
          },
        ),
        targetProfileId: 'local',
      );
      saved = await workspaces('local').read('release-1');
      expect((saved['tracks'] as List).map((r) => r['id']).toSet(), {
        'gone',
        'restored',
      });
      expect(
        saved['deleted_records']['tracks']['gone'],
        '2026-01-03T00:00:00.000Z',
      );
    },
  );

  test(
    'unknown clocks keep local record and report conflict, retaining history',
    () async {
      final local = transferWorkspace('local', updatedAt: null);
      local['distribution'] = [
        {
          'id': 'delivery',
          'status': 'draft',
          'history': [
            {'from': 'none', 'to': 'draft', 'at': releaseTransferTime},
          ],
        },
      ];
      await workspaces(
        'local',
      ).save('release-1', local, preserveTimestamps: true);
      final remote = transferWorkspace('remote', updatedAt: null);
      remote['distribution'] = [
        {
          'id': 'delivery',
          'status': 'submitted',
          'history': [
            {'from': 'draft', 'to': 'submitted', 'at': '2026-01-02T00:00:00Z'},
          ],
        },
      ];
      final result = await transfer.mergeProfile(
        transferBundle('remote', workspaces: {'release-1': remote}),
        targetProfileId: 'local',
      );
      final saved = await workspaces('local').read('release-1');
      expect(saved['distribution'][0]['status'], 'draft');
      expect(saved['distribution'][0]['history'], hasLength(2));
      expect(result.conflicts, ['release/release-1/distribution/delivery']);
    },
  );

  test(
    'rejects profile mismatch, unsafe identifiers and invalid tombstones',
    () async {
      final mismatch = transferBundle(
        'remote',
        catalog: transferCatalog('other'),
      );
      await expectLater(
        transfer.mergeProfile(mismatch, targetProfileId: 'local'),
        throwsFormatException,
      );
      await expectLater(
        transfer.mergeProfile(
          transferBundle('remote'),
          targetProfileId: '../outside',
        ),
        throwsFormatException,
      );
      final badTombstone = transferWorkspace('remote');
      badTombstone['deleted_records'] = {
        'tracks': {'x': 'yesterday'},
      };
      await expectLater(
        transfer.mergeProfile(
          transferBundle('remote', workspaces: {'release-1': badTombstone}),
          targetProfileId: 'local',
        ),
        throwsFormatException,
      );
      expect(await root.list().isEmpty, isTrue);
    },
  );

  test('preflights all documents before writing any catalog record', () async {
    await catalog(
      'local',
    ).save(transferCatalog('local'), preserveTimestamps: true);
    final before = await catalog('local').read();
    final invalid = transferWorkspace(
      'remote',
      releaseId: 'release-2',
      tracks: [
        {'id': 'duplicate', 'title': 'One'},
        {'id': 'duplicate', 'title': 'Two'},
      ],
    );
    await expectLater(
      transfer.mergeProfile(
        transferBundle(
          'remote',
          catalog: transferCatalog(
            'remote',
            artists: [
              {'id': 'new', 'name': 'Must not be written'},
            ],
          ),
          workspaces: {
            'release-1': transferWorkspace('remote'),
            'release-2': invalid,
          },
        ),
        targetProfileId: 'local',
      ),
      throwsFormatException,
    );
    expect(await catalog('local').read(), before);
    expect(await workspaces('local').listReleaseIds(), isEmpty);
  });

  test('catalog deletion cannot break an unchanged local workspace', () async {
    await catalog('local').save(
      transferCatalog(
        'local',
        artists: [
          {'id': 'artist', 'name': 'Referenced artist'},
        ],
      ),
      preserveTimestamps: true,
    );
    await workspaces('local').save('release-1', {
      ...transferWorkspace('local'),
      'artist_ids': ['artist'],
    }, preserveTimestamps: true);
    final incoming = transferCatalog(
      'remote',
      updatedAt: '2026-02-01T00:00:00Z',
    );
    incoming['deleted_records'] = {
      'artists': {'artist': '2026-02-01T00:00:00Z'},
    };
    await expectLater(
      transfer.mergeProfile(
        transferBundle('remote', catalog: incoming),
        targetProfileId: 'local',
      ),
      throwsFormatException,
    );
    expect((await catalog('local').read())['artists'], hasLength(1));
  });

  test(
    'filters live release IDs without erasing orphaned metadata files',
    () async {
      for (final id in ['release-1', 'release-2']) {
        await workspaces('remote').save(
          id,
          transferWorkspace('remote', releaseId: id),
          preserveTimestamps: true,
        );
      }
      final filtered = await transfer.exportProfile(
        'remote',
        releaseIds: {'release-1'},
      );
      expect((filtered['workspaces'] as Map).keys, ['release-1']);
      expect(await workspaces('remote').listReleaseIds(), [
        'release-1',
        'release-2',
      ]);
      final result = await transfer.mergeProfile(
        await transfer.exportProfile('remote'),
        targetProfileId: 'local',
        allowedReleaseIds: {'release-1'},
      );
      expect(result.skippedReleaseIds, ['release-2']);
      expect(await workspaces('local').listReleaseIds(), ['release-1']);
    },
  );

  test(
    'unreadable native metadata aborts export rather than omitting it',
    () async {
      await workspaces('local').save('release-1', transferWorkspace('local'));
      await File(
        p.join(root.path, 'local', 'release-1.json'),
      ).writeAsString('{broken');
      await expectLater(transfer.exportProfile('local'), throwsFormatException);
    },
  );

  test(
    'imported verification preserves evidence but requires a local check',
    () async {
      final workspace = transferWorkspace(
        'remote',
        tracks: [
          {'id': 'track', 'title': 'Song'},
        ],
      );
      workspace['assets'] = [
        {
          'id': 'master',
          'role': 'master',
          'track_id': 'track',
          'path': r'C:\\Studio\\master.wav',
          'validation': 'verified',
          'sha256': 'a' * 64,
          'bytes': 123,
          'verified_at': releaseTransferTime,
        },
      ];
      final bundle = transferBundle(
        'remote',
        workspaces: {'release-1': workspace},
      );
      await transfer.mergeProfile(bundle, targetProfileId: 'local');
      final saved = await workspaces('local').read('release-1');
      expect(saved['assets'][0]['validation'], 'unverified');
      expect(saved['assets'][0]['sha256'], 'a' * 64);
      expect(saved['assets'][0]['verified_at'], releaseTransferTime);
      expect(
        const ReleaseWorkflowEngine()
            .evaluate(saved)
            .assetsRequiringVerification,
        ['master'],
      );
      final replay = await transfer.mergeProfile(
        bundle,
        targetProfileId: 'local',
      );
      expect(replay.workspacesChanged, 0);
      expect(replay.conflicts, isEmpty);
      expect(workspace['assets'][0]['validation'], 'verified');
    },
  );

  test(
    'does not mutate the incoming snapshot while remapping a profile',
    () async {
      final incoming = transferBundle(
        'remote',
        workspaces: {
          'release-1': transferWorkspace(
            'remote',
            tracks: [
              {'id': 't', 'title': 'Song'},
            ],
          ),
        },
      );
      final before = jsonEncode(incoming);
      await transfer.mergeProfile(incoming, targetProfileId: 'local');
      expect(jsonEncode(incoming), before);
    },
  );
}
