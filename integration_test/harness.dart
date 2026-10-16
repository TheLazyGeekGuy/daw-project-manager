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
import 'package:flutter/material.dart' show IconData, Icons, NavigationRail, SnackBar;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/ui/dashboard_page.dart' show RailAction;
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/utils/app_paths.dart';

/// How long each step is held on screen. Full speed by default (CI, and
/// most local runs); `--dart-define=UITEST_STEP_MS=800` slows it down enough
/// to watch.
const _stepMs = int.fromEnvironment('UITEST_STEP_MS');

/// The library seeded for a test.
class SeededLibrary {
  SeededLibrary({
    required this.profileId,
    required this.projectsFolder,
    this.otherProfileId,
    this.otherProjectsFolder,
  });
  final String profileId;
  final Directory projectsFolder;

  /// With `secondProfile:`, another artist's profile and its scan folder.
  final String? otherProfileId;
  final Directory? otherProjectsFolder;
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
/// own startup scan to find; with [fixtures] (`'<daw>/<name>'` each), just
/// those of it — a deep scan of one project is quicker than of them all.
///
/// With [secondProfile], a second profile of that name is created too, with
/// an empty scan folder of its own — somewhere to move a song to.
Future<SeededLibrary> seedLibrary({
  bool withFixtures = false,
  List<String>? fixtures,
  String? secondProfile,
}) async {
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
  } else if (fixtures != null) {
    for (final f in fixtures) {
      await _copyTree(Directory(p.join(fixtureProjects.path, f)), Directory(p.join(projects.path, f)));
    }
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
    // So the app quits when the test tool closes it. "Warn before quitting"
    // (on by default) kept the window open on its confirmation, and the
    // next test file's app could not start beside it.
    'warnBeforeQuit': 'false',
    'closeToTray': 'false',
  });
  // No Drive sync from a test run, even if this library were ever signed
  // in (it keeps a sign-in of its own, never the real app's).
  final appSettings = await Hive.openBox<String>('app_settings');
  await appSettings.putAll({
    'syncOnStartup': 'false',
    'autoBackupInterval': 'off',
  });

  String? otherId;
  Directory? otherFolder;
  if (secondProfile != null) {
    final other = await profileRepo.createProfile(secondProfile);
    otherId = other.id;
    otherFolder = Directory(p.join(Directory.systemTemp.path, 'dpm_uitest_${other.id.substring(0, 8)}'));
    if (await otherFolder.exists()) await otherFolder.delete(recursive: true);
    await otherFolder.create(recursive: true);
    final otherRepo = await ProjectRepository.initWithProfile(profileRepo, other.id);
    await otherRepo.addRoot(otherFolder.path);
    // createProfile can make the new one current: the test starts on the first.
    await profileRepo.setCurrentProfileId(profileId);
  }

  return SeededLibrary(
    profileId: profileId,
    projectsFolder: projects,
    otherProfileId: otherId,
    otherProjectsFolder: otherFolder,
  );
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

  /// The page's own back button, as a person would leave it.
  Future<void> goBack() async {
    await tapAndWait(find.byIcon(Icons.arrow_back).hitTestable().first);
    await settleTransition();
  }

  /// Opens a dashboard tab from the side rail, by its icon (the rail shows
  /// no labels), and lets the tab slide in.
  Future<void> openTab(IconData icon) async {
    await tapAndWait(
      find.descendant(of: find.byType(NavigationRail), matching: find.byIcon(icon)).first,
    );
    await settleTransition();
  }

  /// Presses one of the side rail's actions (Deep Scan, Settings…) by its
  /// label. On a short screen the rail scrolls and the last ones sit below
  /// the fold, so it is found as it is, never `hitTestable()` — tapping
  /// scrolls it into view first.
  Future<void> tapRailAction(String label) async {
    await tapAndWait(
      find.byWidgetPredicate((w) => w is RailAction && w.label == label).first,
    );
  }

  /// Closes the snackbar on screen with its own close button — once it has
  /// slid in far enough to take the tap. (A bare `Icons.close` can be the
  /// window's own, which quits the app.)
  Future<void> closeSnackBar() async {
    final close = find
        .descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.close))
        .hitTestable();
    await pumpUntilFound(close);
    await settleTransition();
    await tapAndWait(close.first);
    await pumpUntilGone(find.byType(SnackBar));
  }

  /// Lets a page transition finish: the navigator ignores pointers while a
  /// route animates, so a click straight after "back" goes nowhere.
  Future<void> settleTransition() async {
    for (var i = 0; i < 8; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }

  /// A real right-click: a mouse pointer, secondary button — what opens a
  /// project's menu.
  Future<void> rightClick(Finder finder) async {
    await ensureVisible(finder);
    await step();
    // Added, moved there, pressed, released and removed — as a real mouse
    // does. A bare tapAt with a mouse left the device added, and the next
    // right-click was dropped.
    final mouse = await createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: getCenter(finder));
    await pump();
    await mouse.down(getCenter(finder));
    await pump();
    await mouse.up();
    await mouse.removePointer();
    await step();
  }

  /// Taps [finder] after showing it a moment, then gives the app a beat.
  Future<void> tapAndWait(Finder finder, {int buttons = kPrimaryButton}) async {
    await ensureVisible(finder);
    await step();
    await tap(finder, buttons: buttons);
    await step();
  }
}
