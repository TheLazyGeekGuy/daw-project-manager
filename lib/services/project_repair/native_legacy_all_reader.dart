import 'dart:typed_data';

/// Native, cross-platform Cubase VST .ALL MIDI extraction.
///
/// The compact/fixed event layouts, part grouping and timing scalings are a
/// Dart adaptation of AllToMidi 1.0 (Andre Louis, MIT license):
/// https://github.com/OnjLouis/AllToMidi
/// The license is retained in docs/project-repair/third-party/AllToMidi-LICENSE.txt.
///
/// This is an experimental parser for observed .ALL files, NOT a documented
/// Cubase format specification. Unknown variants fail rather than being
/// reported as a lossless conversion. The reader does not decode .ARR,
/// audio, VST states, SysEx or the original mix.
class NativeLegacyAllReader {
  const NativeLegacyAllReader();

  static const maxInputBytes = 128 * 1024 * 1024;
  static const maxNamedRecords = 8192;
  static const maxMidiEvents = 500000;

  LegacyAllSong read(Uint8List data) {
    if (data.length < 192 || data.length > maxInputBytes) {
      throw const FormatException('Legacy ALL is too small or exceeds size limit');
    }
    final candidates = _scanNames(data);
    final names = _findNames(candidates);
    if (names.isEmpty) {
      throw const FormatException('No recognizable Cubase ALL track definitions');
    }
    final partNames = names.where((n) => n.record + 1 != n.track).toList();
    final parts = <LegacyAllTrack>[];
    for (var i = 0; i < partNames.length; i++) {
      final name = partNames[i];
      final next = i + 1 < partNames.length
          ? partNames[i + 1].offset
          : data.length;
      final limit = next <= name.offset ? data.length : next;
      final terminator = _findBytes(data, const [0, 255, 255, 255],
          name.offset + 16, limit);
      LegacyAllTrack? part;
      if (terminator >= 0) {
        final start = name.offset + 42;
        if (start < terminator) {
          part = _readCompact(data, start, terminator, name);
        }
      }
      if (part == null || part.events.isEmpty) {
        part = _readFixed(data, name, limit);
      }
      if (part != null && part.events.isNotEmpty) parts.add(part);
      if (parts.fold<int>(0, (count, t) => count + t.events.length) >
          maxMidiEvents) {
        throw const FormatException('Excessive MIDI events in ALL song');
      }
    }
    final grouped = <int, LegacyAllTrack>{};
    for (final part in parts) {
      final old = grouped[part.trackNumber];
      if (old == null) {
        grouped[part.trackNumber] = part;
      } else {
        grouped[part.trackNumber] = LegacyAllTrack(
          name: old.name,
          channel: old.channel,
          trackNumber: old.trackNumber,
          layout: old.layout,
          partCount: old.partCount + part.partCount,
          events: [...old.events, ...part.events],
        );
      }
    }
    if (grouped.isEmpty) {
      throw const FormatException('ALL contains no recognized MIDI parts');
    }
    final tracks = grouped.values.toList()
      ..sort((a, b) => a.trackNumber.compareTo(b.trackNumber));
    final hasFixed = tracks.any((t) => t.layout == 'fixed');
    final song = LegacyAllSong(
      tracks: List.unmodifiable(tracks),
      microsecondsPerQuarter: _tempoMicros(data),
      signatures: List.unmodifiable(_timeSignatures(data, hasFixed)),
      warnings: const [
        'Experimental recovery from undocumented Cubase ALL layouts.',
        'Audio, VST instruments, effects, mixer settings and SysEx are not recovered.',
        'Mid-song tempo changes and newer time-signature variants may be incomplete.',
        'The result must be checked against the original in a compatible DAW.',
      ],
    );
    if (song.eventCount > maxMidiEvents) {
      throw const FormatException('Excessive MIDI events in ALL song');
    }
    return song;
  }

