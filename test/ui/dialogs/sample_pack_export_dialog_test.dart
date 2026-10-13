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
    SamplePackProfileChoice(id: 'p1', name: 'Audio Crawler', projectCount: 40),
    SamplePackProfileChoice(id: 'p2', name: 'Side project', projectCount: 1),
    SamplePackProfileChoice(id: 'p3', name: 'Label', projectCount: 12),
  ];

  group('SamplePackExportDialog', () {
    late SamplePackExportChoice? result;
    late List<String?> picks;

    Future<void> pump(
      WidgetTester tester, {
      Set<String> initial = const {'p1', 'p2', 'p3'},
      List<String> folders = const [],
    }) async {
      tester.view.physicalSize = const Size(1000, 1600);
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
                    initialProfileIds: initial,
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

    Finder box(String id) => find.descendant(
          of: find.byKey(ValueKey('samplePackProfile-$id')),
          matching: find.byType(Checkbox),
        );

    bool ticked(WidgetTester tester, String id) =>
        tester.widget<Checkbox>(box(id)).value ?? false;

    testWidgets('lists every profile with its project count', (tester) async {
      await pump(tester);
      expect(find.text('Audio Crawler'), findsOneWidget);
      expect(find.text('40 projects'), findsOneWidget);
      expect(find.text('1 project'), findsOneWidget);
    });

    testWidgets('select none, then pick some; export returns them in order',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Select none'));
      await tester.pump();
      expect(ticked(tester, 'p1') || ticked(tester, 'p2'), isFalse);
      final export = find.widgetWithText(FilledButton, 'Choose folder and export');
      expect(tester.widget<FilledButton>(export).onPressed, isNull,
          reason: 'nothing to export without a profile');

      await tester.tap(find.text('Label'));
      await tester.tap(find.text('Audio Crawler'));
      await tester.pump();
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(result!.profileIds, ['p1', 'p3']);
      expect(result!.includeMidi, isTrue);
      expect(result!.includeOwnAudio, isFalse);
      expect(result!.excludeMasterProjects, isTrue);
    });

    testWidgets('master projects can be let back in', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Leave out master projects'));
      await tester.pump();
      await tester.tap(find.text('Choose folder and export'));
      await tester.pumpAndSettle();
      expect(result!.excludeMasterProjects, isFalse);
    });

    testWidgets('select all ticks every profile and then disables itself',
        (tester) async {
      await pump(tester, initial: {'p2'});
      expect(ticked(tester, 'p1'), isFalse);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(['p1', 'p2', 'p3'].every((id) => ticked(tester, id)), isTrue);
      expect(
        tester.widget<TextButton>(
            find.widgetWithText(TextButton, 'Select all')).onPressed,
        isNull,
      );
    });

    testWidgets('a remembered profile that is gone is ignored', (tester) async {
      await pump(tester, initial: {'deleted', 'p2'});
      await tester.tap(find.text('Choose folder and export'));
      await tester.pumpAndSettle();
      expect(result!.profileIds, ['p2']);
    });

    testWidgets('library folders are added once and can be removed',
        (tester) async {
      await pump(tester, folders: ['/old/lib']);
      picks = ['/new/lib', '/new/lib', null];
      await tester.tap(find.text('Add Folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Folder')); // cancelled
      await tester.pumpAndSettle();
      expect(find.text('/new/lib'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, '/old/lib'),
        matching: find.byIcon(Icons.delete_outline),
      ));
      await tester.pump();
      await tester.tap(find.text('Include my recordings, bounces and stems'));
      await tester.tap(find.text('Add my MIDI collections'));
      await tester.pump();
      await tester.tap(find.text('Choose folder and export'));
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

  testWidgets('the progress dialog shows each step and Stop asks to stop',
      (tester) async {
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

    report(SamplePackPhase.copying, 4, 10, 'Kick/kick.wav');
    await tester.pump();
    expect(find.text('Copying 5 of 10: Kick/kick.wav'), findsOneWidget);
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
    final added = PackSample('a')
      ..packPath = 'Kick/a.wav'
      ..added = true;
    final already = PackSample('b')..packPath = 'Kick/b.wav';
    final leftOut = PackSample('c');
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
