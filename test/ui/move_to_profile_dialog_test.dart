import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/ui/dialogs/move_to_profile_dialog.dart';
import 'package:daw_project_manager/ui/dialogs/root_overlap_dialog.dart';
import 'package:daw_project_manager/utils/root_overlap.dart';

void main() {
  const atlas = MoveTargetProfile(
    id: 'atlas',
    name: 'ATLAS',
    scanFolders: ['/drive/Collabs/ATLAS', '/drive/Collabs/ATLAS 2026'],
  );
  const reisser = MoveTargetProfile(
    id: 'reisser',
    name: 'Audio Crawler vs Reisser',
    scanFolders: [],
  );

  Future<MoveToProfileChoice?> run(
    WidgetTester tester, {
    bool canMoveFiles = true,
    int versionCount = 0,
    List<String> releases = const [],
    Future<void> Function()? interact,
    Future<String?> Function()? pickFolder,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MoveToProfileChoice? choice;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showDialog<MoveToProfileChoice>(
                context: context,
                builder: (_) => MoveToProfileDialog(
                  songName: 'Follow My Voice',
                  sourceProfileName: 'Audio Crawler',
                  targets: const [atlas, reisser],
                  path: '/proton/Audio Crawler/Follow My Voice',
                  pathIsScanned: true,
                  canMoveFiles: canMoveFiles,
                  releaseTitles: releases,
                  versionCount: versionCount,
                  sizeLabel: () async => 'About 12 files (1.2 GB) …',
                  pickFolder: pickFolder ?? () async => null,
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
    if (interact != null) await interact();
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('by default the files stay, and the old profile stops scanning them',
      (tester) async {
    final choice = await run(tester, interact: () async {
      expect(
        find.textContaining('Audio Crawler stops scanning /proton/Audio Crawler/Follow My Voice'),
        findsOneWidget,
      );
    });
    expect(choice!.profileId, 'atlas');
    expect(choice.destinationFolder, isNull);
  });

  testWidgets("moving the files goes into the target's folder, and says how much",
      (tester) async {
    final choice = await run(tester, interact: () async {
      await tester.tap(find.byKey(const ValueKey('move-files')));
      await tester.pumpAndSettle();
      expect(find.text('About 12 files (1.2 GB) …'), findsOneWidget);
    });
    expect(choice!.destinationFolder, '/drive/Collabs/ATLAS');
  });

  Future<void> pickProfile(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('picking the same profile again keeps the folder chosen',
      (tester) async {
    // The bug: any pick in the profile list, the same one included, reset
    // the choice among its folders.
    final choice = await run(tester, interact: () async {
      await tester.tap(find.byKey(const ValueKey('move-files')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('/drive/Collabs/ATLAS 2026'));
      await tester.pumpAndSettle();
      await pickProfile(tester, 'ATLAS');
    });
    expect(choice!.destinationFolder, '/drive/Collabs/ATLAS 2026');
  });

  testWidgets('another profile keeps "move the files" and a folder picked by hand',
      (tester) async {
    final choice = await run(
      tester,
      pickFolder: () async => '/picked/here',
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('move-files')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other folder…'));
        await tester.pumpAndSettle();
        await pickProfile(tester, 'Audio Crawler vs Reisser');
      },
    );
    expect(choice!.profileId, 'reisser');
    expect(choice.destinationFolder, '/picked/here');
  });

  testWidgets('a target with no folders needs one picked', (tester) async {
    final choice = await run(
      tester,
      pickFolder: () async => '/picked/here',
      interact: () async {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Audio Crawler vs Reisser').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('move-files')));
        await tester.pumpAndSettle();
        expect(find.textContaining('no project folders yet'), findsOneWidget);
        final move = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'));
        expect(move.onPressed, isNull, reason: 'nowhere to move the files to yet');
        await tester.tap(find.text('Other folder…'));
        await tester.pumpAndSettle();
      },
    );
    expect(choice!.profileId, 'reisser');
    expect(choice.destinationFolder, '/picked/here');
  });

  testWidgets('a stack across folders can only keep its files', (tester) async {
    final choice = await run(tester, canMoveFiles: false, interact: () async {
      expect(find.textContaining('several folders'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('move-files')));
      await tester.pumpAndSettle();
    });
    expect(choice!.destinationFolder, isNull, reason: 'the option is disabled');
  });

  testWidgets('says the versions move together, and which releases it leaves',
      (tester) async {
    await run(tester, versionCount: 3, releases: ['EP 1', 'Live set'], interact: () async {
      expect(find.text('All 3 versions move together, as one song.'), findsOneWidget);
      expect(find.text('It comes off EP 1, Live set in Audio Crawler.'), findsOneWidget);
    });
  });

  testWidgets('the overlap warning names the profile and the folder', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: RootOverlapDialog(overlaps: [
          RootOverlap(
            profileName: 'ATLAS',
            rootPath: '/drive/Collabs/ATLAS',
            kind: RootOverlapKind.contains,
          ),
        ]),
      ),
    ));
    expect(find.text('Another profile already scans this'), findsOneWidget);
    expect(find.textContaining('ATLAS scans /drive/Collabs/ATLAS, inside this folder.'), findsOneWidget);
    expect(find.text('Add anyway'), findsOneWidget);
  });
}
