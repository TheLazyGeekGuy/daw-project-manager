// End to end: a release made from two songs on the Releases tab — the track
// picker, the release page it opens on (a release of several songs has no
// title yet), and the title typed there, kept.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/release.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create a release from two songs and name it', (tester) async {
    final library = await seedLibrary();
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main(const []);

    await tester.pumpUntilFound(find.text('Teardrop Remix'));
    await tester.step();
    final projects = Hive.box<MusicProject>('${library.profileId}_projects');
    final songIds = {for (final p in projects.values) p.id};

    await tester.openTab(Icons.album);
    final create = find.text('Create New Release').hitTestable();
    await tester.pumpUntilFound(create); // once the tab has slid in
    await tester.tapAndWait(create.first);

    // The track picker: both songs ticked.
    await tester.pumpUntilFound(find.text('Select Tracks'));
    for (final name in ['Follow My Voice', 'Teardrop Remix']) {
      await tester.tapAndWait(find.widgetWithText(CheckboxListTile, name));
    }
    await tester.tapAndWait(find.widgetWithText(ElevatedButton, 'Continue'));

    // Two songs: the release page opens, to be given a title.
    final title = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Release Title',
    );
    await tester.pumpUntilFound(title);
    final releases = Hive.box<Release>('${library.profileId}_releases');
    expect(releases.length, 1);
    expect(releases.values.single.trackIds.toSet(), songIds);

    await tester.tapAndWait(title.first);
    await tester.enterText(title.first, 'Night Drive EP');
    await tester.step();
    final savedBy = DateTime.now().add(const Duration(seconds: 10));
    while (releases.values.single.title != 'Night Drive EP' && DateTime.now().isBefore(savedBy)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(releases.values.single.title, 'Night Drive EP');

    // Back on the tab, it is listed under its new title.
    await tester.goBack();
    await tester.pumpUntilGone(title);
    await tester.pumpUntilFound(find.text('Night Drive EP'));
    await tester.step();

    ErrorWidget.builder = errorWidgetBuilder;
  }, timeout: const Timeout(Duration(minutes: 4)));
}
