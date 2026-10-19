import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/midi/input/midi_input_message.dart';

MidiInputMessage on(int pitch, int velocity, {int channel = 0}) =>
    MidiInputMessage(
        kind: MidiInputKind.noteOn,
        channel: channel,
        data1: pitch,
        data2: velocity);

MidiInputMessage off(int pitch, [int velocity = 0]) => MidiInputMessage(
    kind: MidiInputKind.noteOff, channel: 0, data1: pitch, data2: velocity);

void main() {
  group('MidiByteParser', () {
    test('reads a note played and let go', () {
      final parser = MidiByteParser();
      expect(parser.add([0x90, 60, 100, 0x80, 60, 64]),
          [on(60, 100), off(60, 64)]);
    });

    test('a note-on at velocity 0 is the note-off it means', () {
      // Most keyboards let go of a key this way.
      expect(MidiByteParser().add([0x90, 60, 100, 0x90, 60, 0]),
          [on(60, 100), off(60)]);
    });

    test('keeps the channel', () {
      expect(MidiByteParser().add([0x99, 36, 90]), [on(36, 90, channel: 9)]);
    });

    test('running status: notes without their status byte', () {
      // A chord sent as one status and three pairs of data bytes.
      expect(MidiByteParser().add([0x90, 60, 100, 64, 100, 67, 100, 60, 0]),
          [on(60, 100), on(64, 100), on(67, 100), off(60)]);
    });

    test('a message split across two deliveries', () {
      final parser = MidiByteParser();
      expect(parser.add([0x90, 60]), isEmpty);
      expect(parser.add([100]), [on(60, 100)]);
      // Running status carries over too.
      expect(parser.add([62]), isEmpty);
      expect(parser.add([90]), [on(62, 90)]);
    });

    test('clock and other real-time bytes are skipped, even mid-message', () {
      // A keyboard following a DAW's clock sends 0xF8 24 times a beat.
      expect(MidiByteParser().add([0xF8, 0x90, 0xF8, 60, 0xFE, 100, 0xF8]),
          [on(60, 100)]);
    });

    test('a system exclusive dump is skipped whole', () {
      expect(
        MidiByteParser()
            .add([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7, 0x90, 60, 100]),
        [on(60, 100)],
      );
    });

    test('a dump never closed ends at the next status', () {
      expect(MidiByteParser().add([0xF0, 1, 2, 3, 0x90, 60, 100]),
          [on(60, 100)]);
    });

    test('a system message cancels running status', () {
      // Song position (two data bytes), then data with no status of its
      // own: it belongs to nothing.
      expect(MidiByteParser().add([0x90, 60, 100, 0xF2, 1, 2, 62, 100]),
          [on(60, 100)]);
    });

    test('data before any status is ignored', () {
      expect(MidiByteParser().add([60, 100, 0x90, 61, 90]), [on(61, 90)]);
    });

    test('controllers, programs, pressure and pitch bend', () {
      expect(
        MidiByteParser().add([
          0xB0, 1, 64, // Mod wheel.
          0xC0, 5, // Program.
          0xD0, 30, // Channel pressure.
          0xA0, 60, 40, // Poly pressure.
          0xE0, 0x00, 0x40, // Pitch bend at rest.
          0xE0, 0x7F, 0x7F, // Bent all the way up.
        ]),
        [
          const MidiInputMessage(
              kind: MidiInputKind.controller, channel: 0, data1: 1, data2: 64),
          const MidiInputMessage(
              kind: MidiInputKind.program, channel: 0, data1: 5),
          const MidiInputMessage(
              kind: MidiInputKind.channelPressure, channel: 0, data2: 30),
          const MidiInputMessage(
              kind: MidiInputKind.polyPressure,
              channel: 0,
              data1: 60,
              data2: 40),
          const MidiInputMessage(
              kind: MidiInputKind.pitchBend, channel: 0, data2: 8192),
          const MidiInputMessage(
              kind: MidiInputKind.pitchBend, channel: 0, data2: 16383),
        ],
      );
    });

    test('a program change uses running status with one data byte', () {
      expect(
        MidiByteParser().add([0xC0, 1, 2]),
        [
          const MidiInputMessage(
              kind: MidiInputKind.program, channel: 0, data1: 1),
          const MidiInputMessage(
              kind: MidiInputKind.program, channel: 0, data1: 2),
        ],
      );
    });
  });

  group('shortMessageBytes', () {
    test('unpacks a Windows short message: status, then data bytes', () {
      // midiInProc's dwParam1 for "note on, C4, velocity 100".
      expect(shortMessageBytes(0x90 | (60 << 8) | (100 << 16)), [0x90, 60, 100]);
    });

    test('as many data bytes as the status has', () {
      expect(shortMessageBytes(0xC0 | (5 << 8) | (99 << 16)), [0xC0, 5]);
      expect(shortMessageBytes(0xD3 | (30 << 8)), [0xD3, 30]);
      expect(shortMessageBytes(0xF8), [0xF8]);
      expect(shortMessageBytes(0xF2 | (1 << 8) | (2 << 16)), [0xF2, 1, 2]);
    });

    test('running status (no status byte) gives nothing', () {
      // winmm always fills the status in; a bare data byte is noise.
      expect(shortMessageBytes(60 | (100 << 8)), isEmpty);
    });

    test('round-trips through the parser', () {
      final parser = MidiByteParser();
      expect(parser.add(shortMessageBytes(0x80 | (60 << 8) | (64 << 16))),
          [off(60, 64)]);
    });
  });
}
