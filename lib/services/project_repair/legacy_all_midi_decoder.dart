// SPDX-License-Identifier: MIT
// Derived from OnjLouis/AllToMidi Program.cs at
// ea2e985f680e020a8efd662085ac01b8edc03770.
// Copyright (c) 2026 AllToMidi contributors.
// See third_party/alltomidi/LICENSE.txt and README.md for attribution/changes.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

typedef LegacyAllRecoveredEvent = ({
  int tick,
  int status,
  int data1,
  int data2,
  int duration,
});

typedef LegacyAllRecoveredTimeSignature = ({
  int tick,
  int numerator,
  int denominatorPower,
});

/// Experimental recovery of two observed legacy Cubase .ALL event layouts.
/// This parser does not decode .ARR, audio, VST states or a complete Cubase mix.
class LegacyAllMidiResult {
  const LegacyAllMidiResult({
    required this.midi,
    required this.tracks,
    required this.skippedParts,
    required this.initialTempoMicroseconds,
    required this.tempoDefaulted,
    this.timeSignatures = const [],
  });
  final Uint8List midi;
  final List<LegacyAllTrack> tracks;
  final int skippedParts, initialTempoMicroseconds;
  final bool tempoDefaulted;
  final List<LegacyAllRecoveredTimeSignature> timeSignatures;
  int get noteCount =>
      tracks.fold(0, (count, track) => count + track.noteCount);

  Map<String, Object?> toJson() => {
    'engine': 'dpm-alltomidi-dart',
    'upstream': 'https://github.com/OnjLouis/AllToMidi',
    'upstream_commit': 'ea2e985f680e020a8efd662085ac01b8edc03770',
    'status': skippedParts > 0
        ? 'partial_recovery_unverified'
        : 'generated_unverified',
    'midi_type': 1,
    'ticks_per_quarter_note': 480,
    'track_count': tracks.length,
    'note_count': noteCount,
    'skipped_parts': skippedParts,
    'initial_tempo_microseconds': initialTempoMicroseconds,
    'initial_tempo_defaulted': tempoDefaulted,
    'time_signatures': [
      for (final signature in timeSignatures)
        {
          'tick': signature.tick,
          'numerator': signature.numerator,
          'denominator': 1 << signature.denominatorPower,
        },
    ],
    'tracks': [for (final track in tracks) track.toJson()],
    'limitations': const [
      'Only observed compact and fixed .ALL event layouts are implemented.',
      'Mid-song tempo changes and System Exclusive messages are not recovered.',
      'Time-signature changes in fixed-layout files are not certified.',
      'Audio, plug-ins, presets, mixer settings and native automation are not recovered.',
      'MIDI event recovery is not a CPR conversion or a native DAW reopen test.',
    ],
    'native_daw_reopen_verified': false,
  };
}

class LegacyAllTrack {
  LegacyAllTrack(
    this.name,
    this.nameBytes,
    this.channel,
    this.trackNumber,
    this.layout,
  );
  final String name;
  final List<int> nameBytes;
  final int channel, trackNumber;
  final String layout;
  int partCount = 0;
  final List<_AllEvent> _events = [];

  /// Immutable value snapshots for preview adapters; no decoder state escapes.
  List<LegacyAllRecoveredEvent> get events => List.unmodifiable([
    for (final event in _events)
      (
        tick: event.tick,
        status: event.status,
        data1: event.data1,
        data2: event.data2,
        duration: event.duration,
      ),
  ]);
  int get noteCount => _events
      .where((e) => e.status & 0xf0 == 0x90 && e.data2 > 0 && e.duration > 0)
      .length;
  Map<String, Object?> toJson() => {
    'name': name,
    'track_number': trackNumber,
    'midi_channel': channel,
    'layout': layout,
    'parts': partCount,
    'events': _events.length,
    'notes': noteCount,
  };
}

class LegacyAllMidiDecoder {
  static const maxInputBytes = 64 * 1024 * 1024;
  static const maxEvents = 250000;
  static const maxCandidates = 2048;

