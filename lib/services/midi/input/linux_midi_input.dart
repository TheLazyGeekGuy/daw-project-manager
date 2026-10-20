import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'midi_input.dart';

/// MIDI input on Linux, through the ALSA sequencer (libasound), which every
/// desktop has and which lets several apps listen to one keyboard at once —
/// a DAW keeps it while this app hears it too.
///
/// Listening runs on an isolate of its own, waiting in `poll()` for the
/// sequencer, so a key reaches the app as soon as it's pressed without the
/// UI thread ever blocking or polling.
///
/// Without libasound, or without `/dev/snd/seq` (a sandbox that doesn't
/// grant it), there are simply no inputs.
class LinuxMidiInput implements MidiInputBackend {
  @override
  Future<List<MidiInputDevice>> devices() async {
    try {
      final alsa = _Alsa.open();
      return alsa.withSeq<List<MidiInputDevice>>(_kOpenInput, alsa.inputs) ??
          const [];
    } catch (e) {
      debugPrint('[MidiInput] ALSA unavailable: $e');
      return const [];
    }
  }

  @override
  Future<MidiInputConnection> open(List<MidiInputDevice> devices) async {
    final connection = _LinuxConnection(devices);
    await connection._start();
    return connection;
  }
}

/// Whether a sequencer port is one to offer as an input: something can
/// read it and subscribe to it, it is not hidden, and it is not the
/// system's own announcements or the "Midi Through" loopback every Linux
/// has.
bool isOfferedAlsaPort({
  required int client,
  required int capability,
  required String clientName,
}) {
  const read = 1 << 0, subsRead = 1 << 5, noExport = 1 << 7;
  if (client == 0) return false; // System: timer and announcements.
  if (capability & read == 0 || capability & subsRead == 0) return false;
  if (capability & noExport != 0) return false;
  return clientName != 'Midi Through';
}

const _kOpenInput = 2; // SND_SEQ_OPEN_INPUT
const _kNonBlock = 1; // SND_SEQ_NONBLOCK
const _kPollIn = 1; // POLLIN
const _kENoSpace = -28; // -ENOSPC: the input buffer overran.

class _LinuxConnection implements MidiInputConnection {
  _LinuxConnection(this._devices);

  final List<MidiInputDevice> _devices;
  final StreamController<MidiInputPacket> _packets = StreamController();
  final Pointer<Int32> _stop = calloc<Int32>();
  ReceivePort? _port;
  Completer<void>? _exited;

  @override
  final List<MidiInputDevice> failed = [];

  @override
  Stream<MidiInputPacket> get packets => _packets.stream;

  Future<void> _start() async {
    final port = ReceivePort();
    _port = port;
    final exited = Completer<void>();
    _exited = exited;
    final ready = Completer<List<String>>();
    port.listen((message) {
      if (message is _Packet) {
        if (!_packets.isClosed) {
          _packets.add((deviceId: message.source, bytes: message.bytes));
        }
      } else if (message is _Ready) {
        if (!ready.isCompleted) ready.complete(message.failedIds);
      } else if (message == null || message is List) {
        // The isolate ended (null), or failed (an error and its stack).
        if (message is List) debugPrint('[MidiInput] listening failed: $message');
        if (!ready.isCompleted) {
          ready.complete([for (final d in _devices) d.id]);
        }
        if (!exited.isCompleted) exited.complete();
      }
    });
    try {
      await Isolate.spawn(
        _listen,
        _ListenArgs(
          port.sendPort,
          _stop.address,
          [for (final d in _devices) d.id],
        ),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
    } catch (e) {
      debugPrint('[MidiInput] could not start listening: $e');
      if (!exited.isCompleted) exited.complete();
      if (!ready.isCompleted) ready.complete([for (final d in _devices) d.id]);
    }
    final failedIds = await ready.future;
    failed.addAll(_devices.where((d) => failedIds.contains(d.id)));
  }

  @override
  Future<void> close() async {
    _stop.value = 1;
    // Wakes from poll() within its timeout, closes the sequencer and exits.
    await _exited?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    _port?.close();
    calloc.free(_stop);
    // Not awaited: it only completes once a listener has seen the end,
    // and the packets may never have been listened to.
    unawaited(_packets.close());
  }
}

class _ListenArgs {
  const _ListenArgs(this.port, this.stopAddress, this.sources);