  List<_AllName> _scanNames(Uint8List bytes) {
    final found = <_AllName>[];
    for (var pos = 33; pos + 149 < bytes.length; pos++) {
      if ((bytes[pos - 8] != 0x99 && bytes[pos - 8] != 0x9f) ||
          bytes[pos - 10] != 0 || bytes[pos - 9] != 0 ||
          bytes[pos] < 32 || (bytes[pos + 15] & 0x7f) > 3) {
        continue;
      }
      var end = -1;
      var printable = true;
      for (var j = pos; j < pos + 10; j++) {
        if (bytes[j] == 0 && end < 0) end = j;
        if (bytes[j] != 0 && bytes[j] < 32) {
          printable = false;
          break;
        }
      }
      if (!printable) continue;
      if (end < 0) end = pos + 10;
      if (end <= pos) continue;
      final name = _cp1252(bytes.sublist(pos, end));
      if (name.toLowerCase() == 'marker') continue;
      final track = _u16(bytes, pos - 16) + 1;
      if (track < 1 || track > 256) continue;
      found.add(_AllName(
        offset: pos,
        name: name,
        track: track,
        record: _u16(bytes, pos - 18),
      ));
      if (found.length > maxNamedRecords) {
        throw const FormatException('Too many possible ALL track records');
      }
    }
    return found;
  }

  List<_AllName> _findNames(List<_AllName> candidates) {
    var best = -1;
    var bestCount = 0;
    var bestPartMatches = -1;
    for (var start = 0; start < candidates.length; start++) {
      final first = candidates[start];
      if (first.record + 1 != first.track) continue;
      var count = 0;
      while (start + count < candidates.length) {
        final row = candidates[start + count];
        if (row.record != first.record + count ||
            row.track != first.track + count) break;
        count++;
      }
      final defs = <int, String>{
        for (var j = 0; j < count; j++)
          candidates[start + j].track: candidates[start + j].name,
      };
      final lastRecord = candidates[start + count - 1].record;
      var matching = 0;
      for (var j = start + count; j < candidates.length; j++) {
        final row = candidates[j];
        if (row.record > lastRecord &&
            defs[row.track] == row.name) matching++;
      }
      if (count > bestCount ||
          (count == bestCount && matching > bestPartMatches)) {
        best = start;
        bestCount = count;
        bestPartMatches = matching;
      }
    }
    if (best < 0 || bestCount == 0) return const [];
    final result = candidates.sublist(best, best + bestCount);
    final definitions = <int, String>{
      for (final row in result) row.track: row.name,
    };
    final lastRecord = result.last.record;
    for (var i = best + bestCount; i < candidates.length; i++) {
      final row = candidates[i];
      if (row.record > lastRecord &&
          definitions[row.track] == row.name) {
        result.add(row);
      }
    }
    return result;
  }

  LegacyAllTrack? _readCompact(
      Uint8List data, int start, int end, _AllName source) {
    final channel = _channel(data, source);
    final offset = _partPosition(data, source.offset);
    final events = <LegacyAllEvent>[];
    var pos = start;
    var wrap = 0;
    var previousTick = 0;
    while (pos + 6 <= end) {
      final kind = data[pos + 4] & 0xf0;
      final rawTick = _u16(data, pos + 2);
      if (rawTick < previousTick && previousTick - rawTick > 0x8000) {
        wrap += 0x10000;
      }
      previousTick = rawTick;
      final tick = offset + wrap + rawTick;
      final outputTick = _scaleCompact(tick);
      final status = kind | (channel - 1);
      if (kind == 0x80 || kind == 0x90) {
        if (pos + 12 > end) return null;
        var duration = 0;
        final valid = data[pos] < 128 && data[pos + 5] < 128;
        if (valid && kind == 0x90 && data[pos + 5] > 0) {
          final length = _s16(data, pos + 8);
          final scaled = _scaleCompact(tick + length) - outputTick;
          duration = scaled <= 4 ? scaled : scaled - 2;
          if (duration < 1) duration = 1;
        }
        if (valid) {
          events.add(LegacyAllEvent(
            tick: outputTick,
            status: status,
            data1: data[pos],
            data2: data[pos + 5],
            duration: duration,
          ));
        }
        pos += 12;
      } else if (_supportedChannelKind(kind)) {
        final oneByte = kind == 0xc0 || kind == 0xd0;
        if (data[pos] < 128 && (oneByte || data[pos + 5] < 128)) {
          events.add(LegacyAllEvent(
            tick: outputTick,
            status: status,
            data1: data[pos],
            data2: data[pos + 5],
          ));
        }
        pos += 6;
      } else {
        return null;
      }
      if (events.length > maxMidiEvents) {
        throw const FormatException('Excessive compact MIDI events');
      }
    }
    return LegacyAllTrack(
      name: source.name,
      channel: channel,
      trackNumber: source.track,
      layout: 'compact',
      partCount: events.isEmpty ? 0 : 1,
      events: List.unmodifiable(events),
    );
  }

