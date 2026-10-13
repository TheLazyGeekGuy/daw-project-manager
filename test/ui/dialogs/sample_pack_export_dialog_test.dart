import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/sample_pack/sample_pack_exporter.dart';
import 'package:daw_project_manager/ui/dialogs/sample_pack_export_dialog.dart';
import 'package:daw_project_manager/ui/widgets/sample_pack_card.dart';

Widget _app(Widget Function(BuildContext) open) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: open,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  const profiles = [
    SamplePackProfileChoice(id: 'p1', name: 'Audio Crawler'),
    SamplePackProfileChoice(id: 'p2', name: 'Side project'),
    SamplePackProfileChoice(id: 'p3', name: 'Label'),
  ];
  const projects = [
    SamplePackProjectChoice(
        id: 'nebula', profileId: 'p1', name: 'Nebula', detail: 'Nebula.cpr'),
    SamplePackProjectChoice(
        id: 'teardrop',
        profileId: 'p1',
        name: 'Teardrop Remix',
        detail: 'Teardrop.cpr'),
    SamplePackProjectChoice(
        id: 'honor', profileId: 'p1', name: 'Honor', detail: 'Honor.cpr'),
    SamplePackProjectChoice(
        id: 'jam', profileId: 'p2', name: 'Jam', detail: 'jam.flp'),
  ];

  group('SamplePackExportDialog', () {
    late SamplePackExportChoice? result;
    late List<String?> picks;

    Future<void> pump(
      WidgetTester tester, {
      Set<String> initial = const {'p1', 'p2', 'p3'},
      List<String> folders = const [],
      bool onlyPicked = false,
      Set<String> picked = const {},
      Size window = const Size(1000, 2000),
    }) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      result = null;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<SamplePackExportChoice>(
                  context: context,
                  builder: (_) => SamplePackExportDialog(
                    profiles: profiles,
                    projects: projects,
                    initialProfileIds: initial,
                    initialOnlyPicked: onlyPicked,
                    initialPickedProjectIds: picked,
                    initialLibraryFolders: folders,
                    initialIncludeOwnAudio: false,
                    initialIncludeMidi: true,
                    initialExcludeMasterProjects: true,
                    pickFolder: () async =>
                        picks.isEmpty ? null : picks.removeAt(0),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    setUp(() => picks = []);

    bool ticked(WidgetTester tester, String id) => tester
        .widget<FilterChip>(find.byKey(ValueKey('samplePackProfile-$id')))
        .selected;

    Finder exportButton() =>
        find.widgetWithText(FilledButton, 'Choose folder and export');

    testWidgets('lists every profile with its project count', (tester) async {
      await pump(tester);
      expect(find.text('Audio Crawler (3)'), findsOneWidget);
      expect(find.text('Side project (1)'), findsOneWidget);
      expect(find.text('Label (0)'), findsOneWidget);
    });

    testWidgets('select none, then pick some; export returns them in order',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Select none'));
      await tester.pump();
      expect(ticked(tester, 'p1') || ticked(tester, 'p2'), isFalse);
      expect(tester.widget<FilledButton>(exportButton()).onPressed, isNull,
          reason: 'nothing to export without a profile');

      await tester.tap(find.text('Label (0)'));
      await tester.tap(find.text('Audio Crawler (3)'));
      await tester.pump();
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.profileIds, ['p1', 'p3']);
      expect(result!.projectIds, isNull, reason: 'every project in them');
      expect(result!.includeMidi, isTrue);
      expect(result!.includeOwnAudio, isFalse);
      expect(result!.excludeMasterProjects, isTrue);
    });

    testWidgets('select all ticks every profile and then disables itself',
        (tester) async {
      await pump(tester, initial: {'p2'});
      expect(ticked(tester, 'p1'), isFalse);
      await tester.tap(find.text('Select all').first);
      await tester.pump();
      expect(['p1', 'p2', 'p3'].every((id) => ticked(tester, id)), isTrue);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Select all'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a remembered profile that is gone is ignored', (tester) async {
      await pump(tester, initial: {'deleted', 'p2'});
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.profileIds, ['p2']);
    });

    group('picking projects', () {
      testWidgets('lists the selected profiles\' projects by name; exports '
          'only the ticked ones', (tester) async {
        await pump(tester, initial: {'p1'});
        await tester.tap(find.text('Choose projects'));
        await tester.pumpAndSettle();
        expect(find.text('Jam'), findsNothing, reason: 'p2 is not selected');
        final names = tester
            .widgetList<CheckboxListTile>(find.byWidgetPredicate((w) =>
                w is CheckboxListTile &&
                (w.key as ValueKey?)?.value.toString().startsWith(
                        'samplePackProject-') ==
                    true))
            .map((w) => (w.title as Text).data)
            .toList();
        expect(names, ['Honor', 'Nebula', 'Teardrop Remix']);
        expect(find.text('No projects picked'), findsOneWidget);
        expect(tester.widget<FilledButton>(exportButton()).onPressed, isNull,
            reason: 'picking, but nothing picked');

        await tester.tap(find.text('Teardrop Remix'));
        await tester.pump();
        expect(find.text('1 project picked'), findsOneWidget);
        await tester.tap(exportButton());
        await tester.pumpAndSettle();
        expect(result!.projectIds, ['teardrop']);
      });

      testWidgets('search narrows the list, and select all picks only what '
          'it shows', (tester) async {
        await pump(tester, initial: {'p1', 'p2'});
        await tester.tap(find.text('Choose projects'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('samplePackProjectSearch')), 'n');
        await tester.pump();
        // By name or file name: "Nebula" and "Honor" have an n; "Teardrop
        // Remix" (Teardrop.cpr) and "Jam" (jam.flp) don't.
        expect(find.text('Jam'), findsNothing);
        expect(find.text('Teardrop Remix'), findsNothing);
        expect(find.text('Nebula'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('samplePackPickAll')));
        await tester.pump();
        await tester.enterText(
            find.byKey(const ValueKey('samplePackProjectSearch')), 'zzz');
        await tester.pump();
        expect(find.text('No projects match.'), findsOneWidget);
        await tester.tap(exportButton());
        await tester.pumpAndSettle();
        expect(result!.projectIds, ['nebula', 'honor']);
      });

      testWidgets('picks in a profile that gets unticked are not exported',
          (tester) async {
        await pump(tester,
            onlyPicked: true, picked: {'nebula', 'jam'}, initial: {'p1', 'p2'});
        expect(find.text('2 projects picked'), findsOneWidget);
        await tester.tap(find.text('Side project (1)'));
        await tester.pump();
        expect(find.text('1 project picked'), findsOneWidget);
        await tester.tap(exportButton());
        await tester.pumpAndSettle();
        expect(result!.projectIds, ['nebula']);
      });

      testWidgets('going back to all projects exports every project',
          (tester) async {
        await pump(tester, onlyPicked: true, picked: {'nebula'});
        await tester.tap(find.text('All projects'));
        await tester.pumpAndSettle();
        await tester.tap(exportButton());
        await tester.pumpAndSettle();
        expect(result!.projectIds, isNull);
      });
    });

    testWidgets('renaming is off unless ticked; its parts and prefix come '
        'back in the choice, with a live example', (tester) async {
      await pump(tester);
      expect(find.text('Original name'), findsNothing);
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.naming, isNull, reason: 'names are kept by default');

      await pump(tester);
      await tester.tap(find.text('Rename samples'));
      await tester.pump();
      expect(
        find.text(
            'Example: Bass 001 - rolling bassline - 145 BPM - F#m.wav'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Key'));
      await tester.enterText(
          find.byKey(const ValueKey('samplePackRenamePrefix')), 'AC');
      await tester.pump();
      expect(
        find.text('Example: AC Bass 001 - rolling bassline - 145 BPM.wav'),
        findsOneWidget,
      );
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.naming, isNotNull);
      expect(result!.naming!.includeKey, isFalse);
      expect(result!.naming!.includeName, isTrue);
      expect(result!.naming!.prefix, 'AC');
    });

    testWidgets('on a wide window the two halves sit side by side and the '
        'whole dialog fits', (tester) async {
      await pump(tester,
          window: const Size(1920, 1080), onlyPicked: true, picked: {'nebula'});
      await tester.tap(find.text('Rename samples'));
      await tester.pump();
      final profiles = tester.getTopLeft(find.text('Profiles'));
      final folders = tester.getTopLeft(find.text('Sample library folders'));
      expect(folders.dx, greaterThan(profiles.dx + 300),
          reason: 'library folders start the right-hand half');
      expect((folders.dy - profiles.dy).abs(), lessThan(24));
      expect(tester.getBottomLeft(find.text('Choose folder and export')).dy,
          lessThan(1080),
          reason: 'everything on screen without scrolling');
      expect(
        tester.getBottomLeft(find.textContaining('Example: ')).dy,
        lessThan(tester.getTopLeft(find.text('Choose folder and export')).dy),
      );
    });

    testWidgets('on a narrow window it is one column', (tester) async {
      await pump(tester, window: const Size(800, 2400));
      final profiles = tester.getTopLeft(find.text('Profiles'));
      final folders = tester.getTopLeft(find.text('Sample library folders'));
      expect((folders.dx - profiles.dx).abs(), lessThan(24));
      expect(folders.dy, greaterThan(profiles.dy));
    });

    testWidgets('master projects can be let back in', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Leave out master projects'));
      await tester.pump();
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.excludeMasterProjects, isFalse);
    });

    testWidgets('library folders are added once and can be removed',
        (tester) async {
      await pump(tester, folders: ['/old/lib']);
      picks = ['/new/lib', '/new/lib', null];
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Add Folder'));
        await tester.pumpAndSettle();
      }
      expect(find.text('/new/lib'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, '/old/lib'),
        matching: find.byIcon(Icons.delete_outline),
      ));
      await tester.pump();
      await tester.tap(find.text('Include my recordings, bounces and stems'));
      await tester.tap(find.text('Add my MIDI collections'));
      await tester.pump();
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(result!.libraryFolders, ['/new/lib']);
      expect(result!.includeOwnAudio, isTrue);
      expect(result!.includeMidi, isFalse);
    });

    testWidgets('cancel returns nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  testWidgets('the progress dialog shows the project and the step, and Stop '
      'asks to stop', (tester) async {
    final finish = Completer<SamplePackResult>();
    late SamplePackProgress report;
    late bool Function() stop;
    await tester.pumpWidget(_app((_) => SamplePackProgressDialog(
          run: (onProgress, shouldStop) {
            report = onProgress;
            stop = shouldStop;
            return finish.future;
          },
        )));
    await tester.tap(find.text('open'));
    await tester.pump();

    report(const SamplePackProgressUpdate(
      project: 1,
      projects: 4,
      projectName: 'Nebula',
      phase: SamplePackPhase.copying,
      done: 4,
      total: 10,
      current: 'Kick/kick.wav',
    ));
    await tester.pump();
    expect(find.text('Reading project 2 of 4: Nebula'), findsOneWidget);
    expect(find.text('Copying 5 of 10: Kick/kick.wav'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo((1 + 0.4) / 4, 1e-9),
    );
    expect(stop(), isFalse);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(stop(), isTrue);

    finish.complete(const SamplePackResult(
      samples: [],
      problems: [],
      projectsRead: 0,
      midiFiles: 0,
      stopped: true,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SamplePackProgressDialog), findsNothing);
  });

  testWidgets('the result dialog says what happened and opens the folder',
      (tester) async {
    var opened = 0;
    final added = PackSample()
      ..packPath = 'Kick/a.wav'
      ..added = true;
    final already = PackSample()..packPath = 'Kick/b.wav';
    final leftOut = PackSample();
    await tester.pumpWidget(_app((_) => SamplePackResultDialog(
          result: SamplePackResult(
            samples: [added, already, leftOut],
            problems: const [
              SamplePackProblem(
                project: 'Song',
                profile: 'Main',
                problem: SamplePackProblemKind.sampleNotFound,
              ),
            ],
            projectsRead: 1,
            midiFiles: 3,
            stopped: false,
            masterProjectsLeftOut: 2,
          ),
          onOpenFolder: () => opened++,
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Sample pack ready'), findsOneWidget);
    expect(find.text('• 1 new sample added'), findsOneWidget);
    expect(find.text('• 1 was already in the folder'), findsOneWidget);
    expect(find.text('• 1 recording, bounce or stem left out'), findsOneWidget);
    expect(find.text('• 3 MIDI files written'), findsOneWidget);
    expect(find.text('• 2 master projects left out'), findsOneWidget);
    expect(find.textContaining(kSamplePackProblems), findsOneWidget);
    await tester.tap(find.text('Open Folder'));
    expect(opened, 1);
  });

  testWidgets('the settings card exports, unless something else is running',
      (tester) async {
    var exports = 0;
    Future<void> pumpCard(bool busy) => tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SamplePackCard(busy: busy, onExport: () => exports++),
          ),
        ));
    await pumpCard(false);
    expect(find.text('Sample pack from your projects'), findsOneWidget);
    await tester.tap(find.text('Export'));
    expect(exports, 1);
    await pumpCard(true);
    await tester.tap(find.text('Export'));
    expect(exports, 1);
  });
}
