// End to end, in the real app window: delete a project, find it in
// Settings > Project folders > Recently deleted, restore it, and check it
// came back with its notes. See harness.dart for how to run it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/models/music_project.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delete a project, then restore it from Recently deleted',
      (tester) async {
    final library = await seedLibrary();

    // The real app, from its real entry point, on the seeded library. Its
    // startup installs its own error widget; the test framework wants
    // Flutter's back once the test ends.
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main(const []);
    final song = find.text('Follow My Voice');
    await tester.pumpUntilFound(song);
    await tester.pumpUntilFound(find.text('Teardrop Remix'));
    await tester.step();

    // Right-click the card: the project menu.
    await tester.rightClick(song.first);
    await tester.pumpUntilFound(find.text('Delete…'));
    await tester.tapAndWait(find.text('Delete…'));

    // The confirmation: it goes to Recently deleted, and since its folder is
    // scanned, it offers (ticked) to stop scanning it.
    await tester.pumpUntilFound(find.text('Delete "Follow My Voice"?'));
    expect(find.text('Also stop scanning its folder'), findsOneWidget);
    final stopScanning = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(stopScanning.value, isTrue);
    await tester.tapAndWait(find.widgetWithText(FilledButton, 'Delete'));

    // Gone from the dashboard; the other project stays.
    await tester.pumpUntilGone(song);
    expect(find.text('Teardrop Remix'), findsWidgets);

    // The snackbar says where it went (with Undo); close it — it sits over
    // the side rail's Settings button.
    final snackBar = find.byType(SnackBar);
    await tester.pumpUntilFound(snackBar);
    expect(
      find.descendant(
        of: snackBar,
        matching: find.text('"Follow My Voice" moved to Recently deleted.'),
      ),
      findsOneWidget,
    );
    await tester.tapAndWait(
      find.descendant(of: snackBar, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpUntilGone(snackBar);

    // Settings > Project folders > Recently deleted.
    await tester.tapAndWait(find.byIcon(Icons.settings_outlined).hitTestable().first);
    // The side menu's entry ("Project Folders"; the section's own heading
    // is "Project folders").
    await tester.pumpUntilFound(find.text('Project Folders'));
    await tester.tapAndWait(find.text('Project Folders').first);
    await tester.pumpUntilFound(find.text('Recently deleted'));
    await tester.ensureVisible(find.text('Recently deleted'));
    await tester.step();
    expect(song, findsOneWidget, reason: 'listed in Recently deleted');

    // Restore it.
    await tester.tapAndWait(find.text('Restore'));
    await tester.pumpUntilFound(find.text('Nothing here.'));
    await tester.step();

    // Back on the dashboard, it is there again — notes and all.
    await tester.goBack();
    await tester.pumpUntilFound(song);
    await tester.step();

    final projects = Hive.box<MusicProject>('${library.profileId}_projects');
    final restored = projects.values.singleWhere((p) => p.displayName == 'Follow My Voice');
    expect(restored.notes, 'Hook idea: vocal chop in the drop');
    await tester.step();

    ErrorWidget.builder = errorWidgetBuilder;
  });
}
