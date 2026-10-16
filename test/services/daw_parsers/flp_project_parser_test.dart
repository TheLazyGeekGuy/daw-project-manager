import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/daw_parsers/flp_project_parser.dart';

/// Builds an `.flp`: `FLhd` (format, channels, PPQ) then `FLdt` holding TLV
/// events whose id range sets the payload size.
class _Flp {
  final _events = BytesBuilder();

  void byte(int id, int v) => _events.add([id, v]);

  void word(int id, int v) => _events.add([id, v & 255, (v >> 8) & 255]);

  void data(int id, List<int> payload) {
    _events.addByte(id);
    var len = payload.length;
    do {
      var b = len & 0x7F;
      len >>= 7;
      if (len > 0) b |= 0x80;
      _events.addByte(b);
    } while (len > 0);
    _events.add(payload);
  }

  /// FL 11.5+ text: UTF-16LE, NUL-terminated.
  void text(int id, String s) {
    final out = <int>[];
    for (final unit in '$s\u0000'.codeUnits) {
      out..add(unit & 255)..add(unit >> 8);
    }
    data(id, out);
  }

  void note(List<int> into, {
    required int position,
    required int channel,
    required int length,
    required int key,
    required int velocity,
  }) {
    final d = ByteData(24)
      ..setUint32(0, position, Endian.little)
      ..setUint16(6, channel, Endian.little)
      ..setUint32(8, length, Endian.little)
      ..setUint16(12, key, Endian.little)
      ..setUint8(21, velocity);
    into.addAll(d.buffer.asUint8List());
  }

  /// A note as FL 7 wrote it: 20 bytes, with the bytes it fills in for
  /// every note — flags 0x4000, fine pitch 120, release 64, pan 64, mod X/Y
  /// 128 — which read as nonsense when taken 24 bytes at a time.
  void note7(List<int> into, {
    required int position,
    required int channel,
    required int length,
    required int key,
    required int velocity,
    int midiChannel = 0,
  }) {
    final d = ByteData(20)
      ..setUint32(0, position, Endian.little)
      ..setUint16(4, 0x4000, Endian.little)
      ..setUint16(6, channel, Endian.little)
      ..setUint32(8, length, Endian.little)
      ..setUint8(12, key)
      ..setUint8(13, 120)
      ..setUint8(14, 64)
      ..setUint8(15, midiChannel)
      ..setUint8(16, 64)
      ..setUint8(17, velocity)
      ..setUint8(18, 128)
      ..setUint8(19, 128);
    into.addAll(d.buffer.asUint8List());
  }

  Uint8List build({int ppq = 96}) {
    final body = _events.toBytes();
    final header = ByteData(14)
      ..setUint32(4, 6, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, 3, Endian.little)
      ..setUint16(12, ppq, Endian.little);
    final h = header.buffer.asUint8List()..setAll(0, ascii.encode('FLhd'));
    final len = ByteData(4)..setUint32(0, body.length, Endian.little);
    return (BytesBuilder()
          ..add(h)
          ..add(ascii.encode('FLdt'))
          ..add(len.buffer.asUint8List())
          ..add(body))
        .toBytes();
  }
}

Uint8List _project() {
  final f = _Flp();
  f.data(199, ascii.encode('21.2.3.4004\u0000'));
  // Channel 0: a wrapped VST — internal name "Fruity Wrapper".
  f.word(64, 0);
  f.byte(21, 2);
  f.text(201, 'Fruity Wrapper');
  f.text(203, 'Serum');
  // Channel 1: a sampler, no plug-in.
  f.word(64, 1);
  f.byte(21, 0);
  f.text(203, 'Kick');
  // Channel 2: an audio clip.
  f.word(64, 2);
  f.byte(21, 4);
  // A native mixer effect, named by its internal name.
  f.text(201, 'Fruity Limiter');
  f.text(203, 'Master limiter');
  // Pattern 1: notes for two channels.
  f.word(65, 1);
  f.text(193, 'Intro beat');
  final notes = <int>[];
  f.note(notes, position: 0, channel: 1, length: 24, key: 60, velocity: 100);
  f.note(notes, position: 96, channel: 1, length: 24, key: 60, velocity: 100);
  f.note(notes, position: 0, channel: 0, length: 192, key: 48, velocity: 90);
  f.data(224, notes);
  return f.build();
}