  final SendPort port;
  final int stopAddress;

  /// "client:port" of each input.
  final List<String> sources;
}

class _Ready {
  const _Ready(this.failedIds);
  final List<String> failedIds;
}

class _Packet {
  const _Packet(this.source, this.bytes);
  final String source;
  final Uint8List bytes;
}

/// The listening isolate: subscribes to [args]' inputs and sends on what
/// they play, until the stop flag is set.
void _listen(_ListenArgs args) {
  final stop = Pointer<Int32>.fromAddress(args.stopAddress);
  final _Alsa alsa;
  try {
    alsa = _Alsa.open();
  } catch (_) {
    args.port.send(_Ready(args.sources));
    return;
  }
  final seqOut = calloc<Pointer<Void>>();
  final eventOut = calloc<Pointer<Uint8>>();
  final decoderOut = calloc<Pointer<Void>>();
  final buffer = calloc<Uint8>(256);
  final seqName = 'default'.toNativeUtf8();
  final clientName = 'DAW Project Manager'.toNativeUtf8();
  final portName = 'MIDI in'.toNativeUtf8();
  try {
    if (alsa.seqOpen(seqOut, seqName, _kOpenInput, _kNonBlock) < 0) {
      args.port.send(_Ready(args.sources));
      return;
    }
    final seq = seqOut.value;
    // How the app shows up in other apps' lists of connections.
    alsa.setClientName(seq, clientName);
    const capWrite = 1 << 1, capSubsWrite = 1 << 6;
    const typeMidiGeneric = 1 << 1, typeApplication = 1 << 20;
    final myPort = alsa.createSimplePort(
      seq,
      portName,
      capWrite | capSubsWrite,
      typeMidiGeneric | typeApplication,
    );
    final failed = <String>[];
    for (final id in args.sources) {
      final parts = id.split(':');
      final client = int.tryParse(parts.first);
      final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (myPort < 0 ||
          client == null ||
          port == null ||
          alsa.connectFrom(seq, myPort, client, port) < 0) {
        failed.add(id);
      }
    }
    args.port.send(_Ready(failed));

    alsa.midiEventNew(256, decoderOut);
    final decoder = decoderOut.value;
    final count = alsa.pollDescriptorsCount(seq, _kPollIn);
    final fds = calloc<Uint8>(8 * (count < 1 ? 1 : count)); // struct pollfd
    alsa.pollDescriptors(seq, fds.cast(), count, _kPollIn);
    try {
      while (stop.value == 0) {
        if (alsa.poll(fds.cast(), count, 100) <= 0) continue;
        // Everything waiting, until the sequencer has nothing more.
        while (stop.value == 0) {
          final r = alsa.eventInput(seq, eventOut);
          if (r == _kENoSpace) continue; // Overrun: events were lost; go on.
          if (r < 0) break; // -EAGAIN: none left.
          final event = eventOut.value;
          if (event == nullptr) break;
          // Not MIDI (a subscription announced, say): nothing decoded.
          final n = alsa.midiEventDecode(decoder, buffer, 256, event.cast());
          if (n <= 0) continue;
          // snd_seq_event_t: type, flags, tag, queue, 8 bytes of time,
          // then the source's client and port.
          args.port.send(_Packet('${event[12]}:${event[13]}',
              Uint8List.fromList(buffer.asTypedList(n))));
        }
      }
    } finally {
      calloc.free(fds);
      if (decoder != nullptr) alsa.midiEventFree(decoder);
      alsa.seqClose(seq);
    }
  } finally {
    calloc.free(seqOut);
    calloc.free(eventOut);
    calloc.free(decoderOut);
    calloc.free(buffer);
    calloc.free(seqName);
    calloc.free(clientName);
    calloc.free(portName);
  }
}

/// The few libasound (and libc) functions the sequencer needs.
class _Alsa {
  _Alsa._(DynamicLibrary lib)
      : seqOpen = lib.lookupFunction<
            Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>, Int32, Int32),
            int Function(
                Pointer<Pointer<Void>>, Pointer<Utf8>, int, int)>('snd_seq_open'),
        seqClose = lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('snd_seq_close'),
        clientId = lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('snd_seq_client_id'),
        setClientName = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>)>('snd_seq_set_client_name'),
        createSimplePort = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32, Uint32),
            int Function(Pointer<Void>, Pointer<Utf8>, int,
                int)>('snd_seq_create_simple_port'),
        connectFrom = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Int32, Int32),
            int Function(Pointer<Void>, int, int, int)>('snd_seq_connect_from'),
        clientInfoMalloc = lib.lookupFunction<
            Int32 Function(Pointer<Pointer<Void>>),
            int Function(Pointer<Pointer<Void>>)>('snd_seq_client_info_malloc'),
        clientInfoFree = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('snd_seq_client_info_free'),
        clientInfoSetClient = lib.lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)>('snd_seq_client_info_set_client'),
        clientInfoGetClient = lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('snd_seq_client_info_get_client'),
        clientInfoGetName = lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)>('snd_seq_client_info_get_name'),
        queryNextClient = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>)>('snd_seq_query_next_client'),
        portInfoMalloc = lib.lookupFunction<
            Int32 Function(Pointer<Pointer<Void>>),
            int Function(Pointer<Pointer<Void>>)>('snd_seq_port_info_malloc'),
        portInfoFree = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('snd_seq_port_info_free'),
        portInfoSetClient = lib.lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)>('snd_seq_port_info_set_client'),
        portInfoSetPort = lib.lookupFunction<Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)>('snd_seq_port_info_set_port'),
        portInfoGetPort = lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('snd_seq_port_info_get_port'),
        portInfoGetName = lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)>('snd_seq_port_info_get_name'),
        portInfoGetCapability = lib.lookupFunction<
            Uint32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('snd_seq_port_info_get_capability'),
        queryNextPort = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>)>('snd_seq_query_next_port'),
        pollDescriptorsCount = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Int16),
            int Function(Pointer<Void>, int)>('snd_seq_poll_descriptors_count'),
        pollDescriptors = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Int16),
            int Function(
                Pointer<Void>, Pointer<Void>, int, int)>('snd_seq_poll_descriptors'),
        eventInput = lib.lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Pointer<Uint8>>),
            int Function(
                Pointer<Void>, Pointer<Pointer<Uint8>>)>('snd_seq_event_input'),
        midiEventNew = lib.lookupFunction<
            Int32 Function(IntPtr, Pointer<Pointer<Void>>),
            int Function(int, Pointer<Pointer<Void>>)>('snd_midi_event_new'),
        midiEventFree = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('snd_midi_event_free'),
        midiEventDecode = lib.lookupFunction<
            Long Function(Pointer<Void>, Pointer<Uint8>, Long, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Uint8>, int,
                Pointer<Void>)>('snd_midi_event_decode'),
        poll = DynamicLibrary.process().lookupFunction<
            Int32 Function(Pointer<Void>, UnsignedLong, Int32),
            int Function(Pointer<Void>, int, int)>('poll');

  factory _Alsa.open() => _Alsa._(DynamicLibrary.open('libasound.so.2'));

  final int Function(Pointer<Pointer<Void>>, Pointer<Utf8>, int, int) seqOpen;
  final int Function(Pointer<Void>) seqClose;
  final int Function(Pointer<Void>) clientId;
  final int Function(Pointer<Void>, Pointer<Utf8>) setClientName;
  final int Function(Pointer<Void>, Pointer<Utf8>, int, int) createSimplePort;
  final int Function(Pointer<Void>, int, int, int) connectFrom;
  final int Function(Pointer<Pointer<Void>>) clientInfoMalloc;
  final void Function(Pointer<Void>) clientInfoFree;
  final void Function(Pointer<Void>, int) clientInfoSetClient;
  final int Function(Pointer<Void>) clientInfoGetClient;
  final Pointer<Utf8> Function(Pointer<Void>) clientInfoGetName;
  final int Function(Pointer<Void>, Pointer<Void>) queryNextClient;
  final int Function(Pointer<Pointer<Void>>) portInfoMalloc;
  final void Function(Pointer<Void>) portInfoFree;
  final void Function(Pointer<Void>, int) portInfoSetClient;
  final void Function(Pointer<Void>, int) portInfoSetPort;
  final int Function(Pointer<Void>) portInfoGetPort;
  final Pointer<Utf8> Function(Pointer<Void>) portInfoGetName;
  final int Function(Pointer<Void>) portInfoGetCapability;
  final int Function(Pointer<Void>, Pointer<Void>) queryNextPort;
  final int Function(Pointer<Void>, int) pollDescriptorsCount;
  final int Function(Pointer<Void>, Pointer<Void>, int, int) pollDescriptors;
  final int Function(Pointer<Void>, Pointer<Pointer<Uint8>>) eventInput;
  final int Function(int, Pointer<Pointer<Void>>) midiEventNew;
  final void Function(Pointer<Void>) midiEventFree;
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
      midiEventDecode;
  final int Function(Pointer<Void>, int, int) poll;

  /// Runs [body] with a sequencer opened for [streams]; null when it won't
  /// open.
  T? withSeq<T>(int streams, T Function(Pointer<Void> seq) body) {
    final out = calloc<Pointer<Void>>();
    final name = 'default'.toNativeUtf8();
    try {
      if (seqOpen(out, name, streams, _kNonBlock) < 0) return null;
      try {
        return body(out.value);
      } finally {
        seqClose(out.value);
      }
    } finally {
      calloc.free(out);
      calloc.free(name);
    }
  }

  /// Every port [isOfferedAlsaPort] would offer, named by the port (its
  /// device's name, as a DAW lists it).
  List<MidiInputDevice> inputs(Pointer<Void> seq) {
    final own = clientId(seq);
    final clientOut = calloc<Pointer<Void>>();
    final portOut = calloc<Pointer<Void>>();
    try {
      if (clientInfoMalloc(clientOut) < 0 || portInfoMalloc(portOut) < 0) {
        return const [];
      }
      final ci = clientOut.value, pi = portOut.value;
      try {
        final found = <MidiInputDevice>[];
        clientInfoSetClient(ci, -1);
        while (queryNextClient(seq, ci) >= 0) {
          final client = clientInfoGetClient(ci);
          if (client == own) continue;
          final clientName = clientInfoGetName(ci).toDartString();
          portInfoSetClient(pi, client);
          portInfoSetPort(pi, -1);
          while (queryNextPort(seq, pi) >= 0) {
            if (!isOfferedAlsaPort(
              client: client,
              capability: portInfoGetCapability(pi),
              clientName: clientName,
            )) {
              continue;
            }
            found.add(MidiInputDevice(
              id: '$client:${portInfoGetPort(pi)}',
              name: portInfoGetName(pi).toDartString(),
            ));
          }
        }
        final names = distinctDeviceNames([for (final d in found) d.name]);
        return [
          for (final (i, d) in found.indexed)
            MidiInputDevice(id: d.id, name: names[i]),
        ];
      } finally {
        clientInfoFree(ci);
        portInfoFree(pi);
      }
    } finally {
      calloc.free(clientOut);
      calloc.free(portOut);
    }
  }
}
