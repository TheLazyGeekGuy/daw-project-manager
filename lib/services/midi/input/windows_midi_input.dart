import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import 'midi_input.dart';
import 'midi_input_message.dart';

typedef _MidiInProcNative = Void Function(
    IntPtr hMidiIn, Uint32 wMsg, IntPtr instance, IntPtr param1, IntPtr param2);

/// MIDI input on Windows, through the multimedia API (winmm) every Windows
/// has. An input there belongs to one app at a time: one a DAW has open
/// fails here ([MidiInputConnection.failed]), and one this app has open is
/// closed again — for the DAW — as soon as nothing listens to it.
///
/// winmm calls back on a thread of its own; [NativeCallable.listener] hands
/// each message over to Dart's.
class WindowsMidiInput implements MidiInputBackend {
  @override
  Future<List<MidiInputDevice>> devices() async {
    final count = midiInGetNumDevs();
    final caps = calloc<MIDIINCAPS>();
    try {
      final names = <String>[];
      for (var i = 0; i < count; i++) {
        final r = midiInGetDevCaps(i, caps, sizeOf<MIDIINCAPS>());
        names.add(r == MMSYSERR_NOERROR ? caps.ref.szPname : 'MIDI ${i + 1}');
      }
      return [
        for (final (i, name) in distinctDeviceNames(names).indexed)
          MidiInputDevice(id: '$i', name: name),
      ];
    } finally {
      calloc.free(caps);
    }
  }

  @override
  Future<MidiInputConnection> open(List<MidiInputDevice> devices) async {
    final connection = _WindowsConnection();
    for (final device in devices) {
      final index = int.tryParse(device.id);
      if (index == null || !connection._open(device, index)) {
        connection.failed.add(device);
      }
    }
    return connection;
  }
}

class _WindowsConnection implements MidiInputConnection {
  final StreamController<MidiInputPacket> _packets = StreamController();
  final List<({int handle, NativeCallable<_MidiInProcNative> callback})>
      _inputs = [];

  @override
  final List<MidiInputDevice> failed = [];

  @override
  Stream<MidiInputPacket> get packets => _packets.stream;

  bool _open(MidiInputDevice device, int index) {
    final callback = NativeCallable<_MidiInProcNative>.listener(
        (int _, int message, int _, int param1, int _) {
      if (message != MM_MIM_DATA || _packets.isClosed) return;
      final bytes = shortMessageBytes(param1);
      if (bytes.isEmpty) return;
      _packets.add((deviceId: device.id, bytes: Uint8List.fromList(bytes)));
    });
    final handle = calloc<IntPtr>();
    try {
      final r = midiInOpen(handle, index, callback.nativeFunction.address, 0,
          CALLBACK_FUNCTION);
      if (r != MMSYSERR_NOERROR) {
        debugPrint('[MidiInput] ${device.name} would not open: $r');
        callback.close();
        return false;
      }
      midiInStart(handle.value);
      _inputs.add((handle: handle.value, callback: callback));
      return true;
    } finally {
      calloc.free(handle);
    }
  }

  @override
  Future<void> close() async {
    for (final input in _inputs) {
      midiInStop(input.handle);
      midiInReset(input.handle);
      midiInClose(input.handle);
      // Only now: winmm calls back while closing, and a callback closed
      // under it would crash.
      input.callback.close();
    }
    _inputs.clear();
    // Not awaited: it only completes once a listener has seen the end,
    // and the packets may never have been listened to.
    unawaited(_packets.close());
  }
}
