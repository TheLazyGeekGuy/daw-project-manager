import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_record_editor.dart';

void main() {
  final initial = <String, dynamic>{
    'schema_version': 1,
    'rights_filings': <Map<String, dynamic>>[],
    'distribution': <Map<String, dynamic>>[],
    'communications': <Map<String, dynamic>>[],
  };
  test('creates multiple independent rights entries', () {
    final first = ReleaseRecordEditor.update(initial, 'rights_filings', null,
        {'organization': 'SACEM', 'status': 'draft'});
    final second = ReleaseRecordEditor.update(first, 'rights_filings', null,
        {'organization': 'PRS', 'status': 'submitted'});
    expect((second['rights_filings'] as List), hasLength(2));
    expect((initial['rights_filings'] as List), isEmpty);
  });
  test('editing preserves opaque fields and other entries', () {
    final input = {
      ...initial,
      'distribution': [
        {'distributor': 'A', 'status': 'draft', 'external_id': 'keep'},
        {'distributor': 'B', 'status': 'live'}
      ]
    };
    final updated = ReleaseRecordEditor.update(input, 'distribution', 0,
        {'distributor': 'A', 'status': 'submitted'});
    final entries = updated['distribution'] as List;
    expect(entries[0]['external_id'], 'keep');
    expect(entries[1]['distributor'], 'B');
    expect((input['distribution'] as List)[0]['status'], 'draft');
  });
  test('delete affects only selected entry', () {
    final data = {...initial, 'communications': [
      {'platform': 'YouTube', 'status': 'planned'},
      {'platform': 'Instagram', 'status': 'ready'}
    ]};
    final result = ReleaseRecordEditor.remove(data, 'communications', 0);
    expect((result['communications'] as List).single['platform'], 'Instagram');
  });
  test('rejects invalid section or incomplete entries', () {
    expect(() => ReleaseRecordEditor.remove(initial, 'bad', 0), throwsArgumentError);
    expect(() => ReleaseRecordEditor.update(initial, 'distribution', null,
      {'distributor': '', 'status': 'draft'}), throwsFormatException);
  });
}
