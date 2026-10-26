import 'dart:convert';
import 'dart:typed_data';

/// Bounded Standard MIDI File framing/event validation without playback.
class MidiFileSummary {
  const MidiFileSummary(
    this.format,
    this.trackCount,
    this.division,
    this.noteCount,
    this.eventCount,
  );
  final int format, trackCount, division, noteCount, eventCount;
  Map<String, Object?> toJson() => {
    'format': format,
    'track_count': trackCount,
    'division': division,
    'note_count': noteCount,
    'event_count': eventCount,
    'validation': 'smf_chunks_and_event_framing',
    'playback_verified': false,
  };
}

class MidiFileValidator {
  static MidiFileSummary inspect(Uint8List bytes) {
    if (bytes.length < 14 || bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('MIDI file outside size limits');
    }
    final view = ByteData.sublistView(bytes);
    bool tag(int at, String name) =>
        at + 4 <= bytes.length &&
        ascii.decode(bytes.sublist(at, at + 4), allowInvalid: true) == name;
    if (!tag(0, 'MThd') || view.getUint32(4) != 6) {
      throw const FormatException('Invalid MIDI header');
    }
    final format = view.getUint16(8),
        count = view.getUint16(10),
        division = view.getUint16(12);
    if (format > 2 ||
        count < 1 ||
        count > 1024 ||
        (format == 0 && count != 1) ||
        division == 0 ||
        (division & 0x8000 != 0 && division & 255 == 0)) {
      throw const FormatException(
        'Invalid MIDI format, track count or division',
      );
    }
    var offset = 14, notes = 0, eventCount = 0;
    for (var track = 0; track < count; track++) {
      if (offset + 8 > bytes.length || !tag(offset, 'MTrk')) {
        throw const FormatException('Missing MIDI track chunk');
      }
      final length = view.getUint32(offset + 4);
      var at = offset + 8;
      final end = at + length;
      if (end > bytes.length) {
        throw const FormatException('Truncated MIDI track');
      }
      var running = 0, ended = false;
      int vlq() {
        var value = 0;
        for (var i = 0; i < 4; i++) {
          if (at >= end) {
            throw const FormatException('Truncated MIDI delta or length');
          }
          final byte = bytes[at++];
          value = (value << 7) | (byte & 127);
          if (byte & 128 == 0) return value;
        }
        throw const FormatException('MIDI VLQ exceeds four bytes');
      }

      while (at < end) {
        vlq();
        if (++eventCount > 1000000 || at >= end) {
          throw const FormatException('Invalid MIDI event count or event');
        }
        var status = bytes[at];
        if (status >= 128) {
          at++;
        } else {
          if (running == 0) {
            throw const FormatException('MIDI running status is missing');
          }
          status = running;
        }
        if (status == 255) {
          if (at >= end) {
            throw const FormatException('Truncated MIDI meta event');
          }
          final kind = bytes[at++], size = vlq();
          if (at + size > end) {
            throw const FormatException('Truncated MIDI meta payload');
          }
          if (kind == 47) {
            if (size != 0 || at != end) {
              throw const FormatException('Invalid MIDI end-of-track');
            }
            ended = true;
            break;
          }
          at += size;
        } else if (status == 240 || status == 247) {
          running = 0;
          final size = vlq();
          if (at + size > end) {
            throw const FormatException('Truncated MIDI SysEx');
          }
          at += size;
        } else if (status >= 128 && status < 240) {
          running = status;
          final kind = status & 0xf0;
          final size = kind == 0xc0 || kind == 0xd0 ? 1 : 2;
          if (at + size > end ||
              bytes.sublist(at, at + size).any((b) => b >= 128)) {
            throw const FormatException('Invalid MIDI channel event');
          }
          if (kind == 0x90 && bytes[at + 1] > 0) notes++;
          at += size;
        } else {
          throw const FormatException('Unsupported MIDI system event in file');
        }
      }
      if (!ended) throw const FormatException('MIDI track lacks end-of-track');
      offset = end;
    }
    if (offset != bytes.length) {
      throw const FormatException('Unexpected trailing MIDI bytes');
    }
    return MidiFileSummary(format, count, division, notes, eventCount);
  }
}
