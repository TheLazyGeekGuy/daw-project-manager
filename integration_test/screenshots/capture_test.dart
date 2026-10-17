// Captures the screenshots the README and the website's user guide show,
// from the real app, on a library of demo data — never a real one.
//
//   scripts/capture_screenshots.ps1
//
// which runs it with --dart-define=DPM_DATA_DIR=daw_project_manager_screenshots
// (the library it wipes and fills), DPM_HIDE_VERSION=true (no version in
// the title, so the pictures don't date with every release) and
// DPM_SCREENSHOTS=true (no debug-only developer tools).
//
// Writes resources/screenshots/<area>/<name>.png at 1920×1080, in Classic
// Dark. Not part of CI: it is a tool, run when the UI changes enough that
// the pictures no longer match it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/stored_midi_clips.dart';
import 'package:daw_project_manager/repository/midi_clip_store.dart';
import 'package:daw_project_manager/services/metadata_extractor.dart';
import 'package:daw_project_manager/ui/onboarding_wizard_page.dart' show OnboardingWizardPage;
import 'package:daw_project_manager/ui/midi_collection_actions.dart' show collectionItemFor;
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/services/demo_data_service.dart';
import 'package:daw_project_manager/utils/app_paths.dart';

const _size = Size(1920, 1080);

/// What a user never sees, so no picture may show it: the tools for working
/// on the app, which a debug build has unless DPM_SCREENSHOTS hides them.
const _neverInAPicture = [
  'Generate Testing Database',
  'Remove Testing Database',
];

/// A fresh demo library: the demo profiles and nothing else, past the
/// first-run screens.
Future<void> _seed() async {
  if (!isAppDataDirPinned || !appDataDirName.endsWith('_screenshots')) {
    throw StateError('Run with --dart-define=DPM_DATA_DIR=daw_project_manager_screenshots '
        '— this wipes the library it runs on.');
  }
  final dataDir = Directory(await getLocalAppDataPath());
  if (await dataDir.exists()) await dataDir.delete(recursive: true);

  final profiles = await ProfileRepository.init();
  final starter = profiles.getCurrentProfileId()!;
  // Registers the adapters the demo data is written with, as opening the
  // app does before the generator can be reached.
  await ProjectRepository.init(profiles);
  final demo = await DemoDataService().generate(profiles);
  await profiles.setCurrentProfileId(demo.id);
  if (starter != demo.id) await profiles.deleteProfile(starter);

  // The demo projects are empty files: give two of them the MIDI of real
  // projects from the test collection, so the MIDI tab has something in it.
  final projects = await Hive.openBox<MusicProject>('${demo.id}_projects');
  final clips = MidiClipStore(demo.id);
  for (final (name, source) in [
    ('Distant Shore', 'test/fixtures/projects/ableton/Audio Crawler vs Nordic Enigma - NN1 (Live 11)/NN1.als'),
    ('Copper Sun', 'test/fixtures/projects/cubase/Klone - NN (Cubase 5)/NN.cpr'),
  ]) {
    final project = projects.values.firstWhere((x) => x.displayName == name);
    final read = await MetadataExtractor.extractMetadata(source);
    await clips.put(project.id, StoredMidiClips(extractedAt: DateTime.now(), clips: read.midiClips ?? const []));
  }

  // What a lived-in library has: a scan folder, a song in Recently deleted,
  // a MIDI collection with folders — and artists' names, not "Demo — …".
  final repo = await ProjectRepository.initWithProfile(profiles, demo.id);
  // An empty folder of its own: Settings shows a scan folder, and the
  // startup scan adds nothing (the demo files folder holds every demo
  // profile's placeholders and templates).
  // Under the machine's shared Music folder where there is one: the path
  // shows in Settings, and a path under the user's profile names them.
  final shared = Platform.isWindows ? r'C:\Users\Public\Music' : null;
  final scanFolder = Directory(shared != null && Directory(shared).existsSync()
      ? p.join(shared, 'Music Projects')
      : p.join(await getLocalAppDataPath(), 'Music Projects'));
  await scanFolder.create(recursive: true);
  await repo.addRoot(scanFolder.path);
  await repo.deleteProjects([projects.values.firstWhere((x) => x.displayName == 'Ghost Town').id]);
  final collection = await repo.midiCollections.create('Ideas for the EP');
  final basses = await repo.midiCollections.addFolder(collection.id, 'Basslines');
  final leads = await repo.midiCollections.addFolder(collection.id, 'Leads');
  final stored = await clips.getAll();
  final all = [for (final e in stored.entries) for (final c in e.value.clips) (e.key, c)];
  await repo.midiCollections.addItems(collection.id, [
    for (final (i, (id, clip)) in all.take(8).indexed)
      collectionItemFor(clip, projectId: id, bpm: 140).copyWith(folderId: i.isEven ? basses : leads),
  ]);
  for (final profile in profiles.getAllProfiles()) {
    final name = switch (profile.name) {
      DemoDataService.demoProfileName => 'Studio',
      'Demo — Solo Artist' => 'Solo',
      'Demo — Studio B' => 'Collab',
      final other => other,
    };
    await profiles.updateProfile(profile.copyWith(name: name));
  }

  final settings = await Hive.openBox<String>('settings');
  await settings.putAll({
    'onboardingComplete': 'true',
    'hidePinnedLibraryWarning': 'true',
    'warnBeforeQuit': 'false',
    'closeToTray': 'false',
    'dashboardViewMode': 'table',
    // A project's page one section at a time, picked from the rail.
    'projectDetailLayout': 'sectioned',
  });
  final appSettings = await Hive.openBox<String>('app_settings');
  await appSettings.putAll({'syncOnStartup': 'false', 'autoBackupInterval': 'off'});
}

