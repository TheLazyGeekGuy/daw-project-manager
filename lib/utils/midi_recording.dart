/// How many keys calibrating recording latency asks for, one per click.
const kCalibrationTaps = 8;

/// Where a key played while recording goes: [nowTick], where the player
/// says playback is, less [latency] — the round trip from playback to the
/// speakers to the player's ears, and from the key back to the app — at
/// [bpm]. Inside a cycling [region] a key played just after its start was
/// meant for the end of the pass before, and goes there. Never before 0.
double recordedTick(
  double nowTick, {
  required Duration latency,
  required double bpm,
  required int ppq,
  ({int start, int end})? region,
}) {
  var tick = nowTick - latencyTicks(latency, bpm: bpm, ppq: ppq);
  if (region != null && region.end > region.start && tick < region.start) {
    tick += region.end - region.start;
  }
  return tick < 0 ? 0 : tick;
}

/// [latency] in ticks at [bpm].
double latencyTicks(Duration latency,
        {required double bpm, required int ppq}) =>
    latency.inMicroseconds / 1e6 * bpm / 60 * ppq;

/// The latency that keys played along to a metronome show: each tap in
/// [tapTicks] (where the player said playback was) against the click
/// nearest it, every [beatTicks]; the median of how late they came, as a
/// time at [bpm] — the median, so a tap or two that missed don't skew it.
/// Null with fewer than [minTaps] taps. Early on average reads as none.
Duration? measuredLatency(
  List<double> tapTicks, {
  required int beatTicks,
  required double bpm,
  required int ppq,
  int minTaps = 4,
}) {
  if (tapTicks.length < minTaps || beatTicks <= 0) return null;
  final late = [
    for (final t in tapTicks) t - (t / beatTicks).round() * beatTicks,
  ]..sort();
  final mid = late.length ~/ 2;
  final median =
      late.length.isOdd ? late[mid] : (late[mid - 1] + late[mid]) / 2;
  if (median <= 0) return Duration.zero;
  final seconds = median / ppq * 60 / bpm;
  return Duration(microseconds: (seconds * 1e6).round());
}
