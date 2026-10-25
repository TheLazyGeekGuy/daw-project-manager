import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/ui/dialogs/legacy_install_dialog.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

void main() {
  Future<bool?> answer(WidgetTester tester, String button) async {
    late Future<bool?> result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showLegacyInstallDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Remove the old installation?'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('"Remove it" answers yes', (tester) async {
    expect(await answer(tester, 'Remove it'), isTrue);
  });

  testWidgets('"Keep it" answers no, which stops the asking', (tester) async {
    expect(await answer(tester, 'Keep it'), isFalse);
  });
}
