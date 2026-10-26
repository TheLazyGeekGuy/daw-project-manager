import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_workflow_validator.dart';

void main() {
  const validator = ReleaseWorkflowValidator();
  test('requires coherent track identity, ISRC and fields', () {
    final data = {
      'schema_version': 1,
      'collection_type': 'album',
      'tracks': [
        {'id': 'a', 'isrc': 'FRABC1234567'},
        {'id': 'a', 'isrc': 'broken'},
      ],
      'rights_filings': <Object>[],
      'distribution': <Object>[],
      'communications': <Object>[],
    };
    expect(validator.validate(data), contains('Duplicate track ID: a'));
    expect(
      validator.validate(data).any((e) => e.contains('Invalid ISRC')),
      true,
    );
  });
  test('reports next manual release step without inventing confirmation', () {
    final data = {
      'schema_version': 1,
      'collection_type': 'single',
      'tracks': [
        {'id': 'a', 'isrc': 'FRABC1234567'},
      ],
      'rights_filings': <Object>[],
      'distribution': <Object>[],
      'communications': <Object>[],
    };
    expect(validator.nextSuggestedStep(data), 'Prepare distributor delivery');
  });
  test('rejects invalid nested rights, distributor and promotion entries', () {
    final data = {
      'schema_version': 1,
      'collection_type': 'album',
      'tracks': <Object>[],
      'rights_filings': [
        {'organization': 42, 'status': 'draft'},
      ],
      'distribution': [
        {'distributor': 'Example', 'status': 1},
      ],
      'communications': [
        {'platform': null, 'status': 'planned'},
      ],
    };
    final errors = validator.validate(data);
    expect(errors, contains('Invalid rights filing'));
    expect(errors, contains('Invalid distribution entry'));
    expect(errors, contains('Invalid communication entry'));
  });

  test('refuses unknown lifecycle statuses without claiming publication', () {
    final data = {
      'schema_version': 1,
      'collection_type': 'single',
      'tracks': <Object>[],
      'rights_filings': [
        {'organization': 'SACEM', 'status': 'automatically_approved'},
      ],
      'distribution': [
        {'distributor': 'Example', 'status': 'live_on_every_platform'},
      ],
      'communications': [
        {'platform': 'Video platform', 'status': 'published_everywhere'},
      ],
    };
    final errors = validator.validate(data);
    expect(errors, contains('Invalid rights filing'));
    expect(errors, contains('Invalid distribution entry'));
    expect(errors, contains('Invalid communication entry'));
  });

  Map<String, dynamic> modern() => {
    'schema_version': 2,
    'release_id': 'release',
    'collection_type': 'album',
    'artist_ids': <String>[],
    'tracks': <Map>[],
    'rights_filings': <Map>[],
    'distribution': <Map>[],
    'communications': <Map>[],
    'assets': <Map>[],
    'campaigns': <Map>[],
    'tasks': <Map>[],
  };
  Map<String, dynamic> catalog() => {
    'schema_version': 1,
    'artists': [
      {
        'id': 'artist',
        'name': 'Artist',
        'aliases': ['Alias'],
        'roles': ['composer'],
      },
    ],
    'holders': [
      {'id': 'holder', 'name': 'Holder'},
    ],
    'works': [
      {
        'id': 'work',
        'title': 'Composition',
        'shares': [
          {'holder_id': 'holder', 'role': 'composer', 'percentage': 100.0},
        ],
      },
    ],
    'tracks': [
      {
        'id': 'recording',
        'title': 'Recording',
        'work_id': 'work',
        'credits': [
          {'artist_id': 'artist', 'role': 'performer'},
        ],
      },
    ],
    'playlists': [
      {
        'id': 'list',
        'title': 'Selection',
        'track_ids': ['recording'],
      },
    ],
  };

  test('draft schema2 allows incomplete optional publication metadata', () {
    final data = modern()
      ..['tracks'] = [
        {'id': 'track', 'title': 'Unfinished recording'},
      ];
    expect(validator.validate(data), isEmpty);
    expect(validator.validateCatalog(catalog()), isEmpty);
  });

  test(
    'catalog references protect artists, rights holders and playlist tracks',
    () {
      final data = catalog();
      (data['artists'] as List).clear();
      (data['holders'] as List).clear();
      (data['tracks'] as List).clear();
      final errors = validator.validateCatalog(data);
      expect(errors, contains('Unknown rights holder: holder'));
      expect(errors, contains('Unknown playlist track: recording'));
      final workspace = modern()..['artist_ids'] = ['artist'];
      expect(
        validator.validate(workspace, catalog: data),
        contains('Unknown artist: artist'),
      );
    },
  );

  test('schema1 imported artist IDs remain unresolved until migrated', () {
    final data = modern()..['schema_version'] = 1;
    data['artist_ids'] = ['unresolved'];
    expect(validator.validate(data, catalog: catalog()), isEmpty);
  });

  test('non-finite and incomplete rights splits fail validation', () {
    final data = catalog();
    final shares = ((data['works'] as List).first as Map)['shares'] as List;
    (shares.first as Map)['percentage'] = double.nan;
    expect(
      validator.validateCatalog(data),
      contains('Invalid rights share percentage'),
    );
    (shares.first as Map)['percentage'] = 75;
    expect(
      validator
          .validateCatalog(data)
          .any((error) => error.startsWith('Shares must total 100%')),
      true,
    );
  });

  test('UPC and EAN check digits are enforced without claiming allocation', () {
    expect(ReleaseWorkflowValidator.validBarcode('036000291452'), true);
    expect(ReleaseWorkflowValidator.validBarcode('4006381333931'), true);
    expect(ReleaseWorkflowValidator.validBarcode('036000291453'), false);
    expect(ReleaseWorkflowValidator.validBarcode('4006381333932'), false);
    final data = modern()
      ..['distribution'] = [
        {
          'id': 'delivery',
          'distributor': 'Example',
          'status': 'draft',
          'upc': '036000291453',
        },
      ];
    expect(validator.validate(data), contains('Invalid UPC/EAN check digit'));
  });

  test(
    'publication and scheduled states require dates and safe URL syntax',
    () {
      final data = modern()
        ..['communications'] = [
          {
            'id': 'published',
            'title': 'Published',
            'platform': 'Social',
            'status': 'published',
            'url': 'javascript:alert(1)',
          },
          {
            'id': 'scheduled',
            'title': 'Scheduled',
            'platform': 'Social',
            'status': 'scheduled',
          },
        ];
      final errors = validator.validate(data);
      expect(
        errors,
        contains('Published communication requires a publication timestamp'),
      );
      expect(
        errors,
        contains('Scheduled communication requires a scheduled timestamp'),
      );
      expect(errors, contains('Publication requires an HTTP(S) URL'));
      expect(
        ReleaseWorkflowValidator.validUrl('https://music.example/track?a=b'),
        true,
      );
      expect(
        ReleaseWorkflowValidator.validUrl('https://user:secret@music.example/'),
        false,
      );
    },
  );

  test('invalid calendar dates are not normalized into different days', () {
    expect(ReleaseWorkflowValidator.parseDate('2026-02-30'), isNull);
    expect(ReleaseWorkflowValidator.parseDate('2026-13-01'), isNull);
    expect(ReleaseWorkflowValidator.parseDate('2026-10-26T25:00:00Z'), isNull);
    expect(ReleaseWorkflowValidator.parseDate('2028-02-29'), isNotNull);
    expect(
      ReleaseWorkflowValidator.parseDate('2026-10-26T08:00:00+02:00'),
      isNotNull,
    );
  });

  test('removing referenced tracks/assets/campaigns is rejected', () {
    final data = modern()
      ..['communications'] = [
        {
          'id': 'post',
          'title': 'Post',
          'platform': 'Video',
          'status': 'draft',
          'track_id': 'deleted',
          'campaign_id': 'gone',
          'asset_ids': ['missing'],
        },
      ]
      ..['rights_filings'] = [
        {
          'id': 'filing',
          'organization': 'Example',
          'status': 'draft',
          'evidence_asset_ids': ['proof'],
        },
      ];
    final errors = validator.validate(data);
    expect(errors, contains('Unknown promotion track: deleted'));
    expect(errors, contains('Unknown campaign: gone'));
    expect(errors, contains('Unknown promotion asset: missing'));
    expect(errors, contains('Unknown evidence asset: proof'));
  });

  test('cycles in task dependencies and asset lineage are rejected', () {
    final data = modern()
      ..['tasks'] = [
        {
          'id': 'a',
          'title': 'A',
          'status': 'todo',
          'depends_on': ['b'],
        },
        {
          'id': 'b',
          'title': 'B',
          'status': 'todo',
          'depends_on': ['a'],
        },
      ]
      ..['assets'] = [
        {
          'id': 'one',
          'path': '/one.wav',
          'role': 'mix',
          'parent_asset_id': 'two',
        },
        {
          'id': 'two',
          'path': '/two.wav',
          'role': 'mix',
          'parent_asset_id': 'one',
        },
      ];
    final errors = validator.validate(data);
    expect(errors, contains('Task dependencies contain a cycle'));
    expect(errors, contains('Asset lineage contains a cycle'));
  });

  test('verified assets require actual integrity evidence fields', () {
    final data = modern()
      ..['assets'] = [
        {
          'id': 'master',
          'role': 'master',
          'path': '/master.wav',
          'validation': 'verified',
        },
      ];
    expect(
      validator.validate(data),
      contains(
        'Verified asset requires a digest, byte length and verification timestamp',
      ),
    );
  });

  test(
    'nested malformed objects return errors instead of type-cast failures',
    () {
      final data = modern()
        ..['assets'] = [
          3,
          {
            'id': false,
            'role': [],
            'parent_asset_id': 42,
            'sha256': false,
            'bytes': 'big',
          },
        ]
        ..['communications'] = [
          {
            'id': 'x',
            'platform': 1,
            'status': true,
            'asset_ids': [3],
          },
        ]
        ..['tasks'] = [
          {
            'id': 't',
            'title': 'Task',
            'status': 'todo',
            'depends_on': {'bad': true},
          },
        ];
      expect(validator.validate(data), isNotEmpty);
      expect(
        validator.validateCatalog({
          'schema_version': 1,
          'works': [
            {
              'id': 'w',
              'title': 'Work',
              'shares': [
                1,
                {'percentage': 'all', 'holder_id': null},
              ],
            },
          ],
        }),
        isNotEmpty,
      );
    },
  );
}
