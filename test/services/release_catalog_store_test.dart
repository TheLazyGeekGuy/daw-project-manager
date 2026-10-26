import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/services/release_catalog_store.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';

void main() {
  late Directory root;
  late ReleaseCatalogStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm-release-catalog-');
    store = ReleaseCatalogStore(root, profileId: 'profile-a');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<Map<String, dynamic>> catalog() async => {
    ...await store.read(),
    'artists': [
      {
        'id': 'artist-a',
        'name': 'Alice',
        'aliases': ['A'],
        'roles': ['composer'],
        'custom': true,
      },
    ],
    'holders': [
      {'id': 'holder-a', 'name': 'Alice', 'ipi': '123456789'},
    ],
    'works': [
      {
        'id': 'work-a',
        'title': 'Song',
        'shares': [
          {'holder_id': 'holder-a', 'role': 'composer', 'percentage': 100},
        ],
      },
    ],
    'tracks': [
      {
        'id': 'track-a',
        'title': 'Song — master',
        'work_id': 'work-a',
        'project_id': 'project-a',
        'credits': [
          {'artist_id': 'artist-a', 'role': 'performer'},
        ],
      },
    ],
    'playlists': [
      {
        'id': 'playlist-a',
        'title': 'Collection',
        'track_ids': ['track-a', 'track-a'],
      },
    ],
  };

  test(
    'catalog persists complete shared records in a reserved subdirectory',
    () async {
      final value = await catalog();
      await store.save(value, expectedRevision: 0);
      final restored = await store.read();
      expect(restored['revision'], 1);
      expect(restored['artists'], value['artists']);
      expect(restored['tracks'], value['tracks']);
      expect(restored['playlists'], value['playlists']);
      expect(
        await File(p.join(root.path, 'catalog', 'library.json')).exists(),
        isTrue,
      );
      final workspace = ReleaseWorkspaceStore(root, profileId: 'profile-a');
      await workspace.save('library', await workspace.read('library'));
      expect((await store.read())['artists'], value['artists']);
    },
  );

  test('catalog revision conflicts preserve a newer edit', () async {
    final value = await catalog();
    await store.save(value, expectedRevision: 0);
    await expectLater(
      store.save(value, expectedRevision: 0),
      throwsA(isA<ReleaseRevisionConflict>()),
    );
    expect((await store.read())['revision'], 1);
  });

  test('profile catalogs do not share records', () async {
    await store.save(await catalog());
    final other = ReleaseCatalogStore(
      Directory(p.join(root.path, 'other')),
      profileId: 'other',
    );
    expect((await other.read())['artists'], isEmpty);
    await expectLater(other.save(await store.read()), throwsFormatException);
  });

  test('catalog rejects duplicate IDs and dangling references', () async {
    final value = await catalog();
    final invalidDocuments = [
      {
        ...value,
        'artists': [...value['artists'] as List, ...value['artists'] as List],
      },
      {...value, 'holders': <Object>[]},
      {...value, 'artists': <Object>[]},
      {...value, 'works': <Object>[]},
      {...value, 'tracks': <Object>[]},
      {
        ...value,
        'playlists': [
          {'id': 'p', 'title': 'P', 'track_ids': 'track-a'},
        ],
      },
    ];
    for (final invalid in invalidDocuments) {
      await expectLater(store.save(invalid), throwsFormatException);
    }
    expect((await store.read())['revision'], 0);
  });

  test(
    'rights allocation may be unfinished but cannot exceed 100 percent',
    () async {
      final value = await catalog();
      Map<String, dynamic> allocated(num percentage) => {
        ...value,
        'works': [
          {
            'id': 'work-a',
            'title': 'Song',
            'shares': [
              {
                'holder_id': 'holder-a',
                'role': 'composer',
                'percentage': percentage,
              },
              {'holder_id': 'holder-a', 'role': 'publisher', 'percentage': 20},
            ],
          },
        ],
      };
      await store.save(allocated(40));
      await expectLater(store.save(allocated(90)), throwsFormatException);
      await expectLater(store.save(allocated(-1)), throwsFormatException);
      await expectLater(
        store.save(allocated(double.infinity)),
        throwsFormatException,
      );
      expect((await store.read())['revision'], 1);
    },
  );

  test(
    'future fields survive save and prior catalog snapshots remain available',
    () async {
      final value = {
        ...await catalog(),
        'vendor': {'unknown': true},
      };
      await store.save(value);
      final latest = await store.read();
      latest.remove('vendor');
      await store.save(latest, expectedRevision: 1);
      expect((await store.read())['vendor'], {'unknown': true});
      expect((await store.read())['artists'][0]['custom'], isTrue);
      final entries = await Directory(
        p.join(root.path, 'catalog'),
      ).list().toList();
      expect(
        entries.where((e) => e.path.endsWith('.previous.json')),
        hasLength(1),
      );
    },
  );

  test(
    'symlinked catalog directory is rejected',
    () async {
      final target = Directory(p.join(root.path, 'outside'));
      await target.create();
      await Link(p.join(root.path, 'catalog')).create(target.path);
      await expectLater(store.read(), throwsA(isA<FileSystemException>()));
      expect(await target.list().isEmpty, isTrue);
    },
    skip: Platform.isWindows
        ? 'Creating Windows symlinks requires elevated privileges'
        : false,
  );
}