void main() {
  final parser = FlpProjectParser(_project());

  group('readStats', () {
    test('counts channels by type', () {
      final stats = parser.readStats();
      expect(stats.instrumentTracks, 1);
      expect(stats.samplerTracks, 1);
      expect(stats.audioTracks, 1);
    });

    test('names wrapped plug-ins by display name, native ones by internal name',
        () {
      expect(parser.readStats().plugins, ['Fruity Limiter', 'Serum']);
    });

    test('counts one clip per pattern per channel', () {
      expect(parser.readStats().midiClipCount, 2);
    });
  });

  group('readMidiClips', () {
    test('splits a pattern by channel and names each after its channel', () {
      final clips = parser.readMidiClips();
      final kick = clips.firstWhere((c) => c.trackName == 'Kick');
      expect(kick.name, 'Intro beat');
      expect(kick.ppq, 96);
      expect(kick.notes.map((n) => (n.startTick, n.pitch)), [(0, 60), (96, 60)]);
      expect(kick.lengthTicks, 384, reason: 'rounded up to a whole 4/4 bar');

      final serum = clips.firstWhere((c) => c.trackName == 'Serum');
      expect(serum.notes.single.velocity, 90);
    });
  });

  test('before FL 12 a channel is named by event 192, after its plug-in state', () {
    // As FL 10 wrote a wrapped VST: internal name, state, then the name.
    final f = _Flp();
    f.data(199, ascii.encode('10.0.0\u0000'));
    f.word(64, 0);
    f.byte(21, 2);
    f.data(201, ascii.encode('Fruity Wrapper\u0000'));
    f.data(213, List.filled(64, 7));
    f.data(192, ascii.encode('Sylenth1 #3\u0000'));
    f.word(64, 1);
    f.byte(21, 0);
    f.data(192, ascii.encode('Kick 2013\u0000'));
    f.word(65, 1);
    final notes = <int>[];
    f.note(notes, position: 0, channel: 0, length: 96, key: 60, velocity: 100);
    f.note(notes, position: 0, channel: 1, length: 24, key: 36, velocity: 100);
    f.data(224, notes);
    final parser = FlpProjectParser(f.build());
    expect(parser.readStats().plugins, ['Sylenth1'],
        reason: 'the wrapped VST by its name, not its instance number; a sampler is no plug-in');
    expect(parser.readMidiClips().map((c) => c.trackName).toSet(), {'Sylenth1 #3', 'Kick 2013'});
  });

  group('a wrapped VST is named by the plug-in it hosts', () {
    // The wrapper's state: a u32, then (id u32, size u64, data) records;
    // 54 is the plug-in's name.
    List<int> wrapperState(String plugin) {
      final out = BytesBuilder()..add([7, 0, 0, 0]);
      void record(int id, List<int> data) {
        final head = ByteData(12)
          ..setUint32(0, id, Endian.little)
          ..setUint64(4, data.length, Endian.little);
        out..add(head.buffer.asUint8List())..add(data);
      }
      record(51, ascii.encode('1lys'));
      record(54, utf8.encode(plugin));
      record(55, ascii.encode('C:/Program Files/Image-Line'));
      return out.toBytes();
    }

    test('not the channel, renamed after a preset — whichever comes first', () {
      final f = _Flp();
      // FL 20: display name, then state.
      f.word(64, 0);
      f.byte(21, 2);
      f.text(201, 'Fruity Wrapper');
      f.text(203, 'LD Menu Special');
      f.data(213, wrapperState('Sylenth1'));
      // FL 10: state, then the name (192).
      f.word(64, 1);
      f.byte(21, 2);
      f.data(201, ascii.encode('Fruity Wrapper\u0000'));
      f.data(213, wrapperState('Serum'));
      f.data(192, ascii.encode('BAS Deeper Bass\u0000'));
      expect(FlpProjectParser(f.build()).readStats().plugins, ['Serum', 'Sylenth1']);
    });

    test('a state laid out otherwise names it by the channel, and costs nothing else', () {
      // FL 7's wrapper state: what would be a record size reads past 2^63.
      final f = _Flp();
      f.word(64, 0);
      f.byte(21, 2);
      f.text(201, 'Fruity Wrapper');
      f.data(213, [7, 0, 0, 0, 54, 0, 0, 0, ...List.filled(8, 0xF5), ...List.filled(20, 1)]);
      f.text(203, 'Vanguard');
      final stats = FlpProjectParser(f.build()).readStats();
      expect(stats.plugins, ['Vanguard']);
      expect(stats.instrumentTracks, 1, reason: 'a stats read that threw lost every count');
    });

    test('the FL 7 spelling "Fruity wrapper" is the wrapper too, not a plug-in', () {
      final f = _Flp();
      f.word(64, 0);
      f.byte(21, 2);
      f.data(201, ascii.encode('Fruity wrapper\u0000'));
      f.data(192, ascii.encode('Waves RBass\u0000'));
      expect(FlpProjectParser(f.build()).readStats().plugins, ['Waves RBass']);
    });
  });

  group('FL 7 notes (20-byte records)', () {
    List<(int, int, int, int)> read(void Function(_Flp f, List<int> notes) write) {
      final f = _Flp();
      f.data(199, ascii.encode('7.0.0\u0000'));
      f.word(65, 1);
      final notes = <int>[];
      write(f, notes);
      f.data(224, notes);
      final clip = FlpProjectParser(f.build()).readMidiClips().single;
      return [for (final n in clip.notes) (n.startTick, n.lengthTicks, n.pitch, n.velocity)];
    }

    test('are read when only 20 divides the pattern', () {
      final notes = read((f, into) {
        for (final (i, key) in [60, 63, 67].indexed) {
          f.note7(into, position: i * 96, channel: 0, length: 48, key: key, velocity: 100);
        }
      });
      expect(notes, [(0, 48, 60, 100), (96, 48, 63, 100), (192, 48, 67, 100)]);
    });

    test('are read when 24 divides the pattern too — six notes are 120 bytes', () {
      // A real FL 7 file read 24 bytes at a time came out with every clip
      // 2 billion ticks long, and a minute to read it.
      final notes = read((f, into) {
        for (var i = 0; i < 6; i++) {
          f.note7(into, position: i * 48, channel: 0, length: 24, key: 48 + i, velocity: 90);
        }
      });
      expect(notes, [for (var i = 0; i < 6; i++) (i * 48, 24, 48 + i, 90)]);
    });

    test('keep the MIDI channel of each note, so a part doubled on two stays two', () {
      // A MIDI file imported into FL 7: its parts on their channels, two of
      // them doubling one note. On one channel the two would collide.
      final f = _Flp();
      f.word(65, 1);
      final notes = <int>[];
      f.note7(notes, position: 0, channel: 0, length: 96, key: 60, velocity: 127, midiChannel: 0);
      f.note7(notes, position: 0, channel: 0, length: 96, key: 60, velocity: 127, midiChannel: 1);
      f.note7(notes, position: 0, channel: 0, length: 96, key: 64, velocity: 127, midiChannel: 2);
      f.data(224, notes);
      final clip = FlpProjectParser(f.build()).readMidiClips().single;
      expect(clip.notes.map((n) => (n.pitch, n.channel)).toSet(), {(60, 0), (60, 1), (64, 2)});
    });

    test('a newer pattern both sizes divide still reads as 24-byte records', () {
      final notes = read((f, into) {
        for (var i = 0; i < 5; i++) {
          f.note(into, position: i * 96, channel: 0, length: 96, key: 40 + i, velocity: 80);
        }
      });
      expect(notes, [for (var i = 0; i < 5; i++) (i * 96, 96, 40 + i, 80)]);
    });
  });

  test('a file that is not an FLP reads as empty, not as an error', () {
    final p = FlpProjectParser(Uint8List.fromList(utf8.encode('RIFF....')));
    expect(p.readStats().totalTracks, 0);
    expect(p.readMidiClips(), isEmpty);
  });
}