  LegacyAllTrack? _readFixed(
      Uint8List data, _AllName source, int limit) {
    final start = source.offset + 139;
    if (source.offset < 33 || start + 8 > limit) return null;
    final channel = _channel(data, source);
    final partPosition = _partPosition(data, source.offset);
    final events = <LegacyAllEvent>[];
    var pos = start;
    var foundTerminator = false;
    while (pos + 8 <= limit) {
      if (data[pos] == 0xff &&
          data[pos + 1] == 0xff &&
          data[pos + 2] == 0xff) {
        foundTerminator = true;
        break;
      }
      final kind = data[pos + 3] & 0xf0;
      final absoluteTick = partPosition + _u24(data, pos);
      final tick = _scaleFixed(absoluteTick);
      final status = kind | (channel - 1);
      if (kind == 0x80 || kind == 0x90) {
        if (pos + 16 > limit) return null;
        final valid = data[pos + 4] < 128 && data[pos + 5] < 128;
        var duration = 0;
        if (valid && kind == 0x90 && data[pos + 5] > 0) {
          final endTick = _scaleFixed(
                  absoluteTick + _u24(data, pos + 8)) - 2;
          duration = endTick - tick;
          if (duration < 1) duration = 1;
        }
        if (valid) {
          events.add(LegacyAllEvent(
            tick: tick,
            status: status,
            data1: data[pos + 4],
            data2: data[pos + 5],
            duration: duration,
          ));
        }
        pos += 16;
      } else if (_supportedChannelKind(kind)) {
        final oneByte = kind == 0xc0 || kind == 0xd0;
        if (data[pos + 4] < 128 &&
            (oneByte || data[pos + 5] < 128)) {
          events.add(LegacyAllEvent(
            tick: tick,
            status: status,
            data1: data[pos + 4],
            data2: data[pos + 5],
          ));
        }
        pos += 8;
      } else if (data[pos + 3] == 0x0e && pos + 24 <= limit) {
        pos += 24;
      } else {
        return null;
      }
      if (events.length > maxMidiEvents) {
        throw const FormatException('Excessive fixed MIDI events');
      }
    }
    if (!foundTerminator) return null;
    return LegacyAllTrack(
      name: source.name,
      channel: channel,
      trackNumber: source.track,
      layout: 'fixed',
      partCount: events.isEmpty ? 0 : 1,
      events: List.unmodifiable(events),
    );
  }

  List<LegacyAllTimeSignature> _timeSignatures(
      Uint8List data, bool fixedLayout) {
    for (var start = 0; start + 12 <= data.length; start++) {
      if (_u32(data, start) != 0 || !_isTimeSig(data, start)) continue;
      final signatures = <LegacyAllTimeSignature>[];
      var pos = start;
      var previous = -1;
      while (pos + 8 <= data.length) {
        if (_u32(data, pos) == 0x7fffffff) {
          if (signatures.isNotEmpty) return signatures;
          break;
        }
        if (!_isTimeSig(data, pos)) break;
        final raw = _u32(data, pos);
        if (raw < previous) break;
        previous = raw;
        signatures.add(LegacyAllTimeSignature(
          tick: fixedLayout ? _scaleFixed(raw) : _scaleCompact(raw),
          numerator: data[pos + 6],
          denominatorPower: data[pos + 4],
        ));
        if (signatures.length > 4096) {
          throw const FormatException('Excessive time signatures');
        }
        pos += 8;
      }
    }
    return const [
      LegacyAllTimeSignature(tick: 0, numerator: 4, denominatorPower: 2),
    ];
  }

  bool _isTimeSig(Uint8List data, int i) =>
      i + 8 <= data.length &&
      data[i + 4] <= 7 &&
      data[i + 5] == 0 &&
      data[i + 6] >= 1 &&
      data[i + 6] <= 32 &&
      data[i + 7] == 4;

  int _tempoMicros(Uint8List data) {
    if (data.length < 0xa6) return 750000;
    final milliBpm = _u32(data, 0xa2);
    if (milliBpm < 10000 || milliBpm > 400000) return 750000;
    return (60000000000 ~/ milliBpm).clamp(1, 0xffffff);
  }

  int _partPosition(Uint8List data, int offset) =>
      _u24(data, offset - 33);

  int _channel(Uint8List data, _AllName name) {
    var channel = data[name.offset - 5] + 1;
    if (channel < 1 || channel > 16) channel = name.track;
    if (channel < 1 || channel > 16) channel = 1;
    return channel;
  }

