import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/utils/midi_recording.dart';

void main() {
  // At 120 BPM and 480 PPQ, 1 ms is 0.96 ticks; 100 ms is 96.
  const bpm = 120.0, ppq = 480;

  group('recordedTick', () {
    test('takes the latency off where playback is', () {
      expect(
          recordedTick(576,
              latency: const Duration(milliseconds: 100), bpm: bpm, ppq: ppq),
          closeTo(480, 0.01));
    });

    test('no latency: where playback is', () {
      expect(recordedTick(300, latency: Duration.zero, bpm: bpm, ppq: ppq),
          300);
    });

    test('just after a cycling region starts: the end of the pass before',
        () {
      // Heard as the last beat's end, the key reached the app 40 ticks into
      // the next pass.
      expect(
        recordedTick(40,
            latency: const Duration(milliseconds: 100),
            bpm: bpm,
            ppq: ppq,
            region: (start: 0, end: 1920)),
        closeTo(1864, 0.01),
      );
      expect(
        recordedTick(1000,
            latency: const Duration(milliseconds: 100),
            bpm: bpm,
            ppq: ppq,
            region: (start: 960, end: 1920)),
        closeTo(1864, 0.01),
        reason: 'a region starting mid-clip wraps to its own end',
      );
    });

    test('without a region, never before the start', () {
      expect(
          recordedTick(40,
              latency: const Duration(milliseconds: 100), bpm: bpm, ppq: ppq),
          0);
    });

    test('a faster tempo makes the same latency more ticks', () {
      expect(latencyTicks(const Duration(milliseconds: 100), bpm: 240, ppq: ppq),
          closeTo(192, 0.01));
    });
  });

  group('measuredLatency', () {
    test('the median of how late each tap came after its click', () {
      // Clicks every beat (480 ticks); taps about 48 ticks (50 ms) late.
      final taps = <double>[528, 1010, 1488, 1968 - 1920, 528, 1012, 1490, 50];
      final latency =
          measuredLatency(taps, beatTicks: 480, bpm: bpm, ppq: ppq)!;
      expect(latency.inMilliseconds, closeTo(50, 2));
    });

    test('a tap that missed doesn\'t skew it', () {
      final taps = <double>[528, 1008, 1488, 48, 528, 1008, 1488, 700];
      expect(
          measuredLatency(taps, beatTicks: 480, bpm: bpm, ppq: ppq)!
              .inMilliseconds,
          closeTo(50, 1));
    });

    test('a tap just before a bar\'s first click is early for it', () {
      // 1900 is 20 ticks before 1920 — not 460 late after 1440.
      final taps = <double>[1900, 1900, 1900, 1900];
      expect(measuredLatency(taps, beatTicks: 480, bpm: bpm, ppq: ppq),
          Duration.zero, reason: 'early on average reads as none');
    });

    test('too few taps: nothing measured', () {
      expect(measuredLatency(<double>[528, 1008], beatTicks: 480, bpm: bpm, ppq: ppq),
          isNull);
    });
  });
}
