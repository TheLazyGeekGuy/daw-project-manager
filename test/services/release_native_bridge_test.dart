import 'dart:convert';

import 'package:daw_project_manager/services/release_native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _merge(
  Map<String, dynamic> workspace, {
  List<Map<String, dynamic>> tracks = const [],
  List<Map<String, dynamic>> assets = const [],
  String? description,
  String? releaseDate,
}) => ReleaseNativeBridge.mergeWorkspace(
  workspace: workspace,
  nativeTracks: tracks,
  nativeAssets: assets,
  title: 'Current release',
  description: description,
  releaseDate: releaseDate,
);

List<Map> _rows(Map<String, dynamic> workspace, String key) =>
    (workspace[key] as List).cast<Map>();

void main() {
  test('refreshes native summary while preserving independent metadata', () {
    final workspace = <String, dynamic>{
      'title': 'Old title',
      'description': 'Old description',
      'release_date': '2026-01-01',
      'collection_type': 'ep',
      'custom': {
        'nested': ['original'],
      },
    };
    final before = jsonEncode(workspace);
    final merged = _merge(workspace);
    expect(merged['title'], 'Current release');
    expect(merged.containsKey('description'), isTrue);
    expect(merged['description'], isNull);
    expect(merged.containsKey('release_date'), isTrue);
    expect(merged['release_date'], isNull);
    expect(merged['collection_type'], 'ep');
    (merged['custom']['nested'] as List).add('new');
    expect(jsonEncode(workspace), before);

    final replaced = _merge(
      workspace,
      description: 'Current description',
      releaseDate: '2026-12-15',
    );
    expect(replaced['description'], 'Current description');
    expect(replaced['release_date'], '2026-12-15');
  });

  test(
    'infers legacy links, reorders slots and retains custom track metadata',
    () {
      final workspace = <String, dynamic>{
        'tracks': [
          {
            'id': 'project-1',
            'title': 'Custom first title',
            'isrc': 'GBABC2600001',
          },
          {'id': 'manual-1', 'title': 'Interlude'},
          {
            'id': 'recording-2',
            'project_id': 'project-2',
            'title': 'Custom second title',
            'credits': [
              {'artist_id': 'artist-1', 'role': 'composer'},
            ],
          },
          {'id': 'removed', 'project_id': 'no-longer-linked', 'title': 'Old'},
          {'id': 'manual-2', 'title': 'Outro'},
        ],
      };
      final native = <Map<String, dynamic>>[
        {'id': 'project-2', 'title': 'Project two'},
        {'id': 'project-1', 'title': 'Project one'},
        {'id': 'project-3', 'title': 'New project'},
      ];
      final before = jsonEncode([workspace, native]);
      final merged = _merge(workspace, tracks: native);
      final tracks = _rows(merged, 'tracks');
      expect(tracks.map((row) => row['id']), [
        'recording-2',
        'manual-1',
        'project-1',
        'manual-2',
        'project-3',
      ]);
      expect(tracks.first['title'], 'Custom second title');
      expect(tracks.first['credits'], hasLength(1));
      expect(tracks[2]['project_id'], 'project-1');
      expect(tracks[2]['isrc'], 'GBABC2600001');
      expect(tracks.last['project_id'], 'project-3');
      (tracks.first['credits'] as List).clear();
      expect(jsonEncode([workspace, native]), before);
    },
  );

  test(
    'preserves native order with new leading links and multiple recordings',
    () {
      final merged = _merge(
        {
          'tracks': [
            {'id': 'take-a', 'project_id': 'existing', 'title': 'Take A'},
            {'id': 'manual', 'title': 'Manual'},
            {'id': 'take-b', 'project_id': 'existing', 'title': 'Take B'},
          ],
        },
        tracks: [
          {'id': 'new', 'title': 'New'},
          {'id': 'existing', 'title': 'Project'},
        ],
      );
      final tracks = _rows(merged, 'tracks');
      expect(tracks.map((row) => row['id']), [
        'new',
        'manual',
        'take-a',
        'take-b',
      ]);
      expect(
        tracks
            .where((row) => row['project_id'] != null)
            .map((row) => row['project_id']),
        ['new', 'existing', 'existing'],
      );
    },
  );

  test(
    'only removes explicit project links absent from the native release',
    () {
      final merged = _merge({
        'tracks': [
          {'id': 'manual', 'title': 'Unlinked'},
          {'id': 'old-legacy-id', 'title': 'No reliable link evidence'},
          {'id': 'linked', 'project_id': 'gone', 'title': 'Removed natively'},
        ],
      });
      expect(_rows(merged, 'tracks').map((row) => row['id']), [
        'manual',
        'old-legacy-id',
      ]);
    },
  );

  test(
    'allocates a distinct new row ID without renaming existing recordings',
    () {
      final workspace = <String, dynamic>{
        'tracks': [
          {
            'id': 'project-2',
            'project_id': 'project-1',
            'title': 'Existing ID',
          },
          {'id': 'project-2-native', 'title': 'Manual'},
        ],
      };
      final native = <Map<String, dynamic>>[
        {'id': 'project-1', 'title': 'One'},
        {'id': 'project-2', 'title': 'Two'},
      ];
      final merged = _merge(workspace, tracks: native);
      final ids = _rows(merged, 'tracks').map((row) => row['id']).toList();
      expect(ids, ['project-2', 'project-2-native', 'project-2-native-2']);
      expect(_merge(merged, tracks: native), merged);
    },
  );

  test(
    'refreshes native asset paths and removes all obsolete integrity evidence',
    () {
      final workspace = <String, dynamic>{
        'assets': [
          {
            'id': 'file-1',
            'title': 'Release master',
            'role': 'master',
            'path': '/old/master.wav',
            'validation': 'verified',
            'sha256': 'old-hash',
            'bytes': 4,
            'verified_at': 'old-time',
            'checked_at': 'old-time',
            'resolved_path': '/old/master.wav',
            'observed_sha256': 'old-observation',
            'observed_bytes': 5,
            'verification_error': 'old-error',
            'notes': {'text': 'Preserve notes'},
          },
        ],
      };
      final native = <Map<String, dynamic>>[
        {
          'id': 'file-1',
          'title': 'master.wav',
          'role': 'document',
          'path': '/new/master.wav',
        },
      ];
      final before = jsonEncode([workspace, native]);
      final merged = _merge(workspace, assets: native);
      final asset = _rows(merged, 'assets').single;
      expect(asset['path'], '/new/master.wav');
      expect(asset['title'], 'Release master');
      expect(asset['role'], 'master');
      expect(asset['native_release_asset'], isTrue);
      expect(asset['validation'], 'unverified');
      for (final key in [
        'sha256',
        'bytes',
        'verified_at',
        'checked_at',
        'resolved_path',
        'observed_sha256',
        'observed_bytes',
        'verification_error',
      ]) {
        expect(asset.containsKey(key), isFalse, reason: key);
      }
      asset['notes']['text'] = 'Changed result only';
      expect(jsonEncode([workspace, native]), before);
    },
  );

  test(
    'keeps unchanged asset verification and removes only absent marked files',
    () {
      final merged = _merge(
        {
          'assets': [
            {'id': 'manual', 'path': '/manual.wav', 'validation': 'unverified'},
            {'id': 'removed', 'path': '/old.wav', 'native_release_asset': true},
            {
              'id': 'matching',
              'path': '/same.wav',
              'validation': 'verified',
              'sha256': 'stored',
            },
          ],
        },
        assets: [
          {'id': 'matching', 'path': '/same.wav', 'validation': 'unverified'},
          {
            'id': 'added',
            'path': '/new.wav',
            'validation': 'verified',
            'sha256': 'not-observed',
          },
        ],
      );
      final assets = _rows(merged, 'assets');
      expect(assets.map((row) => row['id']), ['manual', 'matching', 'added']);
      expect(assets[0].containsKey('native_release_asset'), isFalse);
      expect(assets[1]['validation'], 'verified');
      expect(assets[1]['sha256'], 'stored');
      expect(assets[1]['native_release_asset'], isTrue);
      expect(assets[2]['validation'], 'unverified');
      expect(assets[2].containsKey('sha256'), isFalse);
      expect(assets[2]['native_release_asset'], isTrue);
    },
  );

  test('rejects ambiguous native identities without modifying caller data', () {
    final workspace = <String, dynamic>{
      'title': 'Retain',
      'tracks': [],
      'assets': [],
    };
    final before = jsonEncode(workspace);
    expect(
      () => _merge(
        workspace,
        tracks: [
          {'id': 'a', 'project_id': 'same'},
          {'id': 'b', 'project_id': 'same'},
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => _merge(
        workspace,
        assets: [
          {'id': 'same', 'path': '/one'},
          {'id': 'same', 'path': '/two'},
        ],
      ),
      throwsFormatException,
    );
    expect(jsonEncode(workspace), before);
  });
}
