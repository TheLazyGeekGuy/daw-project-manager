import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/services/midi/input/midi_input.dart';
import 'package:daw_project_manager/services/midi/midi_clip_synth.dart';
import 'package:daw_project_manager/services/midi/synth_voice.dart';
import 'package:daw_project_manager/ui/midi_note_auditioner.dart';
import 'package:daw_project_manager/ui/midi_piano_roll_dialog.dart';
import 'package:daw_project_manager/ui/midi_preview_player.dart';
import 'package:daw_project_manager/ui/widgets/midi_input_button.dart';
import 'package:daw_project_manager/ui/widgets/midi_piano_roll.dart';
import 'package:daw_project_manager/ui/widgets/midi_tempo_control.dart';
import 'package:daw_project_manager/utils/musical_scale.dart';

import '../helpers/fake_midi_input.dart';

/// One empty bar at 480 PPQ: a 1/16 step is 120 ticks.
const _empty = MidiClip(name: 'Idea', ppq: 480, lengthTicks: 1920, notes: []);

const _keyStep = MidiInputDevice(id: '0', name: 'KeyStep');
const _pads = MidiInputDevice(id: '1', name: 'Pads');

String _laneName(MidiLane lane) => lane.toString();
String _scaleTypeName(ScaleType type) => type.name;

/// Hears what the window sounds, instead of playing it.
class _Ear extends MidiNoteAuditioner {
  final heard = <(int, int)>[];
  final held = <int>[];
  final _notes = <MidiHeldNote, int>{};

  @override
  Future<void> play(int pitch, {int velocity = 100}) async =>
      heard.add((pitch, velocity));

  @override
  MidiHeldNote hold(int pitch, {int velocity = 100}) {
    heard.add((pitch, velocity));
    held.add(pitch);
    final note = heldNoteForTest();
    _notes[note] = pitch;
    return note;
  }

  @override
  Future<void> release(MidiHeldNote note) async {
    final pitch = _notes.remove(note);
    if (pitch != null) held.remove(pitch);
  }
}

final _labels = MidiPianoRollWindowLabels(
  roll: const MidiPianoRollLabels(
    zoomIn: 'In',
    zoomOut: 'Out',
    fit: 'Fit',
    follow: 'Follow',
    lane: 'Lane',
    laneNone: 'None',
    laneName: _laneName,
    scale: 'Scale',
    scaleNone: 'No scale',
    scaleRoot: 'Root',
    scaleType: 'Type',
    scaleTypeName: _scaleTypeName,
    edit: 'Edit',
    undo: 'Undo',
    redo: 'Redo',
    snap: 'Snap',
    snapOff: 'Off',
    toolSelect: 'Select',
    toolRange: 'Range',
    toolEraser: 'Eraser',
    toolPencil: 'Pencil',
  ),
  close: 'Close',
  play: 'Play',
  pause: 'Pause',
  stop: 'Stop',
  openProject: 'Project details',
  saveAsNew: 'Save as new clip',
  metronome: 'Metronome',
  tempo: const MidiTempoLabels(
    unit: 'BPM',
    tooltip: 'Tempo',
    slower: 'Slower',
    faster: 'Faster',
  ),
  midiInput: MidiInputLabels(
    input: 'MIDI input',
    off: 'No MIDI input',
    all: 'All MIDI inputs',
    noDevices: 'No MIDI inputs found',
    listening: (names) => 'MIDI input: $names',
    busy: (names) => 'Busy: $names',
    record: 'Record',
    stopRecording: 'Stop recording',
    latency: (ms) => 'Latency: $ms ms',
    latencyTitle: 'Recording latency',
    latencyBody: 'Moves recorded notes earlier.',
    calibrate: 'Calibrate',
    calibrating: (done, total) => 'Tap along: $done of $total',
    calibrated: (ms) => 'Latency set to $ms ms',
    done: 'Done',
    cancel: 'Cancel',
  ),
);

