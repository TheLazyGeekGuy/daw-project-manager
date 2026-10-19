/// What a MIDI controller sent: a key, a knob, the bend wheel.
enum MidiInputKind {
  noteOn,
  noteOff,
  polyPressure,
  controller,
  program,
  channelPressure,
  pitchBend,
}

/// One channel message from a MIDI input. A note-on at velocity 0 arrives
/// as the note-off it means.
class MidiInputMessage {
  const MidiInputMessage({
    required this.kind,
    required this.channel,
    this.data1 = 0,
    this.data2 = 0,
  });

  final MidiInputKind kind;

  /// 0…15.
  final int channel;

  /// The key of a note or of poly pressure, a controller's number, a
  /// program; 0 otherwise.
  final int data1;

  /// A note's velocity, a controller's or pressure's value; a pitch bend's
  /// whole 14-bit value (8192: no bend).
  final int data2;

  /// The key, for a note.
  int get pitch => data1;

  int get velocity => data2;

  @override
  bool operator ==(Object other) =>
      other is MidiInputMessage &&
      other.kind == kind &&
      other.channel == channel &&
      other.data1 == data1 &&
      other.data2 == data2;

  @override
  int get hashCode => Object.hash(kind, channel, data1, data2);

  @override
  String toString() => 'MidiInputMessage($kind, ch $channel, $data1, $data2)';
}

/// Turns the bytes a MIDI input delivers into messages, whatever pieces
/// they come in: running status (a status byte left out because it's the
/// same as the last one's), a message split across two deliveries, clock
/// and other real-time bytes dropped in anywhere — even inside a message —
/// and system exclusive dumps, which are skipped.
///
/// One parser per input: running status belongs to the stream it is in.
class MidiByteParser {
  /// The channel status the data bytes belong to; null before any, and
  /// after a system message (which cancels running status).
  int? _status;
  final List<int> _data = [];
  bool _inSysex = false;

  /// System common messages being skipped, and how many data bytes are left.
  int _skipping = 0;

  /// The complete messages [bytes] finished.
  List<MidiInputMessage> add(Iterable<int> bytes) {
    final out = <MidiInputMessage>[];
    for (final raw in bytes) {
      final b = raw & 0xFF;
      if (b >= 0xF8) continue; // Real-time: clock, start, stop, active sensing.
      if (b == 0xF0) {
        _inSysex = true;
        _status = null;
        _data.clear();
        continue;
      }
      if (b == 0xF7) {
        _inSysex = false;
        continue;
      }
      if (b >= 0x80) {
        // Any other status ends a dump that was never closed.
        _inSysex = false;
        _data.clear();
        if (b >= 0xF0) {
          _status = null;
          _skipping = switch (b) {
            0xF1 || 0xF3 => 1, // MTC quarter frame, song select.
            0xF2 => 2, // Song position.
            _ => 0, // Tune request, undefined.
          };
        } else {
          _status = b;
          _skipping = 0;
        }
        continue;
      }
      if (_inSysex) continue;
      if (_skipping > 0) {
        _skipping--;
        continue;
      }
      final status = _status;
      if (status == null) continue; // Data with nothing to belong to.
      _data.add(b);
      if (_data.length < _dataLength(status)) continue;
      out.add(_message(status, _data));
      _data.clear();
    }
    return out;
  }

  static int _dataLength(int status) => switch (status & 0xF0) {
        0xC0 || 0xD0 => 1,
        _ => 2,
      };

  static MidiInputMessage _message(int status, List<int> data) {
    final channel = status & 0x0F;
    final d1 = data[0];
    final d2 = data.length > 1 ? data[1] : 0;
    return switch (status & 0xF0) {
      0x90 when d2 > 0 => MidiInputMessage(
          kind: MidiInputKind.noteOn, channel: channel, data1: d1, data2: d2),
      0x90 || 0x80 => MidiInputMessage(
          kind: MidiInputKind.noteOff, channel: channel, data1: d1, data2: d2),
      0xA0 => MidiInputMessage(
          kind: MidiInputKind.polyPressure,
          channel: channel,
          data1: d1,
          data2: d2),
      0xB0 => MidiInputMessage(
          kind: MidiInputKind.controller, channel: channel, data1: d1, data2: d2),
      0xC0 => MidiInputMessage(
          kind: MidiInputKind.program, channel: channel, data1: d1),
      0xD0 => MidiInputMessage(
          kind: MidiInputKind.channelPressure, channel: channel, data2: d1),
      _ => MidiInputMessage(
          kind: MidiInputKind.pitchBend,
          channel: channel,
          data2: d1 | (d2 << 7)),
    };
  }
}

/// The bytes of a Windows short message ([packed]: status in the low byte,
/// then the first and second data bytes) — as many as its status has.
List<int> shortMessageBytes(int packed) {
  final status = packed & 0xFF;
  final d1 = (packed >> 8) & 0x7F;
  final d2 = (packed >> 16) & 0x7F;
  if (status < 0x80) return const [];
  if (status >= 0xF8 || status == 0xF6) return [status];
  return switch (status & 0xF0) {
    0xC0 || 0xD0 => [status, d1],
    0xF0 => switch (status) {
        0xF1 || 0xF3 => [status, d1],
        0xF2 => [status, d1, d2],
        _ => [status],
      },
    _ => [status, d1, d2],
  };
}
