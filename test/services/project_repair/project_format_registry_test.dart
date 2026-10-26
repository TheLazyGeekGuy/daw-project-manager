import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/project_format_registry.dart';

void main() {
  test('recognizes common formats regardless of filename casing', () {
    expect(ProjectFormatRegistry.byExtension('Song.CPR')?.id, 'cubase');
    expect(ProjectFormatRegistry.byExtension('song.rpp')?.id, 'reaper');
    expect(ProjectFormatRegistry.byExtension('session.dawproject')?.id, 'dawproject');
    expect(ProjectFormatRegistry.byExtension('unknown.bin'), isNull);
  });

  test('rejects fake Cubase RIFF and truncated headers', () {
    expect(ProjectFormatRegistry.detect('song.cpr', Uint8List.fromList('RIFFxxxxWAVE'.codeUnits)), isNull);
    expect(ProjectFormatRegistry.detect('song.cpr', Uint8List(5)), isNull);
    expect(ProjectFormatRegistry.detect('song.cpr', Uint8List.fromList('RIFFxxxxNUND'.codeUnits))?.id, 'cubase');
  });

  test('detects Ableton gzip header but not plain XML', () {
    expect(ProjectFormatRegistry.detect('song.als', Uint8List.fromList([0x1f, 0x8b]))?.id, 'ableton');
    expect(ProjectFormatRegistry.detect('song.als', Uint8List.fromList('<Ableton>'.codeUnits)), isNull);
  });

  test('DAWproject ZIP must begin with a local file header', () {
    expect(
      ProjectFormatRegistry.detect(
        'album.dawproject', Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
      )?.id,
      'dawproject',
    );
    expect(
      ProjectFormatRegistry.detect(
        'album.dawproject', Uint8List.fromList('not a ZIP'.codeUnits),
      ),
      isNull,
    );
  });

  test('native writing is not marked verified for any format', () {
    expect(ProjectFormatRegistry.formats.every((f) => !f.nativeWritingVerified), isTrue);
  });
}
