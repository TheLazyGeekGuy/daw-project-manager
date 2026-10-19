import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/ui/widgets/midi_clip_edit_controller.dart';
import 'package:daw_project_manager/ui/widgets/midi_step_input.dart';

/// One empty 4/4 bar at 480 PPQ: a 1/16 step is 120 ticks.
const _empty = MidiClip(name: 'Idea', ppq: 480, lengthTicks: 1920, notes: []);

({int start, int length, int pitch, int velocity}) _n(MidiNote n) => (
      start: n.startTick,
      length: n.lengthTicks,
      pitch: n.pitch,
      velocity: n.velocity,
    );

void main() {
  group('MidiClipEditController.addStepNote', () {
    test('puts a grid step long note exactly at the tick, selected', () {
      final c = MidiClipEditController(_empty)..editing = true;
      c.addStepNote(360, 64, 87);
      expect(c.clip.notes.map(_n),
          [(start: 360, length: 120, pitch: 64, velocity: 87)]);
      expect(c.selection, {0});
      expect(c.canUndo, isTrue);
    });

    test('a chord is one undo step', () {
      final c = MidiClipEditController(_empty)..editing = true;
      c.addStepNote(0, 60, 100);
      c.addStepNote(0, 64, 100, joinChord: true);
      c.addStepNote(0, 67, 100, joinChord: true);
      expect(c.clip.notes, hasLength(3));
      expect(c.selection, {0, 1, 2}, reason: 'the chord, ready to transpose');
      c.undo();
      expect(c.clip.notes, isEmpty, reason: 'the whole chord, not its last note');
      expect(c.canUndo, isFalse);
    });

    test('the next chord is a step of its own', () {
      final c = MidiClipEditController(_empty)..editing = true;
      c.addStepNote(0, 60, 100);
      c.addStepNote(120, 62, 100);
      expect(c.selection, {1});
      c.undo();
      expect(c.clip.notes.map((n) => n.pitch), [60]);
    });

    test('joining a chord that was undone starts a new step', () {
      final c = MidiClipEditController(_empty)..editing = true;
      c.addStepNote(0, 60, 100);
      c.undo();
      c.addStepNote(0, 64, 100, joinChord: true);
      c.undo();
      expect(c.clip.notes, isEmpty);
      expect(c.canRedo, isTrue);
    });

    test('a note past the end grows the clip, as any note does', () {
      final c = MidiClipEditController(_empty)..editing = true;
      c.addStepNote(1920, 60, 100);
      expect(c.clip.lengthTicks, 3840);
    });

    test('with snapping off, a 16th long', () {
      final c = MidiClipEditController(_empty)
        ..editing = true
        ..snap = MidiSnap.off;
      c.addStepNote(7, 60, 100);
      expect(c.clip.notes.single.lengthTicks, 120);
      expect(c.clip.notes.single.startTick, 7);
    });

    test('nothing while only viewing, or mid-drag', () {
      final viewing = MidiClipEditController(_empty);
      viewing.addStepNote(0, 60, 100);
      expect(viewing.clip.notes, isEmpty);

      const one = MidiClip(
        name: 'One',
        ppq: 480,
        lengthTicks: 1920,
        notes: [MidiNote(startTick: 0, lengthTicks: 120, pitch: 60, velocity: 100)],
      );
      final c = MidiClipEditController(one)..editing = true;
      c.select(0);
      c.beginGesture();
      c.moveSelection(240, 0);
      c.addStepNote(0, 72, 100);
      c.endGesture();
      // The drag finished as dragged; the note played into it would have
      // been dropped by the drag's end anyway.
      expect(c.clip.notes.map(_n),
          [(start: 240, length: 120, pitch: 60, velocity: 100)]);
    });
  });

  group('MidiStepInput', () {
    late MidiClipEditController editor;
    late int cursor;
    late MidiStepInput step;

    setUp(() {
      editor = MidiClipEditController(_empty)..editing = true;
      cursor = 0;
      step = MidiStepInput(
        editor: editor,
        cursor: () => cursor,
        onCursorChanged: (t) => cursor = t,
      );
    });

    test('a note goes in at the cursor, and letting go moves on a step', () {
      step.noteOn(60, 100);
      expect(cursor, 0, reason: 'not while the key is still down');
      step.noteOff(60);
      expect(cursor, 120);
      step.noteOn(62, 80);
      step.noteOff(62);
      expect(editor.clip.notes.map(_n), [
        (start: 0, length: 120, pitch: 60, velocity: 100),
        (start: 120, length: 120, pitch: 62, velocity: 80),
      ]);
      expect(cursor, 240);
    });

    test('keys held together are a chord: one step, one undo', () {
      step.noteOn(60, 100);
      step.noteOn(64, 100);
      step.noteOff(60);
      expect(cursor, 0, reason: 'a key of the chord is still down');
      step.noteOn(67, 100); // Joins: E is still held.
      step.noteOff(64);
      step.noteOff(67);
      expect(cursor, 120);
      expect(editor.clip.notes.map((n) => (n.startTick, n.pitch)),
          [(0, 60), (0, 64), (0, 67)]);
      editor.undo();
      expect(editor.clip.notes, isEmpty);
    });

    test('the timing of what is played never matters, only its order', () {
      // Held for a long time, or tapped: always one grid step.
      for (final pitch in [60, 62, 64]) {
        step.noteOn(pitch, 100);
        step.noteOff(pitch);
      }
      expect(editor.clip.notes.map((n) => n.lengthTicks), [120, 120, 120]);
      expect(editor.clip.notes.map((n) => n.startTick), [0, 120, 240]);
    });

    test('the grid sets the step', () {
      editor.snap = MidiSnap.eighth;
      step.noteOn(60, 100);
      step.noteOff(60);
      expect(editor.clip.notes.single.lengthTicks, 240);
      expect(cursor, 240);
    });

    test('nothing goes in, nor moves, while not editing', () {
      editor.editing = false;
      step.noteOn(60, 100);
      step.noteOff(60);
      expect(editor.clip.notes, isEmpty);
      expect(cursor, 0);
    });

    test('a key let go that was never seen pressed is ignored', () {
      // Pressed before step input was on, let go after.
      step.noteOff(60);
      expect(cursor, 0);
    });

    test('a key repeated without being let go goes in once', () {
      step.noteOn(60, 100);
      step.noteOn(60, 100);
      step.noteOff(60);
      expect(editor.clip.notes, hasLength(1));
    });

    test('move: a rest forward, a step back, never before the start', () {
      step.move(1);
      expect(cursor, 120);
      step.move(2);
      expect(cursor, 360);
      step.move(-1);
      expect(cursor, 240);
      step.move(-10);
      expect(cursor, 0);
    });

    test('reset forgets the keys down', () {
      step.noteOn(60, 100);
      step.reset();
      step.noteOff(60);
      expect(cursor, 0, reason: 'the chord was forgotten, not finished');
      step.noteOn(62, 100);
      step.noteOff(62);
      editor.undo();
      expect(editor.clip.notes.map((n) => n.pitch), [60],
          reason: 'the next note was a step of its own');
    });
  });

  group('nearestStepTick', () {
    test('rounds to the nearest grid line, never below 0', () {
      expect(nearestStepTick(170, 120), 120);
      expect(nearestStepTick(181, 120), 240);
      expect(nearestStepTick(-50, 120), 0);
    });

    test('with no grid, the nearest tick', () {
      expect(nearestStepTick(239.6, 1), 240);
    });
  });
}
