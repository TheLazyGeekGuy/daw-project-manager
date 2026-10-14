import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/utils/audio_file_info.dart';

List<int> _le32(int v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24];
List<int> _le16(int v) => [v & 255, v >> 8];
List<int> _be32(int v) => [v >> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255];

/// A 16-bit stereo 44.1 kHz WAV with [dataBytes] of audio, a LIST chunk of
/// odd size before it (padded, as RIFF requires), and [declared] as the data
/// chunk's size when given.
List<int> _wav(int dataBytes, {int? declared}) {
  final fmt = [
    ..._le16(1), ..._le16(2), ..._le32(44100), ..._le32(176400),
    ..._le16(4), ..._le16(16),
  ];
  final list = ascii.encode('INFOabc'); // 7 bytes: odd
  final body = [
    ...ascii.encode('WAVE'),
    ...ascii.encode('fmt '), ..._le32(fmt.length), ...fmt,
    ...ascii.encode('LIST'), ..._le32(list.length), ...list, 0,
    ...ascii.encode('data'), ..._le32(declared ?? dataBytes),
    ...List.filled(dataBytes, 0),
  ];
  return [...ascii.encode('RIFF'), ..._le32(body.length), ...body];
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('audio_info_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  test('WAV: data bytes over the byte rate, past other chunks', () async {
    final path = await write('a.wav', _wav(17640)); // 0.1 s
    expect(await readAudioDuration(path), const Duration(milliseconds: 100));
  });

  test('WAV with an unfinished header: what is there counts', () async {
    final path = await write('b.wav', _wav(35280, declared: 0)); // 0.2 s
    expect(await readAudioDuration(path), const Duration(milliseconds: 200));
  });

  test('AIFF: frames over the 80-bit extended sample rate', () async {
    final comm = [
      0, 2, // channels (big-endian u16)
      ..._be32(22050), // frames
      0, 16, // bits
      0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0, // 44100.0
    ];
    final body = [
      ...ascii.encode('AIFF'),
      ...ascii.encode('COMM'), ..._be32(comm.length), ...comm,
    ];
    final path = await write('c.aiff',
        [...ascii.encode('FORM'), ..._be32(body.length), ...body]);
    expect(await readAudioDuration(path), const Duration(milliseconds: 500));
  });

  test('FLAC: total samples over the rate in STREAMINFO', () async {
    final info = Uint8List(34);
    // 48000 Hz, 2 channels, 16 bits, 24000 samples.
    const rate = 48000, total = 24000;
    info[10] = (rate >> 12) & 0xFF;
    info[11] = (rate >> 4) & 0xFF;
    info[12] = ((rate & 0x0F) << 4) | (1 << 1) | 0; // channels-1 = 1
    info[13] = (15 << 4) | 0; // bits-1 = 15, total samples high nibble 0
    info[14] = (total >> 24) & 0xFF;
    info[15] = (total >> 16) & 0xFF;
    info[16] = (total >> 8) & 0xFF;
    info[17] = total & 0xFF;
    final path = await write('d.flac', [
      ...ascii.encode('fLaC'),
      0x80, 0, 0, 34, // last block, STREAMINFO, 34 bytes
      ...info,
    ]);
    expect(await readAudioDuration(path), const Duration(milliseconds: 500));
  });

  test('null for what it cannot read', () async {
    expect(await readAudioDuration(await write('e.mp3', [0xFF, 0xFB, 1, 2])),
        isNull);
    expect(await readAudioDuration(await write('empty.wav', [])), isNull);
    expect(await readAudioDuration(p.join(dir.path, 'missing.wav')), isNull);
  });
}
