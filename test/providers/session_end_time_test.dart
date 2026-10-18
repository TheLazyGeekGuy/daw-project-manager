import 'package:daw_project_manager/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 18, 10);
  final now = DateTime(2026, 10, 18, 12);

  test('a session ended by hand ends now', () {
    expect(sessionEndTime(start: start, now: now), now);
  });

  test('a session ended by the DAW plugin ends when the DAW closed the project', () {
    final closed = DateTime(2026, 10, 18, 11, 30);
    expect(sessionEndTime(start: start, now: now, requestedEnd: closed), closed);
  });

  test('paused time is not work: a paused session ends where it was paused', () {
    final paused = DateTime(2026, 10, 18, 11);
    expect(sessionEndTime(start: start, now: now, pausedAt: paused), paused);
    expect(sessionEndTime(start: start, now: now, pausedAt: paused, requestedEnd: DateTime(2026, 10, 18, 11, 30)), paused);
    expect(
      sessionEndTime(start: start, now: now, pausedAt: paused, requestedEnd: DateTime(2026, 10, 18, 10, 30)),
      DateTime(2026, 10, 18, 10, 30),
    );
  });

  test('an end in the future or before the start is clamped', () {
    expect(sessionEndTime(start: start, now: now, requestedEnd: now.add(const Duration(hours: 1))), now);
    expect(sessionEndTime(start: start, now: now, requestedEnd: start.subtract(const Duration(hours: 1))), start);
  });
}
