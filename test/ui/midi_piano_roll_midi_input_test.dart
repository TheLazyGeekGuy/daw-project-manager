import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/services/midi/input/midi_input.dart';
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
    stepInput: 'Step input',
  ),
);

void main() {
  late MidiPreviewPlayer player;
  late FakeMidiInput backend;
  late _Ear ear;
  late List<MidiInputChoice> choices;
  late List<MidiClip> saved;

  setUp(() {
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
                    onPlay: (_, _) {},
                    voice: SynthVoice.keys,
                    auditioner: ear,
                    midiInput: backend,
                    midiInputChoice: choice,
                    onMidiInputChoiceChanged: offered ? choices.add : null,
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

  Future<void> stepInputOn(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('midi-piano-roll-step-input')));
    await tester.pumpAndSettle();
  }

  Future<List<MidiNote>> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('midi-piano-roll-save')));
    await tester.pumpAndSettle();
    return saved.last.notes;
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
      expect(find.byKey(const ValueKey('midi-piano-roll-step-input')),
          findsNothing);
      expect(backend.opened, isEmpty);
      await close(tester);
    });

    testWidgets('off: nothing is opened', (tester) async {
      await open(tester, choice: MidiInputChoice.off);
      expect(backend.opened, isEmpty);
      expect(find.byKey(const ValueKey('midi-piano-roll-step-input')),
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

    testWidgets('without step input, playing never changes the clip',
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
      expect(find.byKey(const ValueKey('midi-piano-roll-step-input')),
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

  group('step input', () {
    testWidgets('each note goes in a grid step after the last', (tester) async {
      await open(tester);
      await stepInputOn(tester);
      await tap(tester, 60, velocity: 80);
      await tap(tester, 62);
      await tap(tester, 64);
      final notes = await save(tester);
      expect([for (final n in notes) (n.startTick, n.lengthTicks, n.pitch)],
          [(0, 120, 60), (120, 120, 62), (240, 120, 64)]);
      expect(notes.first.velocity, 80, reason: 'as hard as it was played');
      await close(tester);
    });

    testWidgets('keys held together go in as a chord', (tester) async {
      await open(tester);
      await stepInputOn(tester);
      await play(tester, [0x90, 60, 100]);
      await play(tester, [0x90, 64, 100]);
      await play(tester, [0x90, 67, 100]);
      await play(tester, [0x80, 60, 0]);
      await play(tester, [0x80, 64, 0]);
      await play(tester, [0x80, 67, 0]);
      await tap(tester, 72);
      final notes = await save(tester);
      expect([for (final n in notes) (n.startTick, n.pitch)],
          [(0, 60), (0, 64), (0, 67), (120, 72)]);
      await close(tester);
    });

    testWidgets('→ leaves a rest, ← steps back', (tester) async {
      await open(tester);
      await stepInputOn(tester);
      await tap(tester, 60);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tap(tester, 62);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tap(tester, 64);
      final notes = await save(tester);
      // 60 at 0, a rest, 62 at 240; then back two steps from 360: 120.
      expect([for (final n in notes) (n.startTick, n.pitch)],
          [(0, 60), (120, 64), (240, 62)]);
      await close(tester);
    });

    testWidgets('turning it on starts editing; editing off turns it off',
        (tester) async {
      await open(tester);
      await stepInputOn(tester);
      final toggle = find.byKey(const ValueKey('midi-piano-roll-step-input'));
      expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
      await tester.tap(find.byKey(const ValueKey('midi-piano-roll-edit')));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
      await tap(tester, 60);
      expect(find.byKey(const ValueKey('midi-piano-roll-save')), findsNothing);
      await close(tester);
    });

    testWidgets('a view-only window has no step input', (tester) async {
      await open(tester, editable: false);
      expect(find.byKey(const ValueKey('midi-piano-roll-step-input')),
          findsNothing);
      await tap(tester, 60);
      expect(ear.heard.single.$1, 60, reason: 'it still sounds');
      await close(tester);
    });

    testWidgets('a new tempo leaves the cursor on the same note', (tester) async {
      // The cursor is kept as a time; turned into ticks at the new tempo, it
      // used to jump — at double the tempo, twice as far along.
      await open(tester);
      await stepInputOn(tester);
      await tap(tester, 60);
      await tap(tester, 62);
      final field = find.descendant(
          of: find.byKey(const ValueKey('midi-piano-roll-tempo')),
          matching: find.byType(TextField));
      await tester.enterText(field, '240');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tap(tester, 64);
      final notes = await save(tester);
      expect([for (final n in notes) (n.startTick, n.pitch)],
          [(0, 60), (120, 62), (240, 64)]);
      await close(tester);
    });
  });
}
