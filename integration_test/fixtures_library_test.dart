// End to end on the DAW project collection: the app scans a folder holding
// a copy of test/fixtures/projects, search narrows the list, Deep Scan reads
// every project, and the MIDI tab shows their clips — the very clips the
// collection's .expected.json files recorded.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/repository/midi_clip_store.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scan, search, deep scan and browse the clips of real projects',
      (tester) async {
    final library = await seedLibrary(withFixtures: true);
    final files = fixtureProjectFiles(fixtureProjects).values.expand((f) => f).toList();
    final names = {for (final f in files) p.basenameWithoutExtension(f.path)};

    final errorWidgetBuilder = ErrorWidget.builder;
    app.main(const []);

    // The startup scan finds every project in the collection.
    for (final name in names) {
      await tester.pumpUntilFound(find.text(name), timeout: const Duration(seconds: 60));
    }
    await tester.step();

    // Search narrows the list to one.
    final search = find.byWidgetPredicate(
      // "Search projects... (Ctrl+F)" on a desktop.
      (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Search projects'),
    );
    await tester.tapAndWait(search.hitTestable().first);
    await tester.enterText(search.hitTestable().first, 'Blur');
    await tester.pumpUntilGone(find.text('NN1'));
    expect(find.text('Blur - Song 2 (TetraSound Rmx)'), findsWidgets);
    await tester.step();
    await tester.enterText(search.hitTestable().first, '');
    await tester.pumpUntilFound(find.text('NN1'));
    await tester.step();

    // Deep Scan reads every project, MIDI clips included.
    await tester.tapRailAction('Deep Scan');
    await tester.tapAndWait(find.widgetWithText(ElevatedButton, 'Deep Scan'));

    final projects = Hive.box<MusicProject>('${library.profileId}_projects');
    final clips = MidiClipStore(library.profileId);
    final expectedClips = <String, int>{
      for (final f in files)
        p.basenameWithoutExtension(f.path):
            ((jsonDecode(File('${f.parent.path}.expected.json').readAsStringSync())
                    as Map)['midiClips'] as List)
                .length,
    };
    final readUntil = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(readUntil)) {
      await tester.pump(const Duration(milliseconds: 500));
      final done = projects.values.where((p) => !p.isVirtual).every((p) => p.metadataScanned);
      if (done && projects.isNotEmpty) break;
    }
    // What the GUI's deep scan stored is what the collection recorded.
    for (final project in projects.values.where((p) => !p.isVirtual)) {
      final stored = await clips.get(project.id);
      expect(
        stored?.clips.length ?? 0,
        expectedClips[project.displayName],
        reason: 'clips stored for ${project.displayName}',
      );
    }
    await tester.step();

    // The MIDI tab lists them, grouped by project.
    await tester.tapAndWait(find.text('MIDI').hitTestable().first);
    await tester.pumpUntilFound(find.text('NN1'));
    expect(
      find.text('No MIDI clips yet. Extract a project\'s metadata to read its clips.'),
      findsNothing,
    );
    await tester.step();

    ErrorWidget.builder = errorWidgetBuilder;
  }, timeout: const Timeout(Duration(minutes: 6)));
}
