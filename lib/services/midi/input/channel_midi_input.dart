import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'midi_input.dart';

/// MIDI input through the app's own native code: CoreMIDI on macOS and iOS
/// (`MidiInputBridge` in `MainFlutterWindow.swift` / `AppDelegate.swift`),
/// android.media.midi on Android (`MidiInputBridge.kt`).
///
/// The native side keeps one set of open inputs: `open` replaces it,
/// `close` empties it. A platform without it — or a phone without MIDI —
/// simply has no inputs.
class ChannelMidiInput implements MidiInputBackend {
  ChannelMidiInput({
    MethodChannel methods = const MethodChannel(methodChannelName),
    EventChannel events = const EventChannel(eventChannelName),
  })  : _methods = methods,
        _events = events;

  static const methodChannelName = 'com.bandpassrecords.dpm/midi_input';
  static const eventChannelName = 'com.bandpassrecords.dpm/midi_input/events';

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Future<List<MidiInputDevice>> devices() async {
    try {
      final list = await _methods.invokeListMethod<Object?>('devices') ?? [];
      final found = [
        for (final entry in list)
          if (entry case {'id': final String id, 'name': final String name})
            MidiInputDevice(id: id, name: name),
      ];
      final names = distinctDeviceNames([for (final d in found) d.name]);
      return [
        for (final (i, d) in found.indexed)
          MidiInputDevice(id: d.id, name: names[i]),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[MidiInput] listing inputs failed: $e');
      return const [];
    }
  }

  @override
  Future<MidiInputConnection> open(List<MidiInputDevice> devices) async {
    final connection = _ChannelConnection(_methods);
    // Listening before opening, so nothing played straight away is lost.
    connection._subscription =
        _events.receiveBroadcastStream().listen((event) {
      if (event case {'id': final String id, 'bytes': final Uint8List bytes}) {
        if (!connection._packets.isClosed) {
          connection._packets.add((deviceId: id, bytes: bytes));
        }
      }
    }, onError: (Object e) => debugPrint('[MidiInput] $e'));
    List<String> failedIds;
    try {
      failedIds = await _methods.invokeListMethod<String>(
            'open',
            {'ids': [for (final d in devices) d.id]},
          ) ??
          const [];
    } on MissingPluginException {
      failedIds = [for (final d in devices) d.id];
    } on PlatformException catch (e) {
      debugPrint('[MidiInput] opening inputs failed: $e');
      failedIds = [for (final d in devices) d.id];
    }
    connection.failed.addAll(devices.where((d) => failedIds.contains(d.id)));
    return connection;
  }
}

class _ChannelConnection implements MidiInputConnection {
  _ChannelConnection(this._methods);

  final MethodChannel _methods;
  final StreamController<MidiInputPacket> _packets = StreamController();
  StreamSubscription<Object?>? _subscription;

  @override
  final List<MidiInputDevice> failed = [];

  @override
  Stream<MidiInputPacket> get packets => _packets.stream;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    try {
      await _methods.invokeMethod<void>('close');
    } on MissingPluginException {
      // Nothing was open.
    } on PlatformException catch (e) {
      debugPrint('[MidiInput] closing inputs failed: $e');
    }
    // Not awaited: it only completes once a listener has seen the end,
    // and the packets may never have been listened to.
    unawaited(_packets.close());
  }
}
