// End to end: a project's own page, and the project menu's bigger actions —
// notes typed on the project page are kept, and "Move to profile…" hands a
// song to another artist's profile, files left where they are.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/models/ignored_path.dart';
import 'package:daw_project_manager/models/music_project.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edit notes on the project page, then move the song to another artist',
      (tester) async {
    final library = await seedLibrary(secondProfile: 'Audio Crawler vs Reisser');
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main(const []);

    final teardrop = find.text('Teardrop Remix');
    await tester.pumpUntilFound(teardrop);
    await tester.step();
    final projects = Hive.box<MusicProject>('${library.profileId}_projects');
    MusicProject row() => projects.values.singleWhere((p) => p.displayName == 'Teardrop Remix');

    // --- The project page: notes are saved as they are typed.
    await tester.rightClick(teardrop.first);
    await tester.pumpUntilFound(find.text('View Details'));
    await tester.tapAndWait(find.text('View Details'));
    final notes = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Notes',
    );
    await tester.pumpUntilFound(notes);
    await tester.tapAndWait(notes.first);
    await tester.enterText(notes.first, 'Mix: tame the 300 Hz build-up');
    await tester.step();
    final savedBy = DateTime.now().add(const Duration(seconds: 10));
    while (row().notes != 'Mix: tame the 300 Hz build-up' && DateTime.now().isBefore(savedBy)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(row().notes, 'Mix: tame the 300 Hz build-up');
    await tester.goBack();
    await tester.pumpUntilGone(notes);
    await tester.pumpUntilFound(teardrop);
    await tester.step();

    // --- Move to profile: the song goes to the collaboration's profile.
    final songId = row().id;
    await tester.rightClick(teardrop.first);
    await tester.pumpUntilFound(find.text('Move to profile…'));
    await tester.tapAndWait(find.text('Move to profile…'));
    await tester.pumpUntilFound(find.text('Move "Teardrop Remix" to another profile'));
    // Files stay where they are, by default; the target is the other profile.
    expect(find.text('Audio Crawler vs Reisser'), findsWidgets);
    await tester.tapAndWait(find.widgetWithText(FilledButton, 'Move'));

    await tester.pumpUntilGone(teardrop);
    expect(find.text('Follow My Voice'), findsWidgets, reason: 'the other song stays');
    final moved = Hive.box<MusicProject>('${library.otherProfileId}_projects').get(songId);
    expect(moved, isNotNull, reason: 'it lives in the other profile now');
    expect(moved!.notes, 'Mix: tame the 300 Hz build-up', reason: 'with its notes');
    // Its folder is excluded here, so the next scan doesn't bring it back.
    final excluded = Hive.box<IgnoredPath>('${library.profileId}_ignored_paths').values;
    expect(excluded.map((e) => e.path), contains(moved.filePath.replaceAll(RegExp(r'[\\/][^\\/]+$'), '')));
    await tester.step();

    ErrorWidget.builder = errorWidgetBuilder;
  }, timeout: const Timeout(Duration(minutes: 4)));
}
