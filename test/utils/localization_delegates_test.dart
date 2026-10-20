import 'dart:io';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('Material widgets are translated, not just the app strings',
      (tester) async {
    late MaterialLocalizations material;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) {
            material = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(material.cancelButtonLabel, 'Abbrechen');
  });

  // gen-l10n's own list carries flutter_localizations' delegates, which
  // serve the SDK's bundled Material library and leave material_ui widgets
  // without MaterialLocalizations outside English.
  test('nothing uses the generated delegate list', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'test', 'integration_test', 'tool']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        final path = p.normalize(file.path);
        if (!path.endsWith('.dart') ||
            p.isWithin(p.join('lib', 'generated'), path) ||
            path == p.join('test', 'utils', 'localization_delegates_test.dart')) {
          continue;
        }
        // Code only: the shared list's doc comment names the generated one
        // to warn against it.
        final usesIt = file.readAsLinesSync().any((line) =>
            !line.trimLeft().startsWith('//') &&
            line.contains('AppLocalizations.localizationsDelegates'));
        if (usesIt) offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'use appLocalizationsDelegates (lib/utils/localization_delegates.dart)');
  });
}
