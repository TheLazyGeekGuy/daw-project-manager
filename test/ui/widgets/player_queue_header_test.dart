import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/ui/widgets/player_queue_header.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

/// The music player's queue header, at the width its pane gets on a 1920 px
/// window. Written as a plain row it overflowed by 14 px as soon as a track
/// was queued — found by the documentation's screenshot run.
void main() {
  Future<void> pump(WidgetTester tester, Locale locale, {double width = 239}) =>
      tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PlayerQueueHeader(
                count: 12,
                libraryActions: true,
                queueActions: true,
                shuffleOn: true,
                repeatOn: false,
                onAutoQueue: () {},
                onShuffle: () {},
                onRepeat: () {},
                onPrevious: () {},
                onNext: () {},
                onClear: () {},
              ),
            ),
          ),
        ),
      ));

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('fits its pane with every button, in $locale', (tester) async {
      await pump(tester, locale);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(IconButton), findsNWidgets(6));
      expect(find.text('12'), findsOneWidget);
    });
  }

  testWidgets('a long title gives way to the buttons', (tester) async {
    await pump(tester, const Locale('de'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = tester.renderObject<RenderParagraph>(find.text('Warteschlange'));
    expect(title.didExceedMaxLines, isTrue, reason: 'shortened, not pushing the buttons out');
  });
}
