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
    expect(validator.validate(data).any((e) => e.contains('Invalid ISRC')), true);
  });
  test('reports next manual release step without inventing confirmation', () {
    final data = {
      'schema_version': 1,
      'collection_type': 'single',
      'tracks': [{'id': 'a', 'isrc': 'FRABC1234567'}],
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
      'rights_filings': [{'organization': 42, 'status': 'draft'}],
      'distribution': [{'distributor': 'Example', 'status': 1}],
      'communications': [{'platform': null, 'status': 'planned'}],
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
        {'organization': 'SACEM', 'status': 'automatically_approved'}
      ],
      'distribution': [
        {'distributor': 'Example', 'status': 'live_on_every_platform'}
      ],
      'communications': [
        {'platform': 'Video platform', 'status': 'published_everywhere'}
      ],
    };
    final errors = validator.validate(data);
    expect(errors, contains('Invalid rights filing'));
    expect(errors, contains('Invalid distribution entry'));
    expect(errors, contains('Invalid communication entry'));
  });

}
