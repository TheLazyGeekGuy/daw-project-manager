import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/midi/input/channel_midi_input.dart';
import 'package:daw_project_manager/services/midi/input/linux_midi_input.dart';
import 'package:daw_project_manager/services/midi/input/midi_input.dart';
import 'package:daw_project_manager/services/midi/input/midi_input_message.dart';
import 'package:daw_project_manager/services/midi/input/windows_midi_input.dart';
import 'package:daw_project_manager/services/midi_editor_prefs_store.dart';

import '../../../helpers/hive_test_helper.dart';
import '../../../helpers/fake_midi_input.dart';

const keyStep = MidiInputDevice(id: '0', name: 'KeyStep');
const pads = MidiInputDevice(id: '1', name: 'Pads');

void main() {
  group('MidiInputChoice', () {
    test('is kept as text and read back', () {
      for (final choice in [
        MidiInputChoice.off,
        MidiInputChoice.all,
        MidiInputChoice.named('KeyStep'),
      ]) {
        expect(MidiInputChoice.parse(choice.stored), choice);
      }
    });

    test('nothing stored is off', () {
      // A fresh install must not grab every input on Windows, where an
      // input open here is one the DAW can't have.
      expect(MidiInputChoice.parse(null), MidiInputChoice.off);
      expect(MidiInputChoice.parse(''), MidiInputChoice.off);
    });

    test('a name that could be mistaken for off or all is neither', () {
      expect(MidiInputChoice.named(''), MidiInputChoice.off);
      expect(MidiInputChoice.named('*'), MidiInputChoice.off);
    });

    test('picks what it names among the inputs plugged in', () {
      expect(MidiInputChoice.off.pick([keyStep, pads]), isEmpty);
      expect(MidiInputChoice.all.pick([keyStep, pads]), [keyStep, pads]);
      expect(MidiInputChoice.named('Pads').pick([keyStep, pads]), [pads]);
    });

    test('one chosen by name and not plugged in picks nothing', () {
      expect(MidiInputChoice.named('Launchkey').pick([keyStep, pads]), isEmpty);
    });

    test('is remembered by name, not by this run\'s id', () {
      // Ids change between runs (Windows numbers inputs as they're found).
      const moved = MidiInputDevice(id: '3', name: 'KeyStep');
      expect(MidiInputChoice.named('KeyStep').pick([pads, moved]), [moved]);
    });
  });

  group('distinctDeviceNames', () {
    test('tells two of the same keyboard apart', () {
      expect(distinctDeviceNames(['KeyStep', 'Pads', 'KeyStep', 'KeyStep']),
          ['KeyStep', 'Pads', 'KeyStep (2)', 'KeyStep (3)']);
    });

    test('leaves different names alone', () {
      expect(distinctDeviceNames(['A', 'B']), ['A', 'B']);
    });
  });

  group('MidiInputSession', () {
    test('opens what the choice picks and parses what it plays', () async {
      final backend = FakeMidiInput([keyStep, pads]);
      final session =
          await MidiInputSession.start(backend, MidiInputChoice.named('Pads'));
      expect(session, isNotNull);
      expect(backend.opened.single, [pads]);
      final heard = <MidiInputMessage>[];
      session!.messages.listen(heard.add);
      backend.play('1', [0x90, 36, 100]);
      await pumpEventQueue();
      expect(heard.single.kind, MidiInputKind.noteOn);
      expect(heard.single.pitch, 36);
      await session.close();
    });

    test('running status is kept per input, never mixed between two',
        () async {
      final backend = FakeMidiInput([keyStep, pads]);
      final session =
          (await MidiInputSession.start(backend, MidiInputChoice.all))!;
      final heard = <MidiInputMessage>[];
      session.messages.listen(heard.add);
      backend.play('0', [0x90, 60, 100]);
      backend.play('1', [0xB0, 1, 64]); // The pads: a controller.
      backend.play('0', [62, 100]); // The keyboard's running status: a note.
      await pumpEventQueue();
      expect([for (final m in heard) m.kind], [
        MidiInputKind.noteOn,
        MidiInputKind.controller,
        MidiInputKind.noteOn,
      ]);
      expect(heard.last.pitch, 62);
      await session.close();
    });

    test('nothing to open: no session', () async {
      final backend = FakeMidiInput([keyStep]);
      expect(await MidiInputSession.start(backend, MidiInputChoice.off), isNull);
      expect(
          await MidiInputSession.start(
              backend, MidiInputChoice.named('Gone')),
          isNull);
      expect(backend.opened, isEmpty);
    });

    test('an input that wouldn\'t open is told apart from those listening',
        () async {
      final backend = FakeMidiInput([keyStep, pads], busy: {'0'});
      final session =
          (await MidiInputSession.start(backend, MidiInputChoice.all))!;
      expect(session.failed, [keyStep]);
      expect(session.listening, [pads]);
      await session.close();
    });

    test('closing lets the inputs go', () async {
      final backend = FakeMidiInput([keyStep]);
      final session =
          (await MidiInputSession.start(backend, MidiInputChoice.all))!;
      await session.close();
      expect(backend.connections.single.closed, isTrue);
    });

    test('a backend that fails to list inputs gives no session', () async {
      final backend = FakeMidiInput([keyStep], listingFails: true);
      expect(await MidiInputSession.start(backend, MidiInputChoice.all), isNull);
    });
  });

  group('ChannelMidiInput', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const methods = MethodChannel('test/midi_input');
    const events = EventChannel('test/midi_input/events');
    late List<MethodCall> calls;
    late Object? Function(MethodCall) answer;

    setUp(() {
      calls = [];
      answer = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return answer(call);
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockStreamHandler(events, null);
    });

    ChannelMidiInput backend() =>
        ChannelMidiInput(methods: methods, events: events);

    test('lists what the native side reports', () async {
      answer = (_) => [
            {'id': '7', 'name': 'KeyStep'},
            {'id': '9', 'name': 'KeyStep'},
            {'broken': true},
          ];
      expect(await backend().devices(), const [
        MidiInputDevice(id: '7', name: 'KeyStep'),
        MidiInputDevice(id: '9', name: 'KeyStep (2)'),
      ]);
    });

    test('no native side: no inputs, never an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, null);
      expect(await backend().devices(), isEmpty);
      final connection = await backend().open([keyStep]);
      expect(connection.failed, [keyStep]);
      await connection.close();
    });

    test('a native error lists no inputs', () async {
      answer = (_) => throw PlatformException(code: 'boom');
      expect(await backend().devices(), isEmpty);
    });

    test('opens by id, reports those that failed, passes on what they play',
        () async {
      answer = (call) => call.method == 'open' ? ['1'] : null;
      final sink = StreamController<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(events, MockStreamHandler.inline(
        onListen: (_, events) => sink.stream.listen(events.success),
      ));
      final connection = await backend().open([keyStep, pads]);
      expect(calls.last.method, 'open');
      expect(calls.last.arguments, {
        'ids': ['0', '1'],
      });
      expect(connection.failed, [pads]);

      final packets = <MidiInputPacket>[];
      connection.packets.listen(packets.add);
      sink.add({'id': '0', 'bytes': Uint8List.fromList([0x90, 60, 100])});
      sink.add({'id': '0'}); // Malformed: dropped.
      await pumpEventQueue();
      expect(packets.single.deviceId, '0');
      expect(packets.single.bytes, [0x90, 60, 100]);

      await connection.close();
      expect(calls.last.method, 'close');
      await sink.close();
    });
  });

  group('isOfferedAlsaPort', () {
    const read = 1 << 0, subsRead = 1 << 5, noExport = 1 << 7;

    test('a keyboard that can be read and subscribed to', () {
      expect(
          isOfferedAlsaPort(
              client: 24,
              capability: read | subsRead,
              clientName: 'KeyStep'),
          isTrue);
    });

    test('not the system client, nor Midi Through', () {
      expect(
          isOfferedAlsaPort(
              client: 0, capability: read | subsRead, clientName: 'System'),
          isFalse);
      expect(
          isOfferedAlsaPort(
              client: 14,
              capability: read | subsRead,
              clientName: 'Midi Through'),
          isFalse);
    });

    test('not a port only written to, or hidden', () {
      expect(
          isOfferedAlsaPort(client: 24, capability: 1 << 1, clientName: 'Synth'),
          isFalse);
      expect(
          isOfferedAlsaPort(
              client: 24,
              capability: read | subsRead | noExport,
              clientName: 'KeyStep'),
          isFalse);
    });
  });

  group('platform backends', () {
    // The CI machines have no MIDI hardware: what's tested is that asking
    // never throws or hangs, whatever the machine has.
    test('Windows lists its inputs, and an unknown one fails to open',
        () async {
      final backend = WindowsMidiInput();
      final devices = await backend.devices();
      expect(devices.map((d) => d.name).toSet().length, devices.length,
          reason: 'names tell inputs apart');
      final connection = await backend
          .open(const [MidiInputDevice(id: '9999', name: 'Nothing')]);
      expect(connection.failed.single.id, '9999');
      await connection.close();
    }, skip: !Platform.isWindows);

    test('Linux lists its inputs, and an unknown one fails to open', () async {
      final backend = LinuxMidiInput();
      await backend.devices();
      final connection = await backend
          .open(const [MidiInputDevice(id: '250:0', name: 'Nothing')]);
      expect(connection.failed.single.id, '250:0');
      await connection.close();
    }, skip: !Platform.isLinux, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('MidiInputBackend.supportedFor', () {
    test('offered everywhere but inside the Flatpak sandbox', () {
      // The Flathub build doesn't ask for --device=all, without which the
      // ALSA sequencer can't be reached: offering MIDI there would only ever
      // say "no inputs found".
      expect(MidiInputBackend.supportedFor(isLinux: true, inFlatpak: true),
          isFalse);
      expect(MidiInputBackend.supportedFor(isLinux: true, inFlatpak: false),
          isTrue, reason: 'the tarball and the AppImage have it');
      expect(MidiInputBackend.supportedFor(isLinux: false, inFlatpak: false),
          isTrue);
    });

    test('on the machine running the tests (never a Flatpak), it is', () {
      expect(MidiInputBackend.isSupported, isTrue);
    });
  });

  group('MidiInputChoiceStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await HiveTestHelper.setUp();
      MidiInputChoiceStore.cachedForTest = MidiInputChoice.off;
    });

    tearDown(() => HiveTestHelper.tearDown(tempDir));

    test('a chosen input survives a reload', () async {
      await MidiInputChoiceStore.save(MidiInputChoice.named('KeyStep'));
      MidiInputChoiceStore.cachedForTest = MidiInputChoice.off;
      expect(await MidiInputChoiceStore.load(),
          MidiInputChoice.named('KeyStep'));
      expect(MidiInputChoiceStore.current, MidiInputChoice.named('KeyStep'));
    });

    test('off until something is chosen', () async {
      expect(await MidiInputChoiceStore.load(), MidiInputChoice.off);
    });

    test('the metronome and the recording latency are remembered', () async {
      MidiMetronomeStore.cachedForTest = false;
      MidiRecordLatencyStore.cachedForTest = Duration.zero;
      expect(await MidiMetronomeStore.load(), isFalse, reason: 'off at first');
      expect(await MidiRecordLatencyStore.load(), Duration.zero);

      await MidiMetronomeStore.save(true);
      await MidiRecordLatencyStore.save(const Duration(milliseconds: 85));
      MidiMetronomeStore.cachedForTest = false;
      MidiRecordLatencyStore.cachedForTest = Duration.zero;
      expect(await MidiMetronomeStore.load(), isTrue);
      expect(await MidiRecordLatencyStore.load(),
          const Duration(milliseconds: 85));
    });
  });
}