extension on WidgetTester {
  /// Lets animations and async loads finish without waiting on anything
  /// that never settles (a playing preview, a spinner).
  Future<void> settle([int frames = 15]) async {
    for (var i = 0; i < frames; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Never showed $finder');
  }

  Future<void> tapOn(Finder finder) async {
    await until(finder);
    await tap(finder.first);
    await settle(8);
  }

  /// A dashboard tab, by its icon in the side rail.
  Future<void> openTab(IconData icon) =>
      tapOn(find.descendant(of: find.byType(NavigationRail), matching: find.byIcon(icon)));

  /// The project's right-click menu, then one of its entries.
  Future<void> projectMenu(String project, String entry) async {
    final target = find.text(project).first;
    await until(target);
    final mouse = await createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.addPointer(location: getCenter(target));
    await mouse.down(getCenter(target));
    await pump();
    await mouse.up();
    await mouse.removePointer();
    await settle(5);
    await tapOn(find.text(entry));
  }

  Future<void> back() async {
    await tapOn(find.byIcon(Icons.arrow_back).hitTestable());
    await settle(8);
  }

  /// Writes what is on screen to resources/screenshots/[path].
  /// [crop], a part of the window, frames one thing — a wizard, a dialog.
  /// Refuses a picture with a developer tool in it (see [_neverInAPicture]).
  Future<void> shot(String path, {Rect? crop}) async {
    await settle();
    for (final text in _neverInAPicture) {
      if (find.text(text).hitTestable().evaluate().isNotEmpty) {
        throw TestFailure('$path shows "$text", a developer tool: run with --dart-define=DPM_SCREENSHOTS=true');
      }
    }
    final view = binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final bounds = (crop ?? Offset.zero & view.size).intersect(Offset.zero & view.size);
    final image = await layer.toImage(bounds, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(p.join('resources', 'screenshots', path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('SCREENSHOT $path');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshots', (tester) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1;
    await _seed();
    final errorWidgetBuilder = ErrorWidget.builder;
    WidgetsApp.debugAllowBannerOverride = false;
    app.main(const []);

    await tester.until(find.text('Distant Shore'));

    // One screen at a time: a screen that can't be reached is reported and
    // skipped, the rest still taken.
    final failed = <String>[];
    Future<void> screen(String name, Future<void> Function() steps) async {
      try {
        await steps();
      } catch (e) {
        failed.add('$name: ${'$e'.split('\n').first}');
        debugPrint('SKIPPED $name: $e');
      }
    }

    await screen('dashboard', () async {
      await tester.shot('dashboard/dashboard-overview.png');
      // Table | Cards, a segmented button: its right half, then its left.
      final toggle = find.byWidgetPredicate((w) => w is SegmentedButton);
      await tester.until(toggle);
      final box = tester.getRect(toggle.first);
      await tester.tapAt(Offset(box.right - box.width / 4, box.center.dy));
      await tester.settle(20);
      await tester.shot('dashboard/dashboard-cards.png');
      await tester.tapAt(Offset(box.left + box.width / 4, box.center.dy));
      await tester.settle(20);
    });

    await screen('search', () async {
      final search = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Search projects'),
      );
      await tester.tapOn(search);
      // A project's name: search matches names, notes, markers, plug-ins,
      // tags and custom fields — not the DAW, which has a filter of its own.
      await tester.enterText(search.first, 'night');
      await tester.shot('dashboard/dashboard-filters-search.png');
      await tester.enterText(search.first, '');
      await tester.settle();
    });

    await screen('bulk', () async {
      // The rows' own checkboxes: after the three filters and select-all.
      final boxes = find.byType(Checkbox).hitTestable();
      await tester.until(boxes);
      for (final i in [5, 7, 8]) {
        await tester.tap(boxes.at(i));
        await tester.pump();
      }
      await tester.shot('dashboard/dashboard-bulk-actions.png');
      for (final i in [5, 7, 8]) {
        await tester.tap(boxes.at(i));
        await tester.pump();
      }
      await tester.settle();
    });

    await screen('project detail', () async {
      await tester.projectMenu('Distant Shore', 'View Details');
      await tester.until(find.text('Notes'));
      await tester.shot('project-detail/project-detail-metadata.png');
      // Other sections, from the rail on the left: its work sessions…
      await tester.tapOn(find.text('Session History').hitTestable().first);
      await tester.shot('work-sessions/session-history.png');
      await tester.back();
      // …and the to-dos of a song still being arranged: Distant Shore's are done.
      await tester.projectMenu('Fever Dream', 'View Details');
      await tester.tapOn(find.text('TODO List').hitTestable().first);
      await tester.shot('project-detail/project-detail-todos.png');
      await tester.back();
    });

    await screen('releases', () async {
      await tester.openTab(Icons.album);
      await tester.shot('releases/releases-list.png');
      // The first release's own details button — not the pinned project's
      // in the top bar, which looks the same.
      final details = find.byIcon(Icons.assignment).hitTestable();
      await tester.until(details);
      final inTable = details.evaluate().map((e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero))
          .where((o) => o.dy > 200)
          .reduce((a, b) => a.dy <= b.dy ? a : b);
      await tester.tapAt(inTable + const Offset(8, 8));
      await tester.settle(20);
      await tester.shot('releases/release-detail.png');
      await tester.back();
    });

    await screen('MIDI', () async {
      await tester.openTab(Icons.piano);
      await tester.shot('midi/midi-library.png');
      await tester.tapOn(find.text('Ideas for the EP'));
      // Every folder open, in the side list and in the collection.
      final expandAll = find.byTooltip('Expand all').hitTestable();
      await tester.until(expandAll);
      for (final button in expandAll.evaluate().toList()) {
        await tester.tapAt((button.renderObject! as RenderBox).localToGlobal(const Offset(8, 8)));
        await tester.settle(5);
      }
      await tester.shot('midi/midi-collection.png');
      await tester.tapOn(find.text('All clips'));
      await tester.tapOn(find.byTooltip('Open piano roll').hitTestable());
      await tester.shot('midi/midi-piano-roll.png');
      await tester.tapOn(find.byIcon(Icons.close).hitTestable().last);
    });

    await screen('tasks', () async {
      await tester.openTab(Icons.checklist);
      await tester.shot('task-queue/task-queue-overview.png');
    });

    await screen('statistics', () async {
      await tester.openTab(Icons.bar_chart_rounded);
      await tester.shot('statistics/statistics-global-overview.png');
    });

    await screen('player', () async {
      await tester.openTab(Icons.headphones);
      final track = find.text('Distant Shore').hitTestable();
      await tester.until(track);
      await tester.tap(track.first);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(track.first);
      await tester.settle(20);
      await tester.shot('music-player/music-player-desktop.png');
    });

    await screen('profiles', () async {
      await tester.openTab(Icons.library_music);
      await tester.tapOn(find.byIcon(Icons.person).hitTestable());
      await tester.until(find.text('Profile Manager'));
      await tester.shot('profiles/profile-manager.png');
      await tester.back();
    });

    await screen('settings', () async {
      await tester.tapOn(find.text('Settings').hitTestable());
      await tester.until(find.text('Project Folders'));
      await tester.shot('settings/settings-general.png');
      for (final (section, file) in [
        ('Project Folders', 'settings-project-folders.png'),
        ('Phases', 'settings-phases-customize.png'),
        ('Appearance', 'settings-appearance.png'),
        ('Columns & fields', 'settings-columns-fields.png'),
        ('Backup', 'settings-backup.png'),
      ]) {
        await tester.tapOn(find.text(section).first);
        await tester.shot('settings/$file');
      }
      await tester.back();
    });

    // Google Drive, signed out: the demo library has no account, and a
    // signed-in page would show one.
    await screen('google drive', () async {
      await tester.openTab(Icons.library_music);
      await tester.tapOn(find.text('Google Drive').hitTestable());
      await tester.settle(20);
      // Signed out it opens Settings → Backup: frame its two Drive cards.
      final top = tester.getRect(find.text('Google Drive Sync').hitTestable().first).top;
      final bottom = tester.getRect(find.text('Upload auto-detected preview songs').hitTestable().first).bottom;
      await tester.shot('google-drive-sync/drive-sync.png',
          crop: Rect.fromLTRB(256, top - 44, _size.width - 10, bottom + 48));
      await tester.back();
    });

    // Session Mode: switched on, a session started on a project, its time.
    await screen('work sessions', () async {
      await tester.tapOn(find.text('Settings').hitTestable());
      await tester.tapOn(find.text('Work Sessions').hitTestable().first);
      // The option, not the card's title above it: the last "Session mode".
      await tester.tapOn(find.text('Session mode').hitTestable().last);
      await tester.settle(10);
      await tester.shot('work-sessions/settings-session-mode.png');
      await tester.back();

      await tester.openTab(Icons.library_music);
      final start = find.byTooltip('Start Session (S)').hitTestable();
      await tester.until(start);
      await tester.tap(start.first);
      final dialog = find.byType(AlertDialog);
      await tester.until(dialog);
      await tester.shot('work-sessions/session-start.png');
      await tester.tapOn(find.descendant(of: dialog, matching: find.text('Start Session')).last);
      // Real seconds: the timer counts wall-clock time.
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.shot('work-sessions/session-running.png');
      // The session bar on its own: the song, its total, this session's time.
      final bar = find.ancestor(
        of: find.text('Distant Shore').hitTestable().first,
        matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
      );
      await tester.shot('work-sessions/session-bar.png', crop: tester.getRect(bar.first).inflate(12));

      // In Session Mode the menu's first entry starts a session: the row's
      // details button opens the page.
      final details = find.byIcon(Icons.assignment).hitTestable();
      await tester.until(details);
      final firstRow = details.evaluate().map((e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero))
          .where((o) => o.dy > 200)
          .reduce((a, b) => a.dy <= b.dy ? a : b);
      await tester.tapAt(firstRow + const Offset(8, 8));
      await tester.until(find.text('Notes'));
      await tester.shot('work-sessions/session-project-time.png');
      await tester.back();
    });

    // Last, because it ends the session: the setup wizard, framed on its
    // first page — Settings → General → Reset onboarding.
    await screen('wizard', () async {
      await tester.tapOn(find.text('Settings').hitTestable());
      await tester.tapOn(find.text('Reset onboarding').hitTestable());
      await tester.tapOn(find.widgetWithText(FilledButton, 'Reset onboarding'));
      final wizard = find.byType(OnboardingWizardPage);
      await tester.until(wizard);
      await tester.settle(20);
      // A step's own column, with room around it for what frames it.
      Rect column(double width) => tester.getRect(find
          .descendant(
            of: wizard,
            matching: find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.maxWidth == width),
          )
          .first);
      final welcome = column(560);
      await tester.shot('onboarding/onboarding-welcome.png',
          crop: Rect.fromLTRB(welcome.left - 140, welcome.top - 8, welcome.right + 140, welcome.bottom + 48));

      // Language, Theme, Tabs, then the project page's layout.
      for (var i = 0; i < 4; i++) {
        await tester.tapOn(find.widgetWithText(FilledButton, 'Next'));
      }
      await tester.until(find.text('Project pages'));
      final layout = column(760);
      await tester.shot('onboarding/onboarding-detail-layout.png',
          crop: Rect.fromLTRB(layout.left - 60, layout.top - 8, layout.right + 60, layout.bottom + 40));
    });

    debugPrint('SCREENSHOTS SKIPPED: ${failed.isEmpty ? 'none' : failed.join(' | ')}');

    ErrorWidget.builder = errorWidgetBuilder;
  }, timeout: const Timeout(Duration(minutes: 10)));
}
