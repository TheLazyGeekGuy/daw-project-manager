import 'dart:async';
import 'dart:typed_data';

import 'package:daw_project_manager/services/midi/input/midi_input.dart';

/// MIDI inputs for tests: [play] sends bytes as if a key were pressed on
/// the input with that id.
class FakeMidiInput implements MidiInputBackend {
  FakeMidiInput(
    this.available, {
    this.busy = const {},
    this.listingFails = false,
  });

  List<MidiInputDevice> available;

  /// Ids of inputs another app has: they fail to open.
  final Set<String> busy;
  final bool listingFails;

  /// What each [open] asked for.
  final List<List<MidiInputDevice>> opened = [];
  final List<FakeMidiConnection> connections = [];

  @override
  Future<List<MidiInputDevice>> devices() async {
    if (listingFails) throw StateError('no MIDI here');
    return available;
  }

  @override
  Future<MidiInputConnection> open(List<MidiInputDevice> devices) async {
    opened.add(devices);
    final connection = FakeMidiConnection()
      ..failed.addAll(devices.where((d) => busy.contains(d.id)));
    connections.add(connection);
    return connection;
  }

  /// [bytes] from input [deviceId], on the newest connection still open.
  void play(String deviceId, List<int> bytes) {
    final open = connections.lastWhere((c) => !c.closed);
    open._packets
        .add((deviceId: deviceId, bytes: Uint8List.fromList(bytes)));
  }
}

class FakeMidiConnection implements MidiInputConnection {
  final StreamController<MidiInputPacket> _packets = StreamController();
  bool closed = false;

  @override
  final List<MidiInputDevice> failed = [];

  @override
  Stream<MidiInputPacket> get packets => _packets.stream;

  @override
  Future<void> close() async {
    closed = true;
    // Not awaited: it only completes once a listener has seen the end,
    // and the packets may never have been listened to.
    unawaited(_packets.close());
  }
}
