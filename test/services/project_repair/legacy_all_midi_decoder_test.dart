import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/legacy_all_midi_decoder.dart';
import 'package:daw_project_manager/services/project_repair/midi_file_validator.dart';

import '../../helpers/legacy_all_fixture.dart';

void main() {
  test('MIDI channel running status survives a meta event', () {
    final body = [
      0,
      0x90,
      60,
      100,
      0,
      0xff,
      1,
      1,
      65,
      0,
      62,
      100,
      0,
      0xff,
      0x2f,
      0,
    ];
    final midi = Uint8List.fromList([
      ...'MThd'.codeUnits,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      1,
      224,
      ...'MTrk'.codeUnits,
      0,
      0,
      0,
      body.length,
      ...body,
    ]);
    expect(MidiFileValidator.inspect(midi).noteCount, 2);
  });
  for (final fixed in [false, true]) {
    test(
      '${fixed ? 'fixed' : 'compact'} records retain notes, channel and MIDI timing',
      () {
        final result = LegacyAllMidiDecoder.decode(
          legacyAllFixture(fixed: fixed),
          songName: 'Test',
        );
        final summary = MidiFileValidator.inspect(result.midi);
        expect(summary.format, 1);
        expect(summary.division, 480);
        expect(summary.trackCount, 2);
        expect(summary.noteCount, 1);
        expect(result.initialTempoMicroseconds, 500000);
        expect(result.tracks.single.name, 'Keys');
        expect(result.tracks.single.channel, 3);
        expect(result.tracks.single.layout, fixed ? 'fixed' : 'compact');
        final hex = result.midi
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        // 480 ticks to channel-three note on; 478 ticks to note off.
        expect(hex, contains('83 60 92 3c 64 83 5e 82 3c 00'));
        expect(hex, contains('ff 58 04 03 02 18 08')); // 3/4 time signature.
        expect(result.toJson()['native_daw_reopen_verified'], false);
      },
    );
    test(
      '${fixed ? 'fixed' : 'compact'} repeated parts retain arrangement offsets',
      () {
        final result = LegacyAllMidiDecoder.decode(
          legacyAllFixture(fixed: fixed, repeatedPart: true),
        );
        expect(result.noteCount, 2);
        expect(result.tracks, hasLength(1));
        expect(result.tracks.single.partCount, 2);
        final summary = MidiFileValidator.inspect(result.midi);
        expect(summary.noteCount, 2);
        final hex = result.midi
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        // First note ends at 958; repeated part note begins at 1440 => delta 482.
        expect(hex, contains('83 62 92 3c 64'));
      },
    );
  }
  test('rejects random data and truncated records instead of empty MIDI', () {
    expect(
      () => LegacyAllMidiDecoder.decode(Uint8List(1400)),
      throwsFormatException,
    );
    expect(
      () => LegacyAllMidiDecoder.decode(Uint8List(30)),
      throwsFormatException,
    );
    final bytes = legacyAllFixture();
    bytes[558] = 0xf0;
    expect(() => LegacyAllMidiDecoder.decode(bytes), throwsFormatException);
  });
  test('missing plausible tempo is explicitly marked defaulted', () {
    final bytes = legacyAllFixture();
    ByteData.sublistView(bytes).setUint32(0xa2, 0);
    final result = LegacyAllMidiDecoder.decode(bytes);
    expect(result.initialTempoMicroseconds, 750000);
    expect(result.tempoDefaulted, true);
  });
  test(
    'SMF validator rejects truncated chunks, invalid running status and no EOT',
    () {
      final valid = LegacyAllMidiDecoder.decode(legacyAllFixture()).midi;
      expect(
        () => MidiFileValidator.inspect(
          Uint8List.fromList(valid.sublist(0, valid.length - 1)),
        ),
        throwsFormatException,
      );
      final bad = Uint8List.fromList(valid);
      bad[bad.length - 2] = 0x51;
      expect(() => MidiFileValidator.inspect(bad), throwsFormatException);
    },
  );
}
