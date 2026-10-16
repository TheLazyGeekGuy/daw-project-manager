// End to end on the MIDI tab, with a real Ableton Live 11 project: a deep
// scan reads its clips, one of them goes into a new collection — a copy,
// stored per profile — and the collection's clip opens in the piano roll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:daw_project_manager/main.dart' as app;
import 'package:daw_project_manager/repository/midi_clip_store.dart';
import 'package:daw_project_manager/repository/midi_collection_store.dart';
import 'package:daw_project_manager/ui/midi_piano_roll_dialog.dart' show MidiPianoRollWindow;

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('read a project\'s clips, collect one, open it in the piano roll',
      (tester) async {
    final library = await seedLibrary(
      fixtures: ['ableton/Audio Crawler vs Nordic Enigma - NN1 (Live 11)'],
    );
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main(const []);

    await tester.pumpUntilFound(find.text('NN1'));
    await tester.step();

    // Deep Scan reads the project's nine clips.
    await tester.tapRailAction('Deep Scan');
    await tester.tapAndWait(find.widgetWithText(ElevatedButton, 'Deep Scan'));
    final clips = MidiClipStore(library.profileId);
    final readBy = DateTime.now().add(const Duration(minutes: 2));
    var stored = 0;
    while (stored == 0 && DateTime.now().isBefore(readBy)) {
      await tester.pump(const Duration(milliseconds: 500));
      stored = (await clips.getAll()).values.fold(0, (n, s) => n + s.clips.length);
    }
    expect(stored, 9);

    // The MIDI tab lists them; one goes into a new collection.
    await tester.openTab(Icons.piano);
    await tester.pumpUntilFound(find.text('Spire 5').hitTestable());
    await tester.step();
    final addTo = find.byTooltip('Add to collection').hitTestable();
    await tester.pumpUntilFound(addTo);
    await tester.tapAndWait(addTo.first);
    await tester.pumpUntilFound(find.text('New collection'));
    await tester.tapAndWait(find.text('New collection').last);
    final name = find.byKey(const ValueKey('collection-name-field'));
    await tester.pumpUntilFound(name);
    await tester.enterText(name, 'Spire leads');
    await tester.step();
    await tester.tapAndWait(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpUntilFound(find.text('Added to Spire leads'));

    final collections = await MidiCollectionStore(library.profileId).all();
    expect(collections.map((c) => c.name), ['Spire leads']);
    expect(collections.single.items, hasLength(1));
    expect(collections.single.items.single.sourceProjectName, 'NN1');
    await tester.closeSnackBar();

    // The collection, opened from the side list, holds the copy.
    await tester.tapAndWait(find.text('Spire leads').hitTestable().first);
    await tester.settleTransition();
    final clipName = collections.single.items.single.clip.name;
    await tester.pumpUntilFound(find.text(clipName).hitTestable());

    // Its thumbnail opens the piano roll; the window's close button shuts it.
    await tester.tapAndWait(find.byTooltip('Open piano roll').hitTestable().first);
    await tester.pumpUntilFound(find.byType(MidiPianoRollWindow));
    await tester.step();
    await tester.tapAndWait(
      find.descendant(of: find.byType(MidiPianoRollWindow), matching: find.byIcon(Icons.close)).first,
    );
    await tester.pumpUntilGone(find.byType(MidiPianoRollWindow));
    await tester.step();

    ErrorWidget.builder = errorWidgetBuilder;
  }, timeout: const Timeout(Duration(minutes: 4)));
}
