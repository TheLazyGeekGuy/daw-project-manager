import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/midi/midi_file_reader.dart';
import 'package:daw_project_manager/services/project_repair/native_legacy_all_reader.dart';
import 'package:daw_project_manager/services/project_repair/native_legacy_all_midi_encoder.dart';
import 'package:daw_project_manager/services/project_repair/native_legacy_all_conversion.dart';
import 'package:daw_project_manager/services/project_repair/all_to_midi_bridge.dart';

/// Synthetic .ALL layouts derived from the publicly documented MIT
/// AllToMidi 1.0 heuristics. They contain no redistributed Steinberg data.
Uint8List legacyAllFixture({bool fixed = false}) {
  final file = Uint8List(1420);

  void u16(int pos, int number) {
    file[pos] = (number >> 8) & 255;
    file[pos + 1] = number & 255;
  }

  void u24(int pos, int number) {
    file[pos] = (number >> 16) & 255;
    file[pos + 1] = (number >> 8) & 255;
    file[pos + 2] = number & 255;
  }

  void definition(int pos, String name, int record, int track,
      {int startTick = 0}) {
    file[pos - 8] = 0x99;
    file[pos - 10] = 0;
    file[pos - 9] = 0;
    u16(pos - 18, record);
    u16(pos - 16, track - 1);
    file[pos - 5] = 0;
    u24(pos - 33, startTick);
    for (var i = 0; i < name.length; i++) {
      file[pos + i] = name.codeUnitAt(i);
    }
    file[pos + 15] = 0;
  }

  definition(240, 'Piano', 0, 1);
  definition(340, 'Bass', 1, 2);
  definition(600, 'Piano', 2, 1, startTick: fixed ? 32 : 0);
  if (!fixed) {
    definition(850, 'Piano', 3, 1, startTick: 160);

    void note(int pos, int pitch, int rawTick, int duration) {
      final at = pos + 42;
      file[at] = pitch;
      u16(at + 2, rawTick);
      file[at + 4] = 0x90;
      file[at + 5] = 100;
      u16(at + 8, duration);
      file.setRange(at + 12, at + 16, [0, 255, 255, 255]);
    }

    note(600, 60, 16, 80);
    note(850, 64, 32, 64);
  } else {
    final at = 600 + 139;
    u24(at, 256);
    file[at + 3] = 0x90;
    file[at + 4] = 60;
    file[at + 5] = 110;
    u24(at + 8, 320);
    file.setRange(at + 16, at + 19, [255, 255, 255]);
  }

  // 120 BPM, expressed in thousandths of BPM at Cubase's observed offset.
  file.setRange(0xa2, 0xa6, [0, 1, 0xd4, 0xc0]);
  file.setRange(104, 112, [0, 0, 0, 0, 2, 0, 4, 4]);
  file.setRange(112, 116, [0x7f, 0xff, 0xff, 0xff]);
  return file;
}

void main() {
  test('native compact ALL reader merges repeated parts by track', () {
    final song = const NativeLegacyAllReader().read(legacyAllFixture());
    expect(song.tracks, hasLength(1));
    expect(song.tracks.single.name, 'Piano');
    expect(song.tracks.single.partCount, 2);
    expect(song.noteCount, 2);
    expect(song.tracks.single.events.first.tick, 20);
    expect(song.tracks.single.events[1].tick, 240);
    expect(song.microsecondsPerQuarter, 500000);
    expect(song.signatures.single.numerator, 4);
    expect(song.toJson()['vst_state_preserved'], false);
  });

  test('native fixed layout is recognized with correct note scaling', () {
    final song = const NativeLegacyAllReader()
        .read(legacyAllFixture(fixed: true));
    expect(song.tracks.single.layout, 'fixed');
    expect(song.tracks.single.noteCount, 1);
    expect(song.tracks.single.events.single.duration, greaterThan(0));
  });

  test('export produces type 1 MIDI readable by existing DPM reader', () {
    final song = const NativeLegacyAllReader().read(legacyAllFixture());
    final bytes = const NativeLegacyAllMidiEncoder().encode(
      song,
      songName: 'Old Song',
    );
    final envelope = AllToMidiOutputProbe.inspect(bytes);
    expect(envelope.ppq, 480);
    expect(envelope.tracks, 2); // conductor + recovered Piano
    expect(envelope.notes, 2);
    final result = decodeMidiFileTracks(bytes);
    expect(result, isNotNull);
    expect(result!.tracks.last.name, 'Piano');
    expect(result.tracks.last.notes.length, 2);
    expect(result.bpm, closeTo(120, 0.01));
  });

  test('fails closed for unfamiliar ALL variants', () {
    expect(
      () => const NativeLegacyAllReader().read(Uint8List(500)),
      throwsFormatException,
    );
    expect(
      () => const NativeLegacyAllReader().read(Uint8List(3)),
      throwsFormatException,
    );
  });

  test('native conversion creates verified backup and separate MIDI', () async {
    final directory = await Directory.systemTemp.createTemp('dpm-native-all-');
    try {
      final original = File(directory.path + '/song.ALL');
      final content = legacyAllFixture();
      await original.writeAsBytes(content);
      final result = await const NativeLegacyAllConversion().convert(
        original: original,
      );
      expect(result.trackCount, 1);
      expect(result.noteCount, 2);
      expect(result.outputPath, contains('.project-repair-exports'));
      expect(await original.readAsBytes(), content);
      expect(await File(result.backupPath).readAsBytes(), content);
      expect(
        AllToMidiOutputProbe.inspect(
          await File(result.outputPath).readAsBytes(),
        ).notes,
        2,
      );
      expect(await File(result.reportPath).readAsString(),
          contains('native_midi_generated_unverified'));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('native conversion rejects ARR without mutating it', () async {
    final directory = await Directory.systemTemp.createTemp('dpm-arr-native-');
    try {
      final original = File(directory.path + '/arrangement.ARR');
      await original.writeAsBytes(legacyAllFixture());
      await expectLater(
        const NativeLegacyAllConversion().convert(original: original),
        throwsFormatException,
      );
      expect(await original.readAsBytes(), legacyAllFixture());
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
