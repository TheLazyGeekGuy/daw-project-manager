// Shared set-up for the end-to-end tests in integration_test/: an isolated,
// freshly seeded library, the real app started on it, and helpers to drive
// it at a pace a person can follow.
//
// Run (Windows; -d macos / -d linux elsewhere, Linux under xvfb-run in CI):
//   flutter test integration_test -d windows --dart-define=DPM_DATA_DIR=daw_project_manager_uitest
// Add --dart-define=UITEST_STEP_MS=800 to watch it step by step.
//
// DPM_DATA_DIR pins the build to its own library: its own data folder under
// %LOCALAPPDATA%, its own Google Drive folder and its own single-instance
// port, so it runs beside the real app without touching its data. The
// harness refuses to run against any other library.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/utils/app_paths.dart';

/// How long each step is held on screen. Full speed by default (CI, and
/// most local runs); `--dart-define=UITEST_STEP_MS=800` slows it down enough
/// to watch.
const _stepMs = int.fromEnvironment('UITEST_STEP_MS');

/// The library seeded for a test.
class SeededLibrary {
  SeededLibrary({required this.profileId, required this.projectsFolder});
  final String profileId;
  final Directory projectsFolder;
}

/// The DAW project collection (`test/fixtures/projects/<daw>/<name>/`), as
/// checked out next to the running test.
Directory get fixtureProjects =>
    Directory(p.join(Directory.current.path, 'test', 'fixtures', 'projects'));

/// Every fixture project file, keyed by DAW folder ("ableton", "cubase"…).
Map<String, List<File>> fixtureProjectFiles(Directory root) {
  const exts = {'.cpr', '.npr', '.als', '.flp', '.rpp', '.song', '.bwproject', '.dawproject', '.ptx'};
  return {
    for (final daw in root.listSync().whereType<Directory>())
      p.basename(daw.path): [
        for (final folder in daw.listSync().whereType<Directory>())
          ...folder
              .listSync()
              .whereType<File>()
              .where((f) => exts.contains(p.extension(f.path).toLowerCase())),
      ],
  };
}

Future<void> _copyTree(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(recursive: false, followLinks: false)) {
    final target = p.join(to.path, p.basename(e.path));
    if (e is Directory) {
      await _copyTree(e, Directory(target));
    } else if (e is File) {
      await e.copy(target);
    }
  }
}

/// Wipes the test library and seeds it: one profile, first-run screens
/// passed, and one scan folder holding — by default — two small REAPER
/// projects, one of them with notes. With [withFixtures], the scan folder
/// holds a copy of the whole DAW project collection instead, for the app's
/// own startup scan to find.
Future<SeededLibrary> seedLibrary({bool withFixtures = false}) async {
  if (!isAppDataDirPinned || !appDataDirName.endsWith('_uitest')) {
    throw StateError(
      'Refusing to wipe "$appDataDirName". Run with '
      '--dart-define=DPM_DATA_DIR=daw_project_manager_uitest.',
    );
  }

  // A fresh library every run.
  final dataDir = Directory(await getLocalAppDataPath());
  if (await dataDir.exists()) await dataDir.delete(recursive: true);

  // Project files the scanner can read: plain-text REAPER projects.
  final projects = Directory(p.join(Directory.systemTemp.path, 'dpm_uitest_projects'));
  if (await projects.exists()) await projects.delete(recursive: true);
  Future<File> reaperProject(String name, int bpm) async {
    final folder = Directory(p.join(projects.path, name));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, '$name.rpp'));
    await file.writeAsString(
      '<REAPER_PROJECT 0.1 "7.0/x64" 1700000000\n  TEMPO $bpm 4 4\n>\n',
    );
    return file;
  }

  final profileRepo = await ProfileRepository.init();
  final profileId = profileRepo.getCurrentProfileId()!;
  final repo = await ProjectRepository.initWithProfile(profileRepo, profileId);
  await repo.addRoot(projects.path);

  if (withFixtures) {
    // Copies: a scan, a deep scan or a move must never write into the
    // checked-in collection.
    await _copyTree(fixtureProjects, projects);
  } else {
    final followMyVoice = await reaperProject('Follow My Voice', 128);
    final teardrop = await reaperProject('Teardrop Remix', 140);
    await repo.upsertFromFileSystemEntity(followMyVoice);
    await repo.upsertFromFileSystemEntity(teardrop);
    final fmv = repo.getByPath(followMyVoice.path)!;
    await repo.updateProject(fmv.copyWith(notes: 'Hook idea: vocal chop in the drop'));
  }

  // Past the first-run screens, onto the card view (its right-click menu is
  // one gesture away).
  final settings = await Hive.openBox<String>('settings');
  await settings.putAll({
    'onboardingComplete': 'true',
    'hidePinnedLibraryWarning': 'true',
    'dashboardViewMode': 'cards',
  });
  // No Drive sync from a test run, even if this library were ever signed
  // in (it keeps a sign-in of its own, never the real app's).
  final appSettings = await Hive.openBox<String>('app_settings');
  await appSettings.putAll({
    'syncOnStartup': 'false',
    'autoBackupInterval': 'off',
  });

  return SeededLibrary(profileId: profileId, projectsFolder: projects);
}

extension Driving on WidgetTester {
  /// Holds the screen for a moment so a person watching can follow.
  Future<void> step() async {
    await pump();
    if (_stepMs > 0) await Future<void>.delayed(const Duration(milliseconds: _stepMs));
    await pump();
  }

  /// Pumps until [finder] finds something, or fails after [timeout]. The app
  /// keeps animating (scanning spinners, timers), so pumpAndSettle may never
  /// settle.
  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $finder');
  }

  /// Pumps until [finder] finds nothing, or fails after [timeout].
  Future<void> pumpUntilGone(
    Finder finder, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isEmpty) return;
    }
    throw TestFailure('Still showing $finder');
  }

  /// Taps [finder] after showing it a moment, then gives the app a beat.
  Future<void> tapAndWait(Finder finder, {int buttons = kPrimaryButton}) async {
    await ensureVisible(finder);
    await step();
    await tap(finder, buttons: buttons);
    await step();
  }
}
