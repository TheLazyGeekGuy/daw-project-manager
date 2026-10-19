import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'channel_midi_input.dart';
import 'linux_midi_input.dart';
import 'midi_input_message.dart';
import 'windows_midi_input.dart';

/// A MIDI input the system offers: a keyboard, a pad controller, a virtual
/// port. [id] is only good for this run of the app; [name] is what a choice
/// is remembered by.
@immutable
class MidiInputDevice {
  const MidiInputDevice({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is MidiInputDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'MidiInputDevice($id, $name)';
}

/// Bytes from one input, as they arrived.
typedef MidiInputPacket = ({String deviceId, Uint8List bytes});

/// The inputs a [MidiInputBackend.open] is listening to.
abstract class MidiInputConnection {
  /// Everything the inputs send, raw.
  Stream<MidiInputPacket> get packets;

  /// The inputs that couldn't be opened — on Windows, usually because
  /// another app (a DAW) has them.
  List<MidiInputDevice> get failed;

  /// Stops listening and lets the inputs go, for other apps to use.
  Future<void> close();
}

/// How this platform reads MIDI inputs.
abstract class MidiInputBackend {
  /// The inputs connected now; empty when there are none, or the platform
  /// can't be asked (no ALSA, no MIDI on this phone).
  Future<List<MidiInputDevice>> devices();

  /// Starts listening to [devices]. Never throws for an input that won't
  /// open: it is in [MidiInputConnection.failed].
  Future<MidiInputConnection> open(List<MidiInputDevice> devices);

  /// The backend for the platform the app runs on.
  static MidiInputBackend forPlatform() {
    if (Platform.isWindows) return WindowsMidiInput();
    if (Platform.isLinux) return LinuxMidiInput();
    return ChannelMidiInput();
  }
}

/// Which input the piano roll listens to: none, all of them, or one by
/// name. Device-local, like the preview volume: it names this machine's
/// hardware.
@immutable
class MidiInputChoice {
  const MidiInputChoice._(this._stored);

  static const off = MidiInputChoice._('');
  static const all = MidiInputChoice._('*');

  /// The input called [name].
  factory MidiInputChoice.named(String name) =>
      name.isEmpty || name == '*' ? off : MidiInputChoice._(name);

  /// Read back from [stored]; anything unreadable is [off].
  factory MidiInputChoice.parse(String? stored) => switch (stored) {
        null || '' => off,
        '*' => all,
        final name => MidiInputChoice._(name),
      };

  final String _stored;

  /// How it is kept.
  String get stored => _stored;

  bool get isOff => _stored.isEmpty;
  bool get isAll => _stored == '*';

  /// The input's name, for a choice of one.
  String? get name => isOff || isAll ? null : _stored;

  /// The inputs of [available] this choice listens to. One chosen by name
  /// that isn't plugged in: none.
  List<MidiInputDevice> pick(List<MidiInputDevice> available) {
    if (isOff) return const [];
    if (isAll) return available;
    return [
      for (final d in available)
        if (d.name == _stored) d,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is MidiInputChoice && other._stored == _stored;

  @override
  int get hashCode => _stored.hashCode;

  @override
  String toString() => 'MidiInputChoice($_stored)';
}

/// Listening to the inputs a [MidiInputChoice] picks, as one stream of
/// messages — each input parsed on its own, since running status belongs
/// to the input it came from.
class MidiInputSession {
  MidiInputSession._(this._connection, this.devices) {
    _subscription = _connection.packets.listen((packet) {
      final parser =
          _parsers.putIfAbsent(packet.deviceId, MidiByteParser.new);
      for (final message in parser.add(packet.bytes)) {
        _messages.add(message);
      }
    }, onError: (Object e) => debugPrint('[MidiInput] $e'));
  }

  /// Opens what [choice] picks among [backend]'s inputs. Null when it picks
  /// none — nothing plugged in, or off.
  static Future<MidiInputSession?> start(
    MidiInputBackend backend,
    MidiInputChoice choice,
  ) async {
    final List<MidiInputDevice> available;
    try {
      available = await backend.devices();
    } catch (e) {
      debugPrint('[MidiInput] listing inputs failed: $e');
      return null;
    }
    final picked = choice.pick(available);
    if (picked.isEmpty) return null;
    final connection = await backend.open(picked);
    return MidiInputSession._(connection, picked);
  }

  final MidiInputConnection _connection;
  late final StreamSubscription<MidiInputPacket> _subscription;
  final Map<String, MidiByteParser> _parsers = {};
  final StreamController<MidiInputMessage> _messages =
      StreamController.broadcast(sync: true);

  /// The inputs it set out to open.
  final List<MidiInputDevice> devices;

  /// Those that couldn't be.
  List<MidiInputDevice> get failed => _connection.failed;

  /// The inputs actually listened to.
  List<MidiInputDevice> get listening =>
      [for (final d in devices) if (!failed.contains(d)) d];

  Stream<MidiInputMessage> get messages => _messages.stream;

  /// Lets the inputs go first — on Windows another app may be waiting for
  /// them — then stops parsing.
  Future<void> close() async {
    await _connection.close();
    await _subscription.cancel();
    // Not awaited: a broadcast stream's close only completes once its
    // listeners have seen the end, and they may have gone already.
    unawaited(_messages.close());
  }
}

/// [names] with repeats told apart — two of the same keyboard become
/// "KeyStep" and "KeyStep (2)" — so a choice remembered by name picks one.
List<String> distinctDeviceNames(List<String> names) {
  final seen = <String, int>{};
  return [
    for (final name in names)
      switch (seen.update(name, (n) => n + 1, ifAbsent: () => 1)) {
        1 => name,
        final n => '$name ($n)',
      },
  ];
}
