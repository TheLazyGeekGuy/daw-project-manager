import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_track_editor.dart';

void main() {
  final data = <String, dynamic>{
    'tracks': [
      {'id': 'id-a', 'title': 'Song A', 'metadata': 'preserve'},
      {'id': 'id-b', 'title': 'Song B'},
    ],
  };
  test('preserves existing metadata when editing by stable ID', () {
    final result = ReleaseTrackEditor.upsert(
      data, {'id': 'id-a', 'title': 'New title'}, index: 0,
    );
    expect((result['tracks'] as List)[0]['metadata'], 'preserve');
    expect((data['tracks'] as List)[0]['title'], 'Song A');
  });
  test('preserves ordering and source immutability', () {
    final moved = ReleaseTrackEditor.move(data, 1, 0);
    expect((moved['tracks'] as List)[0]['id'], 'id-b');
    expect((data['tracks'] as List)[0]['id'], 'id-a');
  });
  test('rejects duplicate identities', () {
    expect(
      () => ReleaseTrackEditor.upsert(data, {'id': 'id-a'}, index: 1),
      throwsFormatException,
    );
  });
  test('removal does not rewrite the source list', () {
    final next = ReleaseTrackEditor.remove(data, 0);
    expect(next['tracks'], hasLength(1));
    expect(data['tracks'], hasLength(2));
  });
}
