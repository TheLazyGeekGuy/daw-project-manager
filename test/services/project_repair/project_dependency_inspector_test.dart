import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/project_dependency_inspector.dart';

void main() {
  test('unsupported files fail closed', () {
    expect(
      () => ProjectDependencyInspector.inspectBytes('broken.cpr', Uint8List.fromList('RIFFxxxxWAVE'.codeUnits)),
      throwsFormatException,
    );
  });

  test('recognized but unimplemented format reports unknown, not empty dependencies', () {
    final result = ProjectDependencyInspector.inspectBytes(
      'session.dawproject',
      Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
    );
    expect(result.formatId, 'dawproject');
    expect(result.trackCount, isNull);
    expect(result.limitations.first, contains('not implemented'));
    expect(result.toJson()['plugin_loadability'], 'untested');
    expect(result.toJson()['original_modified'], isFalse);
  });
}
