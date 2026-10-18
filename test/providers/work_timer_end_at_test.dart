import 'dart:io';

import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// The DPM Companion bridge ends a session through WorkTimerNotifier.endAt,
/// with the time the DAW closed the project — not the time the app heard.
void main() {
  late Directory tempDir;
  late ProjectRepository repo;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    repo = await HiveTestHelper.createRepository(profileId: 'solo');
    await repo.updateProject(TestFactories.makeProject(id: 'p1', sessions: [], totalWorkSeconds: 0));
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWith((ref) async => repo),
    ]);
    // Riverpod 3 pauses what nothing listens to; the app keeps these alive.
    container.listen(workTimerProvider, (_, _) {});
    container.listen(activeProjectProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await HiveTestHelper.tearDown(tempDir);
  });

  Future<MusicProject> savedSession() async {
    for (var i = 0; i < 100; i++) {
      final p = repo.getById('p1')!;
      if (p.sessions.isNotEmpty) return p;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('no session was saved');
  }

  test('endAt saves the session as ending at the given time and clears it', () async {
    final started = DateTime.now().subtract(const Duration(minutes: 10));
    final closed = started.add(const Duration(minutes: 6));

    container.read(activeProjectProvider.notifier).set(repo.getById('p1')!);
    container.read(workTimerProvider.notifier).continueFrom(started);
    container.read(workTimerProvider.notifier).endAt(closed);

    expect(container.read(activeProjectProvider), isNull);
    final project = await savedSession();
    final session = project.sessions.single;
    expect(session.startedAt, started);
    expect(session.endedAt, closed);
    expect(session.durationSeconds, 6 * 60);
    expect(project.totalWorkSeconds, 6 * 60);
  });

  test('endAt does nothing when no session is running', () async {
    container.read(workTimerProvider.notifier).endAt(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(repo.getById('p1')!.sessions, isEmpty);
  });

  test('ending by hand afterwards still ends now', () async {
    final started = DateTime.now().subtract(const Duration(minutes: 3));
    container.read(activeProjectProvider.notifier).set(repo.getById('p1')!);
    container.read(workTimerProvider.notifier).continueFrom(started);
    container.read(activeProjectProvider.notifier).clear();

    final session = (await savedSession()).sessions.single;
    expect(session.durationSeconds, inInclusiveRange(3 * 60 - 1, 3 * 60 + 5));
  });
}
