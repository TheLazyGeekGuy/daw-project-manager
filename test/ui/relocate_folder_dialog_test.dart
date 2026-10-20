import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/ui/dialogs/relocate_folder_dialog.dart';
import 'package:daw_project_manager/utils/relocation_preview.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

void main() {
  late AppLocalizations l10n;

  Future<bool?> open(WidgetTester tester, RelocationPreview preview, {String? tap}) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context)!;
        return TextButton(
          onPressed: () async => result = await showDialog<bool>(
            context: context,
            builder: (_) => RelocateFolderDialog(from: r'C:\Music', to: r'D:\Music', preview: preview),
          ),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
    }
    return result;
  }

  testWidgets('shows both folders and how many projects are already there', (tester) async {
    await open(tester, const RelocationPreview(projects: 12, found: 12));
    expect(find.text(r'C:\Music'), findsOneWidget);
    expect(find.text(r'D:\Music'), findsOneWidget);
    expect(find.text(l10n.relocateFolderFound(12, 12)), findsOneWidget);
    expect(find.text(l10n.relocateFolderSomeMissing), findsNothing);
    expect(find.text(l10n.relocateFolderNoneFound), findsNothing);
  });

  testWidgets('some still on their way: says not to delete the missing ones', (tester) async {
    await open(tester, const RelocationPreview(projects: 12, found: 5));
    expect(find.text(l10n.relocateFolderSomeMissing), findsOneWidget);
  });

  testWidgets('none there: asks whether the right folder was picked', (tester) async {
    await open(tester, const RelocationPreview(projects: 12, found: 0));
    expect(find.text(l10n.relocateFolderNoneFound), findsOneWidget);
    expect(find.text(l10n.relocateFolderSomeMissing), findsNothing);
  });

  testWidgets('an empty folder says nothing about projects', (tester) async {
    await open(tester, const RelocationPreview(projects: 0, found: 0));
    expect(find.text(l10n.relocateFolderFound(0, 0)), findsNothing);
    expect(find.text(l10n.relocateFolderNoneFound), findsNothing);
  });

  testWidgets('Relocate goes ahead, Cancel does not', (tester) async {
    final preview = const RelocationPreview(projects: 1, found: 1);
    expect(await open(tester, preview, tap: 'Relocate'), isTrue);
    expect(await open(tester, preview, tap: 'Cancel'), isFalse);
  });
}
