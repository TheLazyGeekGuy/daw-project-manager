import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/services/release_workflow_validator.dart';

void main() {
  late Directory root;
  late ReleaseWorkspaceStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm-workspace-transactions-');
    store = ReleaseWorkspaceStore(root, profileId: 'profile-a');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'new documents are schema two and reading does not create a profile',
    () async {
      final absent = Directory(p.join(root.path, 'not-created'));
      final fresh = await ReleaseWorkspaceStore(absent).read('album');
      expect(fresh['schema_version'], 2);
      expect(fresh['revision'], 0);
      for (final key in ['assets', 'campaigns', 'tasks']) {
        expect(fresh[key], isEmpty);
      }
      expect(await absent.exists(), isFalse);
    },
  );

  test(
    'v1 migration is in memory and the first edit snapshots exact old bytes',
    () async {
      final file = File(p.join(root.path, 'album.json'));
      const original =
          '{"schema_version":1,"release_id":"album",'
          '"collection_type":"ep","artist_ids":["a"],'
          '"vendor_extension":{"untouched":[1,2,3]}}';
      await file.writeAsString(original);
      final value = await store.read('album');
      expect(value['schema_version'], 2);
      expect(value['revision'], 0);
      expect(value['collection_type'], 'ep');
      expect(value['assets'], isEmpty);
      expect(await file.readAsString(), original);
      await store.save('album', {
        ...value,
        'collection_type': 'single',
      }, expectedRevision: 0);
      final saved = await store.read('album');
      expect(saved['revision'], 1);
      expect(saved['vendor_extension'], {
        'untouched': [1, 2, 3],
      });
      final snapshots = await root
          .list()
          .where((e) => e.path.endsWith('.previous.json'))
          .toList();
      expect(snapshots, hasLength(1));
      expect(await File(snapshots.single.path).readAsString(), original);
    },
  );

  test('unknown top-level fields survive a partial edit', () async {
    final value = await store.read('album');
    await store.save('album', {
      ...value,
      'extension': {'future': true},
    });
    await store.save('album', {
      'schema_version': 2,
      'release_id': 'album',
      'collection_type': 'ep',
    }, expectedRevision: 1);
    expect((await store.read('album'))['extension'], {'future': true});
  });

  test('save captures its submitted snapshot before asynchronous IO', () async {
    final value = await store.read('album');
    final saving = store.save('album', value);
    (value['tracks'] as List).add({'id': 'later', 'title': 'Later edit'});
    await saving;
    expect((await store.read('album'))['tracks'], isEmpty);
  });

  test(
    'local edits stamp UTC but incoming saves can retain their timestamp',
    () async {
      await store.save('album', await store.read('album'));
      final local = await store.read('album');
      expect(DateTime.parse(local['updated_at'] as String).isUtc, isTrue);
      const incoming = '2020-01-02T03:04:05.000Z';
      await store.save(
        'album',
        {...local, 'updated_at': incoming},
        expectedRevision: 1,
        preserveTimestamps: true,
      );
      final merged = await store.read('album');
      expect(merged['updated_at'], incoming);
      expect(merged['revision'], 2);
    },
  );

  test(
    'legacy record IDs and communication labels migrate deterministically',
    () async {
      final file = File(p.join(root.path, 'album.json'));
      final legacy = {
        'schema_version': 1,
        'release_id': 'album',
        'rights_filings': [
          {'organization': 'SACEM', 'status': 'draft', 'custom': 42},
        ],
        'distribution': [
          {
            'distributor': 'Local',
            'status': 'draft',
            'platforms': [
              {'platform': 'Spotify', 'status': 'draft'},
            ],
          },
        ],
        'communications': [
          {'platform': 'YouTube', 'status': 'planned'},
        ],
      };
      final bytes = jsonEncode(legacy);
      await file.writeAsString(bytes);
      final first = await store.read('album');
      final second = await store.read('album');
      expect(first, second);
      expect(first['rights_filings'][0]['id'], startsWith('legacy-'));
      expect(first['rights_filings'][0]['custom'], 42);
      expect(first['communications'][0]['title'], 'YouTube');
      expect(const ReleaseWorkflowValidator().validate(first), isEmpty);
      expect(await file.readAsString(), bytes);
      await store.save('album', first, expectedRevision: 0);
      expect(
        (await store.read('album'))['rights_filings'],
        first['rights_filings'],
      );
    },
  );

  test(
    'workspace inventory excludes catalog, snapshots and invalid names',
    () async {
      await store.save('b', await store.read('b'));
      await store.save('a', await store.read('a'));
      await store.save('a', await store.read('a'));
      await Directory(p.join(root.path, 'catalog')).create();
      await File(
        p.join(root.path, 'catalog', 'library.json'),
      ).writeAsString('{}');
      await File(p.join(root.path, '.hidden.json')).writeAsString('{}');
      await File(p.join(root.path, 'invalid name.json')).writeAsString('{}');
      await Directory(p.join(root.path, 'directory.json')).create();
      expect(await store.listReleaseIds(), ['a', 'b']);
    },
  );

  test(
    'default import cannot overwrite an existing unversioned workspace',
    () async {
      final legacy = File(p.join(root.path, 'legacy-source.json'));
      final destination = File(p.join(root.path, 'album.json'));
      const original = '{"schema_version":1,"release_id":"album"}';
      await legacy.writeAsString(original);
      await destination.writeAsString(original);
      await expectLater(
        store.importLegacy(
          legacy,
          releaseId: 'album',
          destinationProfileId: 'profile-a',
        ),
        throwsStateError,
      );
      expect(await destination.readAsString(), original);
      expect(await legacy.readAsString(), original);
    },
  );

  test('stale editor revision cannot overwrite a newer revision', () async {
    final initial = await store.read('album');
    await store.save('album', {
      ...initial,
      'collection_type': 'single',
    }, expectedRevision: 0);
    final committed = await File(p.join(root.path, 'album.json')).readAsBytes();
    await expectLater(
      store.save('album', {
        ...initial,
        'collection_type': 'ep',
      }, expectedRevision: 0),
      throwsA(
        isA<ReleaseRevisionConflict>().having((e) => e.actual, 'actual', 1),
      ),
    );
    expect(
      await File(p.join(root.path, 'album.json')).readAsBytes(),
      committed,
    );
  });

  test(
    'two concurrent store instances cannot both commit the same revision',
    () async {
      final initial = await store.read('album');
      final second = ReleaseWorkspaceStore(root, profileId: 'profile-a');
      Future<Object> attempt(ReleaseWorkspaceStore target, String type) async {
        try {
          await target.save('album', {
            ...initial,
            'collection_type': type,
          }, expectedRevision: 0);
          return 'saved';
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        attempt(store, 'ep'),
        attempt(second, 'single'),
      ]);
      expect(results.where((result) => result == 'saved'), hasLength(1));
      expect(results.whereType<ReleaseRevisionConflict>(), hasLength(1));
      expect((await store.read('album'))['revision'], 1);
    },
  );

  test('profiles and document identities remain isolated', () async {
    final first = ReleaseWorkspaceStore(
      Directory(p.join(root.path, 'a')),
      profileId: 'a',
    );
    final second = ReleaseWorkspaceStore(
      Directory(p.join(root.path, 'b')),
      profileId: 'b',
    );
    final a = await first.read('same-id');
    await first.save('same-id', {...a, 'collection_type': 'ep'});
    expect((await second.read('same-id'))['collection_type'], 'album');
    await expectLater(second.save('same-id', a), throwsFormatException);
    expect((await first.read('same-id'))['profile_id'], 'a');
  });

  test('successive revisions keep distinct verified snapshots', () async {
    for (var revision = 0; revision < 4; revision++) {
      final current = await store.read('album');
      await store.save('album', {
        ...current,
        'note': 'edit $revision',
      }, expectedRevision: revision);
    }
    final snapshots = await root
        .list()
        .where((e) => e.path.endsWith('.previous.json'))
        .toList();
    expect(snapshots, hasLength(3));
    final revisions = <int>[];
    for (final snapshot in snapshots) {
      revisions.add(
        (jsonDecode(await File(snapshot.path).readAsString())
                as Map)['revision']
            as int,
      );
    }
    expect(revisions..sort(), [1, 2, 3]);
  });

  Future<Map<String, dynamic>> prepareInterruption({
    bool removeDestination = false,
  }) async {
    final initial = await store.read('album');
    await store.save('album', initial, expectedRevision: 0);
    final destination = File(p.join(root.path, 'album.json'));
    final oldBytes = await destination.readAsBytes();
    final next = {
      ...await store.read('album'),
      'revision': 2,
      'collection_type': 'single',
    };
    final nextBytes = utf8.encode(jsonEncode(next));
    await File(p.join(root.path, '.album-crash.tmp')).writeAsBytes(nextBytes);
    await File(
      p.join(root.path, '.album-crash.previous.json'),
    ).writeAsBytes(oldBytes);
    final journal = {
      'schema_version': 1,
      'document': 'album.json',
      'staging': '.album-crash.tmp',
      'sha256': sha256.convert(nextBytes).toString(),
      'previous': '.album-crash.previous.json',
      'previous_sha256': sha256.convert(oldBytes).toString(),
    };
    await File(
      p.join(root.path, '.album.pending.json'),
    ).writeAsString(jsonEncode(journal));
    if (removeDestination) await destination.delete();
    return journal;
  }

  test(
    'prepared transaction is recovered after interrupted replacement',
    () async {
      await prepareInterruption(removeDestination: true);
      final recovered = await store.read('album');
      expect(recovered['revision'], 2);
      expect(recovered['collection_type'], 'single');
      expect(
        await File(p.join(root.path, '.album.pending.json')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(root.path, '.album-crash.tmp')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(root.path, '.album-crash.previous.json')).exists(),
        isTrue,
      );
    },
  );

  test(
    'recovery retains prior bytes if interrupted output is missing',
    () async {
      await prepareInterruption(removeDestination: true);
      await File(p.join(root.path, '.album-crash.tmp')).delete();
      final recovered = await store.read('album');
      expect(recovered['revision'], 1);
      expect(recovered['collection_type'], 'album');
      expect(
        await File(p.join(root.path, 'album.json')).readAsBytes(),
        await File(
          p.join(root.path, '.album-crash.previous.json'),
        ).readAsBytes(),
      );
    },
  );

  test(
    'recovery refuses to overwrite an unrelated destination change',
    () async {
      await prepareInterruption();
      final changed = jsonEncode({
        'schema_version': 2,
        'release_id': 'album',
        'revision': 99,
      });
      final destination = File(p.join(root.path, 'album.json'));
      await destination.writeAsString(changed);
      await expectLater(
        store.read('album'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.readAsString(), changed);
      expect(
        await File(p.join(root.path, '.album.pending.json')).exists(),
        isTrue,
      );
    },
  );

  test(
    'recovery rejects traversal without reading or deleting the target',
    () async {
      final journal = await prepareInterruption();
      final victim = File(p.join(root.path, 'victim.txt'));
      await victim.writeAsString('keep');
      await File(
        p.join(root.path, '.album.pending.json'),
      ).writeAsString(jsonEncode({...journal, 'staging': '../victim.txt'}));
      await expectLater(store.read('album'), throwsFormatException);
      expect(await victim.readAsString(), 'keep');
    },
  );

  test(
    'explicit legacy import copies and fingerprints without deleting source',
    () async {
      final legacy = File(p.join(root.path, 'legacy.json'));
      final original = jsonEncode({
        'schema_version': 1,
        'release_id': 'album',
        'profile_id': 'legacy-profile',
        'extra': {'keep': true},
      });
      await legacy.writeAsString(original);
      await store.importLegacy(
        legacy,
        releaseId: 'album',
        destinationProfileId: 'profile-a',
      );
      final imported = await store.read('album');
      expect(imported['schema_version'], 2);
      expect(imported['profile_id'], 'profile-a');
      expect(imported['extra'], {'keep': true});
      expect(imported['legacy_import']['source_profile_id'], 'legacy-profile');
      expect(
        imported['legacy_import']['source_sha256'],
        sha256.convert(utf8.encode(original)).toString(),
      );
      expect(await legacy.readAsString(), original);
      await expectLater(
        store.importLegacy(
          legacy,
          releaseId: 'album',
          destinationProfileId: 'profile-a',
        ),
        throwsA(isA<ReleaseRevisionConflict>()),
      );
    },
  );

  test(
    'import requires the confirmed destination and cannot import itself',
    () async {
      final value = await store.read('album');
      await store.save('album', value);
      final source = File(p.join(root.path, 'album.json'));
      await expectLater(
        store.importLegacy(
          source,
          releaseId: 'album',
          destinationProfileId: 'wrong',
        ),
        throwsFormatException,
      );
      await expectLater(
        store.importLegacy(
          source,
          releaseId: 'album',
          destinationProfileId: 'profile-a',
        ),
        throwsFormatException,
      );
      expect((await store.read('album'))['revision'], 1);
    },
  );

  test(
    'symlinked documents and profile directories are refused',
    () async {
      final outside = File(p.join(root.path, 'outside.json'));
      await outside.writeAsString('{"sentinel":true}');
      await Link(p.join(root.path, 'album.json')).create(outside.path);
      await expectLater(
        store.read('album'),
        throwsA(isA<FileSystemException>()),
      );
      final real = Directory(p.join(root.path, 'real'));
      await real.create();
      final linked = Link(p.join(root.path, 'linked'));
      await linked.create(real.path);
      final unsafe = ReleaseWorkspaceStore(Directory(linked.path));
      await expectLater(
        unsafe.read('album'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.readAsString(), '{"sentinel":true}');
    },
    skip: Platform.isWindows
        ? 'Creating Windows symlinks requires elevated privileges'
        : false,
  );

  test(
    'unsupported schemas and malformed arrays never replace saved bytes',
    () async {
      final value = await store.read('album');
      await store.save('album', value);
      final bytes = await File(p.join(root.path, 'album.json')).readAsBytes();
      for (final invalid in [
        {...value, 'schema_version': 999},
        {...value, 'assets': 'not a list'},
        {
          ...value,
          'tracks': [42],
        },
        {...value, 'revision': -1},
      ]) {
        await expectLater(store.save('album', invalid), throwsFormatException);
      }
      expect(await File(p.join(root.path, 'album.json')).readAsBytes(), bytes);
    },
  );
}