void main() {
  late MidiPreviewPlayer player;
  late FakeMidiInput backend;
  late _Ear ear;
  late List<MidiInputChoice> choices;
  late List<MidiClip> saved;
  late int plays;
  late List<bool> metronomeChanges;
  late List<Duration> latencyChanges;

  setUp(() {
    plays = 0;
    metronomeChanges = [];
    latencyChanges = [];
    player = MidiPreviewPlayer();
    backend = FakeMidiInput([_keyStep, _pads]);
    ear = _Ear();
    choices = [];
    saved = [];
  });
  tearDown(() => player.dispose());

  Future<void> open(
    WidgetTester tester, {
    MidiInputChoice choice = MidiInputChoice.all,
    bool editable = true,
    bool offered = true,
    bool metronome = false,
    Duration latency = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: 1300,
                  height: 700,
                  child: MidiPianoRollWindow(
                    clip: _empty,
                    title: 'Idea',
                    subtitle: null,
                    player: player,
                    playerKey: 'k',
                    bpm: 120,
                    labels: _labels,
                    onPlay: (_, _) => plays++,
                    voice: SynthVoice.keys,
                    auditioner: ear,
                    midiInput: backend,
                    midiInputChoice: choice,
                    onMidiInputChoiceChanged: offered ? choices.add : null,
                    metronome: metronome,
                    onMetronomeChanged: metronomeChanges.add,
                    recordLatency: latency,
                    onRecordLatencyChanged: latencyChanges.add,
                    onSaveEdited: editable
                        ? (edit) async {
                            saved.add(edit.clip);
                            return true;
                          }
                        : null,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> play(WidgetTester tester, List<int> bytes,
      {String device = '0'}) async {
    backend.play(device, bytes);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, int pitch, {int velocity = 100}) async {
    await play(tester, [0x90, pitch, velocity]);
    await play(tester, [0x80, pitch, 0]);
  }

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('midi-piano-roll-record')));
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(MidiPianoRollWindow))).pop();
    await tester.pumpAndSettle();
  }

  group('playing a MIDI keyboard', () {
    testWidgets('the remembered input is listened to as the window opens',
        (tester) async {
      await open(tester, choice: MidiInputChoice.named('Pads'));
      expect(backend.opened.single, [_pads]);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('midi-piano-roll-midi-input')))
              .tooltip,
          'MIDI input: Pads');
      await close(tester);
    });

    testWidgets('not offered (the Flatpak): no button, nothing opened',
        (tester) async {
      // What showMidiPianoRoll passes when MidiInputBackend.isSupported is
      // false: no choice, nowhere to keep one.
      await open(tester, choice: MidiInputChoice.off, offered: false);
      expect(find.byKey(const ValueKey('midi-piano-roll-midi-input')),
          findsNothing);
      expect(find.byKey(const ValueKey('midi-piano-roll-record')),
          findsNothing);
      expect(backend.opened, isEmpty);
      await close(tester);
    });

    testWidgets('off: nothing is opened', (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      expect(backend.opened, isEmpty);
      expect(find.byKey(const ValueKey('midi-piano-roll-record')),
          findsNothing);
      await close(tester);
    });

    testWidgets('a key sounds for as long as it is held, at its velocity',
        (tester) async {
      await open(tester);
      await play(tester, [0x90, 64, 90]);
      expect(ear.heard, [(64, 90)]);
      expect(ear.held, [64]);
      await play(tester, [0x90, 64, 0]); // Let go: a note-on at velocity 0.
      expect(ear.held, isEmpty);
      await close(tester);
    });

    testWidgets('without recording, playing never changes the clip',
        (tester) async {
      await open(tester);
      await tap(tester, 60);
      expect(find.byKey(const ValueKey('midi-piano-roll-save')), findsNothing);
      await close(tester);
    });

    testWidgets('closing the window lets the input go and silences its keys',
        (tester) async {
      await open(tester);
      await play(tester, [0x90, 60, 100]);
      expect(ear.held, [60]);
      await close(tester);
      expect(backend.connections.single.closed, isTrue,
          reason: 'on Windows, the DAW can only have it back once let go');
      expect(ear.held, isEmpty);
    });

    testWidgets('an input another app has shows as busy', (tester) async {
      backend = FakeMidiInput([_keyStep], busy: {'0'});
      await open(tester);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('midi-piano-roll-midi-input')))
              .tooltip,
          'Busy: KeyStep');
      await close(tester);
    });
  });

  group('choosing an input', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-midi-input')));
      await tester.pumpAndSettle();
    }

    testWidgets('lists what is plugged in now, and opens the one picked',
        (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      // Plugged in after the window opened: the menu still offers it.
      backend.available = [_keyStep, _pads, const MidiInputDevice(id: '2', name: 'Launchkey')];
      await openMenu(tester);
      expect(find.text('Launchkey'), findsOneWidget);
      await tester.tap(find.text('Pads'));
      await tester.pumpAndSettle();
      expect(choices, [MidiInputChoice.named('Pads')]);
      expect(backend.opened.single, [_pads]);
      await close(tester);
    });

    testWidgets('no MIDI input lets go of the one listened to', (tester) async {
      await open(tester);
      await openMenu(tester);
      await tester.tap(find.text('No MIDI input'));
      await tester.pumpAndSettle();
      expect(choices, [MidiInputChoice.off]);
      expect(backend.connections.single.closed, isTrue);
      expect(find.byKey(const ValueKey('midi-piano-roll-record')),
          findsNothing);
      await close(tester);
    });

    testWidgets('nothing plugged in says so', (tester) async {
      backend = FakeMidiInput([]);
      await open(tester, choice: MidiInputChoice.off);
      await openMenu(tester);
      expect(find.text('No MIDI inputs found'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await close(tester);
    });
  });

  group('recording', () {
    /// The take as the player would have it: the clip as opened, playing,
    /// at [at] into the loop — positions are read through the player.
    Future<void> playheadAt(WidgetTester tester, Duration at) async {
      player.preparingKey = null;
      player.playingKey = 'k';
      await player.seek('k', at);
    }

    // At 120 BPM and 480 PPQ, a second is 960 ticks.
    const ms = Duration(milliseconds: 1);

    MidiClip shown(WidgetTester tester) =>
        tester.widget<MidiPianoRoll>(find.byType(MidiPianoRoll)).editor!.clip;

    Future<void> stopPlayback(WidgetTester tester) async {
      await player.stop();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('plays the loop region, cycling, whatever the loop button says',
        (tester) async {
      await open(tester);
      await record(tester);
      expect(player.requestedLoop, isTrue);
      expect(player.requestedClip!.lengthTicks, 1920, reason: 'the region');
      final button = find.byKey(const ValueKey('midi-piano-roll-record'));
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      expect(tester.widget<IconButton>(button).tooltip, 'Stop recording');
      await stopPlayback(tester);
    });

    testWidgets('a key goes in where it was pressed, as long as it was held',
        (tester) async {
      await open(tester);
      await record(tester);
      await playheadAt(tester, ms * 500); // Tick 480.
      await play(tester, [0x90, 60, 90]);
      await playheadAt(tester, ms * 750); // Tick 720.
      await play(tester, [0x80, 60, 0]);
      final note = shown(tester).notes.single;
      expect(note.pitch, 60);
      expect(note.velocity, 90, reason: 'as hard as it was played');
      expect(note.startTick, closeTo(480, 24), reason: 'as played, off the grid');
      expect(note.lengthTicks, closeTo(240, 24));
      await stopPlayback(tester);
    });

    testWidgets('what was recorded plays on the next pass', (tester) async {
      await open(tester);
      await record(tester);
      await playheadAt(tester, ms * 250);
      player.requestedClip = null;
      await play(tester, [0x90, 64, 100]);
      await play(tester, [0x80, 64, 0]);
      expect(player.requestedClip, isNull, reason: 'not a render per note');
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.requestedClip!.notes.map((n) => n.pitch), [64]);
      await stopPlayback(tester);
    });

    testWidgets('a whole take undoes as one', (tester) async {
      await open(tester);
      await record(tester);
      for (final (i, pitch) in [60, 62, 64].indexed) {
        await playheadAt(tester, ms * (200 + i * 300));
        await play(tester, [0x90, pitch, 100]);
        await playheadAt(tester, ms * (300 + i * 300));
        await play(tester, [0x80, pitch, 0]);
      }
      expect(shown(tester).notes, hasLength(3));
      tester.widget<MidiPianoRoll>(find.byType(MidiPianoRoll)).editor!.undo();
      await tester.pump();
      expect(shown(tester).notes, isEmpty);
      await stopPlayback(tester);
    });

    testWidgets('a key held across the loop end stops there', (tester) async {
      await open(tester);
      await record(tester);
      await playheadAt(tester, ms * 1900); // Tick 1824 of 1920.
      await play(tester, [0x90, 67, 100]);
      await playheadAt(tester, ms * 100); // The next pass.
      await play(tester, [0x80, 67, 0]);
      final note = shown(tester).notes.single;
      expect(note.startTick, closeTo(1824, 24));
      expect(note.startTick + note.lengthTicks, 1920);
      await stopPlayback(tester);
    });

    testWidgets('a key already down when recording starts is not kept',
        (tester) async {
      await open(tester);
      await play(tester, [0x90, 60, 100]);
      await record(tester);
      await playheadAt(tester, ms * 500);
      await play(tester, [0x80, 60, 0]);
      expect(shown(tester).notes, isEmpty);
      await stopPlayback(tester);
    });

    testWidgets('stop ends recording; keys still down go in', (tester) async {
      await open(tester);
      await record(tester);
      await playheadAt(tester, ms * 500);
      await play(tester, [0x90, 60, 100]);
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-stop')));
      await tester.pump(const Duration(seconds: 1));
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('midi-piano-roll-record')))
              .isSelected,
          isFalse);
      expect(shown(tester).notes.single.pitch, 60);
    });

    testWidgets('R starts and ends it', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      final button = find.byKey(const ValueKey('midi-piano-roll-record'));
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      await playheadAt(tester, ms * 500);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      await stopPlayback(tester);
    });

    testWidgets('no MIDI input chosen: no record button', (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      expect(find.byKey(const ValueKey('midi-piano-roll-record')), findsNothing);
      await close(tester);
    });

    testWidgets('only viewing: no record button, keys still sound',
        (tester) async {
      await open(tester, editable: false);
      expect(find.byKey(const ValueKey('midi-piano-roll-record')), findsNothing);
      await tap(tester, 60);
      expect(ear.heard.single.$1, 60);
      await close(tester);
    });
  });

  group('the ruler', () {
    var clock = Duration.zero;

    Future<void> clickRuler(WidgetTester tester, double x,
        {Duration after = const Duration(seconds: 1)}) async {
      clock += after;
      final ruler =
          tester.getRect(find.byKey(const ValueKey('midi-piano-roll-ruler')));
      // Below the loop's strip, on the bar numbers.
      final at = Offset(ruler.left + x, ruler.bottom - 4);
      final g = await tester.createGesture();
      await g.down(at, timeStamp: clock);
      await g.up(timeStamp: clock);
      await tester.pumpAndSettle();
    }

    testWidgets('a double-click plays from there; a click only moves the start',
        (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      await clickRuler(tester, 200);
      expect(plays, 0, reason: 'a single click never starts playback');
      await clickRuler(tester, 200, after: const Duration(milliseconds: 120));
      expect(plays, 1);
      expect(player.pendingStartFor('k'), greaterThan(Duration.zero),
          reason: 'from where it was double-clicked');
    });

    testWidgets('a new tempo leaves the resting line on the same tick',
        (tester) async {
      // Kept as a time and read back at the new tempo, it used to jump —
      // at double the tempo, twice as far along.
      await open(tester, choice: MidiInputChoice.off);
      await clickRuler(tester, 300);
      final before =
          tester.widget<MidiPianoRoll>(find.byType(MidiPianoRoll)).restTick!;
      final field = find.descendant(
          of: find.byKey(const ValueKey('midi-piano-roll-tempo')),
          matching: find.byType(TextField));
      await tester.enterText(field, '240');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(before, greaterThan(0));
      expect(tester.widget<MidiPianoRoll>(find.byType(MidiPianoRoll)).restTick,
          closeTo(before, 1));
    });
  });

  group('the metronome', () {
    Future<void> stopPlayback(WidgetTester tester) async {
      await player.stop();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('clicking, what plays carries the clicks, on the clip\'s beats',
        (tester) async {
      await open(tester, choice: MidiInputChoice.off, metronome: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(plays, 0, reason: 'the window plays it: the list has no clicks');
      expect(player.requestedMetronome,
          const Metronome(beatTicks: 480, barTicks: 1920));
      await stopPlayback(tester);
    });

    testWidgets('off, the list plays the clip as it always did', (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(plays, 1);
      expect(player.requestedMetronome, isNull);
      await stopPlayback(tester);
    });

    testWidgets('its button and C switch it, and are remembered',
        (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      final button = find.byKey(const ValueKey('midi-piano-roll-metronome'));
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      expect(metronomeChanges, [true, false]);
    });

    testWidgets('switched on while playing, playback carries on clicking',
        (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      player.preparingKey = null;
      player.playingKey = 'k';
      await player.seek('k', const Duration(milliseconds: 500));
      player.requestedClip = null;
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-metronome')));
      await tester.pump();
      expect(player.requestedClip, isNotNull);
      expect(player.requestedMetronome, isNotNull);
      expect(player.requestedStart!.inMilliseconds, closeTo(500, 50),
          reason: 'from where it was');
      await stopPlayback(tester);
    });

    testWidgets('recording clicks along with the loop', (tester) async {
      await open(tester, metronome: true);
      await record(tester);
      expect(player.requestedLoop, isTrue);
      expect(player.requestedMetronome, isNotNull);
      await stopPlayback(tester);
    });
  });

  group('recording latency', () {
    const ms = Duration(milliseconds: 1);

    Future<void> playheadAt(WidgetTester tester, Duration at) async {
      player.preparingKey = null;
      player.playingKey = 'k';
      await player.seek('k', at);
    }

    testWidgets('recorded notes go in that much earlier', (tester) async {
      await open(tester, latency: ms * 100); // 96 ticks at 120 BPM.
      await record(tester);
      await playheadAt(tester, ms * 600); // Tick 576: heard as 480.
      await play(tester, [0x90, 60, 100]);
      await playheadAt(tester, ms * 850); // Tick 816: heard as 720.
      await play(tester, [0x80, 60, 0]);
      final note = tester
          .widget<MidiPianoRoll>(find.byType(MidiPianoRoll))
          .editor!
          .clip
          .notes
          .single;
      expect(note.startTick, closeTo(480, 24));
      expect(note.lengthTicks, closeTo(240, 24));
      await player.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    Future<void> openLatency(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-midi-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latency: 0 ms'));
      await tester.pumpAndSettle();
    }

    testWidgets('set from the MIDI input menu', (tester) async {
      await open(tester);
      await openLatency(tester);
      expect(find.text('Recording latency'), findsOneWidget);
      await tester.drag(
          find.byKey(const ValueKey('midi-latency-slider')), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('250 ms'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(latencyChanges, [const Duration(milliseconds: 250)]);
      await close(tester);
    });

    testWidgets('only offered where there is something to record into',
        (tester) async {
      await open(tester, editable: false);
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-midi-input')));
      await tester.pumpAndSettle();
      expect(find.text('Latency: 0 ms'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await close(tester);
    });

    testWidgets('calibrating: play along to the clicks, and it is measured',
        (tester) async {
      await open(tester);
      await openLatency(tester);
      await tester.tap(find.text('Calibrate'));
      await tester.pumpAndSettle();
      expect(find.text('Tap along: 0 of 8'), findsOneWidget);
      expect(player.requestedClip!.name, 'calibration');
      expect(player.requestedLoop, isTrue);
      expect(player.requestedMetronome, isNotNull);

      // Every beat (half a second at 120 BPM), 50 ms late.
      player.preparingKey = null;
      player.playingKey = 'k~calibrate';
      for (var i = 0; i < 8; i++) {
        await player.seek('k~calibrate', ms * ((i % 4) * 500 + 50));
        await play(tester, [0x90, 60, 100]);
        await play(tester, [0x80, 60, 0]);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(latencyChanges.single.inMilliseconds, closeTo(50, 3));
      expect(find.textContaining('Latency set to'), findsOneWidget);
      expect(player.playingKey, isNull, reason: 'the clicks stop');
      expect(
          tester
              .widget<MidiPianoRoll>(find.byType(MidiPianoRoll))
              .editor!
              .clip
              .notes,
          isEmpty,
          reason: 'calibrating records nothing');
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.byKey(const ValueKey('midi-piano-roll-calibration')),
          findsNothing);
      await close(tester);
    });

    testWidgets('stop cancels calibrating, and changes nothing',
        (tester) async {
      await open(tester);
      await openLatency(tester);
      await tester.tap(find.text('Calibrate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-stop')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('midi-piano-roll-calibration')),
          findsNothing);
      expect(latencyChanges, isEmpty);
      await close(tester);
    });
  });
}
