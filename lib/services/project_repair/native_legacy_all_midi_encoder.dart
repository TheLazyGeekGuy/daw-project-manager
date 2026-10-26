import 'dart:convert';
import 'dart:typed_data';

import 'native_legacy_all_reader.dart';

/// Standard MIDI File type 1 export for DPM's native classic Cubase reader.
///
/// Track zero stores initial tempo and time signatures. Subsequent tracks
/// retain recovered names and MIDI channels at 480 PPQ. The encoding follows
/// AllToMidi's open-source design, without its Windows/WinForms dependencies.
///
/// MIDI-only export never claims to reconstruct audio, instrument state,
/// plug-in automation or historical mixer routing.
class NativeLegacyAllMidiEncoder {
  const NativeLegacyAllMidiEncoder();

  Uint8List encode(LegacyAllSong song, {String songName = 'Legacy Cubase'}) {
    if (song.tracks.isEmpty || song.tracks.length > 1023) {
      throw const FormatException('MIDI type 1 requires 1–1023 music tracks');
    }
    const resolution = 480;
    final chunks = <Uint8List>[];

    final conductor = <_MidiOutputEvent>[];
    var order = 0;
    conductor.add(_MidiOutputEvent(
      tick: 0,
      order: order++,
      data: _meta(0x03, utf8.encode(songName)),
    ));
    final micros = song.microsecondsPerQuarter.clamp(1, 0xffffff);
    conductor.add(_MidiOutputEvent(
      tick: 0,
      order: order++,
      data: [
        0xff, 0x51, 3,
        (micros >> 16) & 0xff,
        (micros >> 8) & 0xff,
        micros & 0xff,
      ],
    ));
    for (final time in song.signatures) {
      if (time.tick < 0 || time.numerator < 1 || time.numerator > 32 ||
          time.denominatorPower < 0 || time.denominatorPower > 7) {
        throw const FormatException('Invalid ALL time signature');
      }
      conductor.add(_MidiOutputEvent(
        tick: time.tick,
        order: order++,
        data: [
          0xff, 0x58, 4,
          time.numerator,
          time.denominatorPower,
          24, 8,
        ],
      ));
    }
    chunks.add(_encodeTrack(conductor));

    for (final track in song.tracks) {
      final events = <_MidiOutputEvent>[];
      var seq = 0;
      events.add(_MidiOutputEvent(
        tick: 0,
        order: seq++,
        data: _meta(0x03, utf8.encode(track.name)),
      ));
      for (final event in track.events) {
        final kind = event.status & 0xf0;
        final channel = event.status & 0x0f;
        if (event.tick < 0 || event.data1 < 0 ||
            event.data1 > 127 || event.data2 < 0 ||
            event.data2 > 127 || event.duration < 0) {
          throw const FormatException('Invalid recovered MIDI event');
        }
        if (kind == 0x90 && event.data2 > 0) {
          // A malformed duration should not leave a MIDI note stuck forever.
          if (event.duration == 0) {
            throw const FormatException('Recovered note has no valid duration');
          }
          final end = event.tick + event.duration;
          events.add(_MidiOutputEvent(
            tick: event.tick,
            order: seq++,
            data: [0x90 | channel, event.data1, event.data2],
          ));
          events.add(_MidiOutputEvent(
            tick: end,
            order: seq++,
            data: [0x80 | channel, event.data1, 0],
          ));
        } else if (kind == 0xc0 || kind == 0xd0) {
          events.add(_MidiOutputEvent(
            tick: event.tick,
            order: seq++,
            data: [event.status, event.data1],
          ));
        } else if ({
          0x80, 0x90, 0xa0, 0xb0, 0xe0,
        }.contains(kind)) {
          events.add(_MidiOutputEvent(
            tick: event.tick,
            order: seq++,
            data: [event.status, event.data1, event.data2],
          ));
        } else {
          throw const FormatException('Unsupported recovered MIDI status');
        }
      }
      chunks.add(_encodeTrack(events));
    }

    final output = BytesBuilder(copy: false);
    output.add(ascii.encode('MThd'));
    output.add(_u32(6));
    output.add(_u16(1));
    output.add(_u16(chunks.length));
    output.add(_u16(resolution));
    for (final chunk in chunks) {
      output.add(ascii.encode('MTrk'));
      output.add(_u32(chunk.length));
      output.add(chunk);
    }
    return output.toBytes();
  }

  Uint8List _encodeTrack(List<_MidiOutputEvent> events) {
    // Metas first, followed by note-offs, other channel events, and note-ons.
    // Same-tick note-offs precede note-ons to support repeated pitches.
    events.sort((a, b) {
      final tick = a.tick.compareTo(b.tick);
      if (tick != 0) return tick;
      final priority = a.priority.compareTo(b.priority);
      return priority == 0 ? a.order.compareTo(b.order) : priority;
    });
    final out = BytesBuilder(copy: false);
    var last = 0;
    for (final event in events) {
      if (event.tick < last) {
        throw const FormatException('MIDI events cannot run backward');
      }
      final delta = event.tick - last;
      if (delta > 0x0fffffff) {
        throw const FormatException('MIDI event time exceeds VLQ bounds');
      }
      out.add(_vlq(delta));
      out.add(event.data);
      last = event.tick;
    }
    out.addByte(0);
    out.add(const [0xff, 0x2f, 0]);
    return out.toBytes();
  }

  static List<int> _meta(int type, List<int> payload) =>
      [0xff, type, ..._vlq(payload.length), ...payload];

  static List<int> _u16(int value) =>
      [(value >> 8) & 0xff, value & 0xff];

  static List<int> _u32(int value) => [
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  static List<int> _vlq(int value) {
    if (value < 0 || value > 0x0fffffff) {
      throw const FormatException('Invalid MIDI variable-length value');
    }
    final out = <int>[value & 0x7f];
    var rest = value >> 7;
    while (rest > 0) {
      out.insert(0, (rest & 0x7f) | 0x80);
      rest >>= 7;
    }
    return out;
  }
}

class _MidiOutputEvent {
  const _MidiOutputEvent({
    required this.tick,
    required this.order,
    required this.data,
  });

  final int tick;
  final int order;
  final List<int> data;

  int get priority {
    if (data.isEmpty || data.first == 0xff) return 0;
    final kind = data.first & 0xf0;
    if (kind == 0x80 ||
        (kind == 0x90 && data.length > 2 && data[2] == 0)) {
      return 1;
    }
    if (kind == 0x90) return 3;
    return 2;
  }
}