  static LegacyAllMidiResult decode(
    Uint8List bytes, {
    String songName = 'Recovered song',
  }) {
    if (bytes.length < 183 || bytes.length > maxInputBytes) {
      throw const FormatException('Legacy ALL input outside size limits');
    }
    return _AllDecoder(bytes).decode(songName);
  }
}

class _AllDecoder {
  _AllDecoder(this.data);
  final Uint8List data;
  int eventsRead = 0;
  int skipped = 0;
  int u16(int at) => (data[at] << 8) | data[at + 1];
  int u24(int at) => (data[at] << 16) | (data[at + 1] << 8) | data[at + 2];
  int u32(int at) =>
      (data[at] << 24) |
      (data[at + 1] << 16) |
      (data[at + 2] << 8) |
      data[at + 3];
  int s16(int at) {
    final value = u16(at);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int compactTick(int value) => math.min(0x7fffffff, (value * 5 + 1) ~/ 4);
  int fixedTick(int value) => (value + 15) ~/ 32;

  LegacyAllMidiResult decode(String songName) {
    final names = _findTrackNames();
    final parts = names
        .where((n) => n.recordNumber + 1 != n.trackNumber)
        .toList();
    final merged = <int, LegacyAllTrack>{};
    for (var i = 0; i < parts.length; i++) {
      final source = parts[i];
      final end = i + 1 < parts.length ? parts[i + 1].offset - 33 : data.length;
      var terminator = -1;
      for (var at = source.offset + 16; at + 4 <= end; at++) {
        if (data[at] == 0 &&
            data[at + 1] == 255 &&
            data[at + 2] == 255 &&
            data[at + 3] == 255) {
          terminator = at;
          break;
        }
      }
      LegacyAllTrack? decoded;
      if (terminator > source.offset + 42) {
        decoded = _decodeCompact(source, source.offset + 42, terminator);
      }
      if (decoded == null || decoded._events.isEmpty) {
        decoded = _decodeFixed(source, end);
      }
      if (decoded == null || decoded._events.isEmpty) {
        skipped++;
        continue;
      }
      final target = merged.putIfAbsent(
        source.trackNumber,
        () => LegacyAllTrack(
          decoded!.name,
          decoded.nameBytes,
          decoded.channel,
          decoded.trackNumber,
          decoded.layout,
        ),
      );
      target.partCount += decoded.partCount;
      target._events.addAll(decoded._events);
    }
    if (merged.isEmpty) {
      throw const FormatException(
        'No recognized MIDI channel events were found in this ALL file',
      );
    }
    final tracks = merged.values.toList()
      ..sort((a, b) => a.trackNumber.compareTo(b.trackNumber));
    final milliBpm = u32(0xa2);
    final defaulted = milliBpm < 10000 || milliBpm > 400000;
    final tempo = defaulted ? 750000 : 60000000000 ~/ milliBpm;
    final signatures = List<LegacyAllRecoveredTimeSignature>.unmodifiable([
      for (final signature in _signatures(
        tracks.any((t) => t.layout == 'fixed'),
      ))
        (
          tick: signature.$1,
          numerator: signature.$2,
          denominatorPower: signature.$3,
        ),
    ]);
    final midi = _buildMidi(tracks, songName, tempo, signatures);
    return LegacyAllMidiResult(
      midi: midi,
      tracks: List.unmodifiable(tracks),
      skippedParts: skipped,
      initialTempoMicroseconds: tempo,
      tempoDefaulted: defaulted,
      timeSignatures: signatures,
    );
  }

  LegacyAllTrack _track(_TrackName source, String layout) {
    var channel = data[source.offset - 5] + 1;
    if (channel < 1 || channel > 16) channel = source.trackNumber;
    if (channel > 16) channel = 1;
    return LegacyAllTrack(
      source.name,
      source.bytes,
      channel,
      source.trackNumber,
      layout,
    );
  }

  void _add(LegacyAllTrack track, _AllEvent event) {
    if (++eventsRead > LegacyAllMidiDecoder.maxEvents) {
      throw const FormatException('Legacy ALL event limit exceeded');
    }
    track._events.add(event);
  }

  LegacyAllTrack? _decodeCompact(_TrackName source, int start, int end) {
    final track = _track(source, 'compact');
    final partTick = u24(source.offset - 33);
    var at = start, wrap = 0, previous = 0;
    while (at + 6 <= end) {
      final kind = data[at + 4] & 0xf0;
      final raw = u16(at + 2);
      if (raw < previous && previous - raw > 0x8000) wrap += 0x10000;
      previous = raw;
      final absolute = partTick + wrap + raw;
      final tick = compactTick(absolute);
      final status = kind | (track.channel - 1);
      var duration = 0;
      if (kind == 0x90 || kind == 0x80) {
        if (at + 12 > end) return null;
        if (data[at] < 128 && data[at + 5] < 128) {
          if (kind == 0x90 && data[at + 5] > 0) {
            final scaled = compactTick(absolute + s16(at + 8)) - tick;
            duration = math.max(1, scaled <= 4 ? scaled : scaled - 2);
          }
          _add(
            track,
            _AllEvent(tick, status, data[at], data[at + 5], duration),
          );
        }
        at += 12;
      } else if (const {0xa0, 0xb0, 0xc0, 0xd0, 0xe0}.contains(kind)) {
        if (data[at] < 128 &&
            (kind == 0xc0 || kind == 0xd0 || data[at + 5] < 128)) {
          _add(track, _AllEvent(tick, status, data[at], data[at + 5], 0));
        }
        at += 6;
      } else {
        return null;
      }
    }
    if (at != end) return null;
    track.partCount = track._events.isNotEmpty ? 1 : 0;
    return track;
  }

  LegacyAllTrack? _decodeFixed(_TrackName source, int end) {
    var at = source.offset + 139;
    if (at + 8 > end) return null;
    final track = _track(source, 'fixed');
    final partTick = u24(source.offset - 33);
    var terminated = false;
    while (at + 8 <= end) {
      if (data[at] == 255 && data[at + 1] == 255 && data[at + 2] == 255) {
        terminated = true;
        break;
      }
      final kind = data[at + 3] & 0xf0;
      final status = kind | (track.channel - 1);
      final absolute = partTick + u24(at);
      final tick = fixedTick(absolute);
      var duration = 0;
      if (kind == 0x90 || kind == 0x80) {
        if (at + 16 > end) return null;
        if (data[at + 4] < 128 && data[at + 5] < 128) {
          if (kind == 0x90 && data[at + 5] > 0) {
            duration = math.max(
              1,
              fixedTick(absolute + u24(at + 8)) - 2 - tick,
            );
          }
          _add(
            track,
            _AllEvent(tick, status, data[at + 4], data[at + 5], duration),
          );
        }
        at += 16;
      } else if (const {0xa0, 0xb0, 0xc0, 0xd0, 0xe0}.contains(kind)) {
        if (data[at + 4] < 128 &&
            (kind == 0xc0 || kind == 0xd0 || data[at + 5] < 128)) {
          _add(track, _AllEvent(tick, status, data[at + 4], data[at + 5], 0));
        }
        at += 8;
      } else if (data[at + 3] == 0x0e && at + 24 <= end) {
        at += 24;
      } else {
        return null;
      }
    }
    if (!terminated) return null;
    track.partCount = track._events.isNotEmpty ? 1 : 0;
    return track;
  }

  List<_TrackName> _findTrackNames() {
    final candidates = <_TrackName>[];
    for (var at = 33; at < data.length - 149; at++) {
      if (!const {0x99, 0x9f}.contains(data[at - 8]) ||
          data[at - 10] != 0 ||
          data[at - 9] != 0 ||
          data[at] < 32 ||
          (data[at + 15] & 0x7f) > 3) {
        continue;
      }
      var end = -1, printable = true;
      for (var field = at; field < at + 10; field++) {
        if (data[field] == 0) {
          if (end < 0) end = field;
        } else if (data[field] < 32) {
          printable = false;
          break;
        }
      }
      if (!printable) continue;
      if (end < 0) end = at + 10;
      if (end <= at) continue;
      final nameBytes = data.sublist(at, end);
      final name = _decode1252(nameBytes);
      final number = u16(at - 16) + 1;
      if (name.toLowerCase() == 'marker' || number > 256) continue;
      candidates.add(_TrackName(at, name, nameBytes, number, u16(at - 18)));
      if (candidates.length > LegacyAllMidiDecoder.maxCandidates) {
        throw const FormatException('Too many legacy ALL record candidates');
      }
    }
    var bestStart = -1, bestCount = 0, bestMatches = -1;
    for (var start = 0; start < candidates.length; start++) {
      if (candidates[start].recordNumber + 1 != candidates[start].trackNumber) {
        continue;
      }
      var count = 0;
      while (start + count < candidates.length &&
          candidates[start + count].recordNumber ==
              candidates[start].recordNumber + count &&
          candidates[start + count].trackNumber ==
              candidates[start].trackNumber + count) {
        count++;
      }
      final definitions = {
        for (final n in candidates.skip(start).take(count))
          n.trackNumber: n.name,
      };
      final last = candidates[start + count - 1].recordNumber;
      final matches = candidates
          .skip(start + count)
          .where(
            (n) =>
                n.recordNumber > last && definitions[n.trackNumber] == n.name,
          )
          .length;
      if (count > bestCount || (count == bestCount && matches > bestMatches)) {
        bestStart = start;
        bestCount = count;
        bestMatches = matches;
      }
    }
    if (bestStart < 0) return [];
    final names = candidates.skip(bestStart).take(bestCount).toList();
    final last = names.last.recordNumber;
    final definitions = {for (final n in names) n.trackNumber: n.name};
    names.addAll(
      candidates
          .skip(bestStart + bestCount)
          .where(
            (n) =>
                n.recordNumber > last && definitions[n.trackNumber] == n.name,
          ),
    );
    return names;
  }

  List<(int, int, int)> _signatures(bool fixed) {
    bool valid(int at) =>
        at + 8 <= data.length &&
        data[at + 4] <= 7 &&
        data[at + 5] == 0 &&
        data[at + 6] >= 1 &&
        data[at + 6] <= 32 &&
        data[at + 7] == 4;
    for (var start = 0; start + 12 <= data.length; start++) {
      if (u32(start) != 0 || !valid(start)) continue;
      final signatures = <(int, int, int)>[];
      var previous = -1;
      for (var at = start; at + 4 <= data.length; at += 8) {
        if (u32(at) == 0x7fffffff) {
          if (signatures.isNotEmpty) return signatures;
          break;
        }
        if (!valid(at)) break;
        final raw = u32(at);
        if (raw < previous || raw > 0x7fffffff) break;
        previous = raw;
        signatures.add((
          fixed ? fixedTick(raw) : compactTick(raw),
          data[at + 6],
          data[at + 4],
        ));
        if (signatures.length > 10000) {
          throw const FormatException('Too many time signatures');
        }
      }
    }
    return [(0, 4, 2)];
  }

  Uint8List _buildMidi(
    List<LegacyAllTrack> tracks,
    String songName,
    int tempo,
    List<LegacyAllRecoveredTimeSignature> signatures,
  ) {
    final conductor = <_MidiEvent>[
      _MidiEvent(0, _meta(3, _encode1252(songName))),
      _MidiEvent(0, [
        255,
        81,
        3,
        tempo >> 16 & 255,
        tempo >> 8 & 255,
        tempo & 255,
      ]),
      for (final signature in signatures)
        _MidiEvent(signature.tick, [
          255,
          88,
          4,
          signature.numerator,
          signature.denominatorPower,
          24,
          8,
        ]),
    ];
    final chunks = <Uint8List>[_buildTrack(conductor)];
    for (final track in tracks) {
      final events = <_MidiEvent>[_MidiEvent(0, _meta(3, track.nameBytes))];
      for (final event in track._events) {
        final kind = event.status & 0xf0;
        if (kind == 0x90 && event.data2 > 0 && event.duration > 0) {
          events.add(
            _MidiEvent(event.tick, [event.status, event.data1, event.data2]),
          );
          events.add(
            _MidiEvent(event.tick + event.duration, [
              0x80 | (event.status & 15),
              event.data1,
              0,
            ]),
          );
        } else {
          events.add(
            _MidiEvent(event.tick, [
              event.status,
              event.data1,
              if (kind != 0xc0 && kind != 0xd0) event.data2,
            ]),
          );
        }
      }
      chunks.add(_buildTrack(events));
    }
    final output = BytesBuilder(copy: false)
      ..add(ascii.encode('MThd'))
      ..add(_be(6, 4))
      ..add(_be(1, 2))
      ..add(_be(chunks.length, 2))
      ..add(_be(480, 2));
    for (final chunk in chunks) {
      output.add(chunk);
    }
    return output.takeBytes();
  }
}

class _AllEvent {
  const _AllEvent(
    this.tick,
    this.status,
    this.data1,
    this.data2,
    this.duration,
  );
  final int tick, status, data1, data2, duration;
}

class _TrackName {
  const _TrackName(
    this.offset,
    this.name,
    this.bytes,
    this.trackNumber,
    this.recordNumber,
  );
  final int offset, trackNumber, recordNumber;
  final String name;
  final List<int> bytes;
}

class _MidiEvent {
  const _MidiEvent(this.tick, this.data);
  final int tick;
  final List<int> data;
}

Uint8List _buildTrack(List<_MidiEvent> events) {
  int priority(List<int> bytes) {
    if (bytes.first == 255) return 0;
    final kind = bytes.first & 0xf0;
    if (kind == 0x80 || (kind == 0x90 && bytes.length > 2 && bytes[2] == 0)) {
      return 1;
    }
    return kind == 0x90 ? 3 : 2;
  }

  // Original index makes equal-priority event ordering deterministic.
  final indexed = events.indexed.toList()
    ..sort((a, b) {
      final timing = a.$2.tick.compareTo(b.$2.tick);
      if (timing != 0) return timing;
      final order = priority(a.$2.data).compareTo(priority(b.$2.data));
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  final body = BytesBuilder(copy: false);
  var last = 0;
  for (final item in indexed) {
    final event = item.$2;
    body.add(_vlq(event.tick - last));
    body.add(event.data);
    last = event.tick;
  }
  body.add([0, 255, 47, 0]);
  return (BytesBuilder(copy: false)
        ..add(ascii.encode('MTrk'))
        ..add(_be(body.length, 4))
        ..add(body.takeBytes()))
      .takeBytes();
}

List<int> _be(int value, int count) => [
  for (var i = count - 1; i >= 0; i--) (value >> (i * 8)) & 255,
];
List<int> _meta(int kind, List<int> bytes) => [
  255,
  kind,
  ..._vlq(bytes.length),
  ...bytes,
];
List<int> _vlq(int value) {
  if (value < 0 || value > 0x0fffffff) {
    throw const FormatException('MIDI delta exceeds standard VLQ range');
  }
  final bytes = <int>[value & 127];
  while ((value >>= 7) > 0) {
    bytes.insert(0, (value & 127) | 128);
  }
  return bytes;
}

const _windows1252 = [
  0x20ac,
  0x81,
  0x201a,
  0x192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x2c6,
  0x2030,
  0x160,
  0x2039,
  0x152,
  0x8d,
  0x17d,
  0x8f,
  0x90,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x2dc,
  0x2122,
  0x161,
  0x203a,
  0x153,
  0x9d,
  0x17e,
  0x178,
];
String _decode1252(List<int> bytes) => String.fromCharCodes(
  bytes.map((b) => b >= 128 && b < 160 ? _windows1252[b - 128] : b),
);
List<int> _encode1252(String text) => [
  for (final rune in text.runes)
    if (_windows1252.contains(rune))
      _windows1252.indexOf(rune) + 128
    else if (rune < 256)
      rune
    else
      63,
];