  static int _findBytes(
      Uint8List data, List<int> needle, int start, int limit) {
    for (var i = start; i + needle.length <= limit; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (data[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  static bool _supportedChannelKind(int kind) =>
      kind == 0xa0 || kind == 0xb0 || kind == 0xc0 ||
      kind == 0xd0 || kind == 0xe0;

  static int _u16(Uint8List data, int offset) =>
      (data[offset] << 8) | data[offset + 1];

  static int _u24(Uint8List data, int offset) =>
      (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];

  static int _u32(Uint8List data, int offset) =>
      (data[offset] << 24) | (data[offset + 1] << 16) |
      (data[offset + 2] << 8) | data[offset + 3];

  static int _s16(Uint8List data, int offset) {
    final value = _u16(data, offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  static int _scaleCompact(int value) => ((value * 5) + 1) ~/ 4;

  static int _scaleFixed(int value) => (value + 15) ~/ 32;

  static String _cp1252(Uint8List bytes) {
    const chars = <int>[
      0x20ac, 0x0081, 0x201a, 0x0192,
      0x201e, 0x2026, 0x2020, 0x2021,
      0x02c6, 0x2030, 0x0160, 0x2039,
      0x0152, 0x008d, 0x017d, 0x008f,
      0x0090, 0x2018, 0x2019, 0x201c,
      0x201d, 0x2022, 0x2013, 0x2014,
      0x02dc, 0x2122, 0x0161, 0x203a,
      0x0153, 0x009d, 0x017e, 0x0178,
    ];
    return String.fromCharCodes([
      for (final value in bytes)
        if (value >= 0x80 && value <= 0x9f)
          chars[value - 0x80]
        else
          value,
    ]);
  }
}

class LegacyAllEvent {
  const LegacyAllEvent({
    required this.tick,
    required this.status,
    required this.data1,
    required this.data2,
    this.duration = 0,
  });

  final int tick;
  final int status;
  final int data1;
  final int data2;
  final int duration;
}

class LegacyAllTrack {
  const LegacyAllTrack({
    required this.name,
    required this.channel,
    required this.trackNumber,
    required this.layout,
    required this.partCount,
    required this.events,
  });

  final String name;
  final int channel;
  final int trackNumber;
  final String layout;
  final int partCount;
  final List<LegacyAllEvent> events;

  int get noteCount => events.where(
        (e) => (e.status & 0xf0) == 0x90 &&
            e.data2 > 0 && e.duration > 0,
      ).length;
}

class LegacyAllTimeSignature {
  const LegacyAllTimeSignature({
    required this.tick,
    required this.numerator,
    required this.denominatorPower,
  });

  final int tick;
  final int numerator;
  final int denominatorPower;
}

class LegacyAllSong {
  const LegacyAllSong({
    required this.tracks,
    required this.microsecondsPerQuarter,
    required this.signatures,
    required this.warnings,
  });

  final List<LegacyAllTrack> tracks;
  final int microsecondsPerQuarter;
  final List<LegacyAllTimeSignature> signatures;
  final List<String> warnings;

  int get eventCount =>
      tracks.fold(0, (sum, track) => sum + track.events.length);

  int get noteCount =>
      tracks.fold(0, (sum, track) => sum + track.noteCount);

  Map<String, Object?> toJson() => {
    'format': 'cubase-vst-all',
    'decoder': 'native-dart-experimental',
    'tracks': [
      for (final track in tracks)
        {
          'name': track.name,
          'midi_channel': track.channel,
          'track_number': track.trackNumber,
          'parts': track.partCount,
          'layout': track.layout,
          'midi_events': track.events.length,
          'notes': track.noteCount,
        },
    ],
    'total_midi_events': eventCount,
    'total_notes': noteCount,
    'initial_bpm': 60000000 / microsecondsPerQuarter,
    'time_signatures': [
      for (final sig in signatures)
        {
          'tick': sig.tick,
          'numerator': sig.numerator,
          'denominator': 1 << sig.denominatorPower,
        },
    ],
    'warnings': warnings,
    'verified_against_native_cubase': false,
    'vst_state_preserved': false,
  };
}

class _AllName {
  const _AllName({
    required this.offset,
    required this.name,
    required this.track,
    required this.record,
  });

  final int offset;
  final String name;
  final int track;
  final int record;
}
