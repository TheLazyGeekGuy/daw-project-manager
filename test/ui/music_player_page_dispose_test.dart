import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/ui/music_player_page.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

/// Leaving the Music Player tab used `ref` in `dispose()`, which Riverpod 3
/// refuses: it threw on every unmount, the bottom player bar kept calling
/// into the page that was gone, and the page's own dispose never finished.
/// Found by the documentation's screenshot run.
void main() {
  testWidgets('leaving the music player takes its callbacks back, cleanly', (tester) async {
    final container = ProviderContainer(overrides: [
      allProjectsStreamProvider.overrideWith((ref) => Stream.value(const <MusicProject>[])),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MusicPlayerPage()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(container.read(queueNavigationProvider).playNext, isNotNull,
        reason: 'the page lends the bottom bar its previous/next');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(container.read(queueNavigationProvider).playNext, isNull,
        reason: 'and takes them back when it goes');
  });

  test('a page going away leaves a newer page\'s callbacks alone', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigation = container.read(queueNavigationProvider.notifier);
    void oldNext() {}
    void newNext() {}
    navigation.register(playNext: oldNext, playPrev: () {});
    navigation.register(playNext: newNext, playPrev: () {});
    navigation.unregister(oldNext);
    expect(container.read(queueNavigationProvider).playNext, newNext);
    navigation.unregister(newNext);
    expect(container.read(queueNavigationProvider).playNext, isNull);
  });
}
