import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/daw_parsers/embedded_audio_paths.dart';

Uint8List _bytes(List<int> parts) => Uint8List.fromList(parts);

List<int> _ascii(String s) => latin1.encode(s);

List<int> _utf16(String s) => [
      for (final unit in s.codeUnits) ...[unit & 0xFF, unit >> 8],
    ];

void main() {
  group('findEmbeddedAudioPaths', () {
    test('finds an ASCII Windows path between binary bytes', () {
      final data = _bytes([
        0, 1, 2, 0xFF,
        ..._ascii(r'D:\Samples\Kicks\kick 01.wav'),
        0, 0, 7,
      ]);
      expect(findEmbeddedAudioPaths(data), [r'D:\Samples\Kicks\kick 01.wav']);
    });

    test('drops the length byte a printable prefix leaves in front', () {
      // Cubase/FL length-prefixed strings: "%" is a length of 37.
      final data = _bytes([0, ..._ascii(r'%C:\Audio\snare.aiff'), 0]);
      expect(findEmbeddedAudioPaths(data), [r'C:\Audio\snare.aiff']);
    });

    test('finds a UTF-16LE path with non-ASCII characters', () {
      const path = r'C:\Música\Gataka – Life kick.wav';
      final data = _bytes([9, 9, ..._utf16(path), 0, 0]);
      expect(findEmbeddedAudioPaths(data), [path]);
    });

    test('finds POSIX paths under a user root, and UNC shares', () {
      final data = _bytes([
        ..._ascii('xx/Users/me/Library/Loops/hat.flac'),
        0,
        ..._ascii(r'\\nas\samples\fx\riser.mp3'),
        0,
      ]);
      expect(findEmbeddedAudioPaths(data), [
        '/Users/me/Library/Loops/hat.flac',
        r'\\nas\samples\fx\riser.mp3',
      ]);
    });

    test('ignores relative paths and names without a folder', () {
      final data = _bytes([
        ..._ascii(r'Audio\kick.wav'),
        0,
        ..._ascii('kick.wav'),
        0,
      ]);
      expect(findEmbeddedAudioPaths(data), isEmpty);
    });

    test("ignores Ableton's analysis files and longer extensions", () {
      final data = _bytes([
        ..._ascii(r'C:\Samples\kick.wav.asd'),
        0,
        ..._ascii(r'C:\Samples\kick.wavex'),
        0,
      ]);
      expect(findEmbeddedAudioPaths(data), isEmpty);
    });

    test('ignores files that are not audio', () {
      final data = _bytes([
        ..._ascii(r'C:\Program Files\VSTPlugins\Serum.dll'),
        0,
        ..._ascii(r'C:\Presets\lead.fxp'),
        0,
      ]);
      expect(findEmbeddedAudioPaths(data), isEmpty);
    });

    test('matches the extension case-insensitively and lists a path once', () {
      final data = _bytes([
        ..._ascii(r'E:\Crash\Crash 02.WAV'),
        0,
        ..._ascii(r'E:\Crash\Crash 02.WAV'),
        0,
      ]);
      expect(findEmbeddedAudioPaths(data), [r'E:\Crash\Crash 02.WAV']);
    });

    test('prefers .aiff over .aif', () {
      final data = _bytes([..._ascii(r'C:\a\pad.aiff'), 0]);
      expect(findEmbeddedAudioPaths(data), [r'C:\a\pad.aiff']);
    });
  });
}
