import 'package:daw_project_manager/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  group('phonePlayerIsPlaying', () {
    test('playing while loading, buffering or ready', () {
      for (final s in [
        ja.ProcessingState.loading,
        ja.ProcessingState.buffering,
        ja.ProcessingState.ready,
      ]) {
        expect(phonePlayerIsPlaying(ja.PlayerState(true, s)), isTrue,
            reason: '$s');
      }
    });

    test('not playing when paused', () {
      for (final s in ja.ProcessingState.values) {
        expect(phonePlayerIsPlaying(ja.PlayerState(false, s)), isFalse,
            reason: '$s');
      }
    });

    test('not playing at the end of the queue, though just_audio says it is',
        () {
      expect(
        phonePlayerIsPlaying(
            ja.PlayerState(true, ja.ProcessingState.completed)),
        isFalse,
      );
    });

    test('playing again once a new song loads after the queue ended', () {
      // Regression: just_audio keeps `playing` true through the end of the
      // queue, so starting the next song never emitted on `playingStream` and
      // the button stayed on play while it played. The state that follows
      // is the new source loading with `playing` still true.
      final sequence = [
        ja.PlayerState(true, ja.ProcessingState.ready),
        ja.PlayerState(true, ja.ProcessingState.completed),
        ja.PlayerState(true, ja.ProcessingState.loading),
        ja.PlayerState(true, ja.ProcessingState.ready),
      ];
      expect(sequence.map(phonePlayerIsPlaying), [true, false, true, true]);
    });
  });
}
