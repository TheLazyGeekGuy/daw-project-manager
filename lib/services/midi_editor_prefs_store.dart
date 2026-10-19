import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import 'midi/input/midi_input.dart';
import 'player_volume_store.dart';

/// Whether the piano roll sounds notes as they are edited (its "acoustic
/// feedback" toggle). Device-local, like the preview volume and loop
/// setting: how this person likes to edit on this machine — neither synced
/// nor backed up.
class MidiAcousticFeedbackStore {
  const MidiAcousticFeedbackStore._();

  static const String key = 'midi_acoustic_feedback';
  static bool _cached = false;

  static bool get current => _cached;

  @visibleForTesting
  static set cachedForTest(bool value) => _cached = value;

  static Future<bool> load() async {
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      _cached = box.get(key) == 'true';
    } catch (e) {
      debugPrint('[MidiAcousticFeedback] failed to load: $e');
    }
    return _cached;
  }

  static Future<void> save(bool on) async {
    _cached = on;
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      await box.put(key, on.toString());
    } catch (e) {
      debugPrint('[MidiAcousticFeedback] failed to save: $e');
    }
  }
}

/// Whether the piano roll window fills the whole app window (its full
/// screen toggle). Device-local: it depends on this machine's screen.
class MidiPianoRollFullScreenStore {
  const MidiPianoRollFullScreenStore._();

  static const String key = 'midi_piano_roll_full_screen';
  static bool _cached = false;

  static bool get current => _cached;

  @visibleForTesting
  static set cachedForTest(bool value) => _cached = value;

  static Future<bool> load() async {
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      _cached = box.get(key) == 'true';
    } catch (e) {
      debugPrint('[MidiPianoRollFullScreen] failed to load: $e');
    }
    return _cached;
  }

  static Future<void> save(bool on) async {
    _cached = on;
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      await box.put(key, on.toString());
    } catch (e) {
      debugPrint('[MidiPianoRollFullScreen] failed to save: $e');
    }
  }
}

/// Which MIDI input the piano roll listens to: none, all, or one by name.
/// Device-local: it names this machine's hardware — neither synced nor
/// backed up.
class MidiInputChoiceStore {
  const MidiInputChoiceStore._();

  static const String key = 'midi_input_choice';
  static MidiInputChoice _cached = MidiInputChoice.off;

  static MidiInputChoice get current => _cached;

  @visibleForTesting
  static set cachedForTest(MidiInputChoice value) => _cached = value;

  static Future<MidiInputChoice> load() async {
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      _cached = MidiInputChoice.parse(box.get(key));
    } catch (e) {
      debugPrint('[MidiInputChoice] failed to load: $e');
    }
    return _cached;
  }

  static Future<void> save(MidiInputChoice choice) async {
    _cached = choice;
    try {
      final box = await Hive.openBox<String>(PlayerVolumeStore.boxName);
      await box.put(key, choice.stored);
    } catch (e) {
      debugPrint('[MidiInputChoice] failed to save: $e');
    }
  }
}
