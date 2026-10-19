import 'package:flutter/foundation.dart';

import 'midi_clip_edit_controller.dart';

/// Step input, as in Cubase: played on a MIDI keyboard, each note — or
/// chord: the keys held down together — goes in at the cursor, one grid
/// step long ([MidiClipEditController.newNoteTicks]), at the velocity it was
/// played with. Letting go of the last key moves the cursor on a step,
/// ready for the next. Only the order of what is played counts, never its
/// timing: the way to enter a line too fast, or too tricky, to play in
/// time.
///
/// The cursor is the window's own (the line resting on the ruler), read
/// through [cursor] and moved through [onCursorChanged].
class MidiStepInput {
  MidiStepInput({
    required this.editor,
    required this.cursor,
    required this.onCursorChanged,
  });

  final MidiClipEditController editor;

  /// Where the next note goes, in ticks.
  final int Function() cursor;
  final ValueChanged<int> onCursorChanged;

  /// The keys down now.
  final Set<int> _down = {};

  /// Whether the keys down have put notes in — so letting go of them moves
  /// the cursor on, and another key pressed meanwhile joins their chord.
  bool _entered = false;

  /// A key pressed: its note goes in, joining the chord of the keys still
  /// held. Nothing while the piano roll isn't editing.
  void noteOn(int pitch, int velocity) {
    if (!editor.editing || !_down.add(pitch)) return;
    final before = editor.committed;
    editor.addStepNote(cursor(), pitch, velocity, joinChord: _entered);
    if (!identical(editor.committed, before)) _entered = true;
  }

  /// A key let go: the last of a chord moves the cursor a step on.
  void noteOff(int pitch) {
    if (!_down.remove(pitch) || _down.isNotEmpty || !_entered) return;
    _entered = false;
    onCursorChanged(cursor() + editor.newNoteTicks);
  }

  /// ← / →: the cursor [steps] steps on (back, when negative) — a rest, or
  /// a step back over a mistake — never before the start.
  void move(int steps) {
    final next = cursor() + steps * editor.newNoteTicks;
    onCursorChanged(next < 0 ? 0 : next);
  }

  /// Forgets the keys down, as when the input goes away with them held.
  void reset() {
    _down.clear();
    _entered = false;
  }
}

/// [tick] on the nearest line of a grid [step] ticks apart — where the step
/// cursor sits after a click on the ruler between two lines.
int nearestStepTick(double tick, int step) {
  if (step <= 1) return tick < 0 ? 0 : tick.round();
  final at = (tick / step).round() * step;
  return at < 0 ? 0 : at;
}
