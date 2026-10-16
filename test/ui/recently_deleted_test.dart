import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/repository/project_trash.dart';
import 'package:daw_project_manager/ui/dialogs/delete_project_dialog.dart';
import 'package:daw_project_manager/ui/recently_deleted_actions.dart' show pathAScanWouldFind;
import 'package:daw_project_manager/ui/widgets/recently_deleted_card.dart';

import '../helpers/test_factories.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  Widget app(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('pathAScanWouldFind', () {
    final root = p.join(Directory.systemTemp.path, 'songs');
    final ownFolder = p.join(root, 'Follow My Voice', 'Follow My Voice.cpr');
    final shared = p.join(root, 'loose', 'a.als');
    final sharedNeighbour = p.join(root, 'loose', 'b.als');

    test('outside every scan folder: nothing would bring it back', () {
      final project = TestFactories.makeProject(
        id: 'x',
        filePath: p.join(Directory.systemTemp.path, 'elsewhere', 'x.cpr'),
      );
      expect(pathAScanWouldFind(project, [root], [project.filePath]), isNull);
    });

    test('in a folder of its own: that folder', () {
      final project = TestFactories.makeProject(id: 'x', filePath: ownFolder);
      final found = pathAScanWouldFind(project, [root], [ownFolder, shared]);
      expect(found?.path, p.dirname(ownFolder));
      expect(found?.isFolder, isTrue);
    });

    test('sharing its folder: just its file', () {
      final project = TestFactories.makeProject(id: 'x', filePath: shared);
      final found = pathAScanWouldFind(project, [root], [shared, sharedNeighbour]);
      expect(found?.path, shared);
      expect(found?.isFolder, isFalse);
    });
  });

  group('delete dialog', () {
    Future<DeleteProjectChoice?> open(
      WidgetTester tester, {
      String? scannedPath,
      bool tapCheckbox = false,
    }) async {
      DeleteProjectChoice? choice;
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            choice = await showDeleteProjectDialog(
              context,
              projectName: 'Follow My Voice',
              scannedPath: scannedPath,
              scannedPathIsFolder: true,
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Follow My Voice"?'), findsOneWidget);
      if (tapCheckbox) await tester.tap(find.byType(Checkbox));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      return choice;
    }

    testWidgets('inside a scan folder: offers to stop scanning it, ticked',
        (tester) async {
      final choice = await open(tester, scannedPath: '/music/Follow My Voice');
      expect(choice!.stopScanning, isTrue);
    });

    testWidgets('the offer can be declined', (tester) async {
      final choice = await open(
        tester,
        scannedPath: '/music/Follow My Voice',
        tapCheckbox: true,
      );
      expect(choice!.stopScanning, isFalse);
    });

    testWidgets('outside scan folders: no offer', (tester) async {
      DeleteProjectChoice? choice;
      await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            choice = await showDeleteProjectDialog(context, projectName: 'X');
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(choice!.stopScanning, isFalse);
    });
  });

  group('RecentlyDeletedCard', () {
    final now = DateTime(2026, 10, 16, 12);

    testWidgets('lists what was deleted, when, and how long it stays',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(app(RecentlyDeletedCard(
        items: [
          TrashedProject(
            project: TestFactories.makeProject(id: 'fmv', customDisplayName: 'Follow My Voice'),
            deletedAt: now.subtract(const Duration(days: 2)),
          ),
        ],
        now: now,
        onRestore: (t) => calls.add('restore:${t.project.id}'),
        onDeleteForever: (t) => calls.add('forever:${t.project.id}'),
        onEmpty: () => calls.add('empty'),
      )));

      expect(find.text('Follow My Voice'), findsOneWidget);
      expect(find.textContaining('Deleted 2 days ago'), findsOneWidget);
      expect(find.textContaining('gone for good in 28 days'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await tester.tap(find.byTooltip('Delete forever'));
      await tester.tap(find.text('Empty'));
      expect(calls, ['restore:fmv', 'forever:fmv', 'empty']);
    });

    testWidgets('says when there is nothing', (tester) async {
      await tester.pumpWidget(app(RecentlyDeletedCard(
        items: const [],
        now: now,
        onRestore: (_) {},
        onDeleteForever: (_) {},
        onEmpty: () {},
      )));
      expect(find.text('Nothing here.'), findsOneWidget);
      expect(find.text('Empty'), findsNothing);
    });
  });
}
