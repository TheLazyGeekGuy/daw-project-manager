import 'dart:async';
import 'dart:io';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_en.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_fr.dart';
import 'package:daw_project_manager/ui/widgets/legacy_all_recovery_action.dart';
import 'package:daw_project_manager/ui/widgets/legacy_cubase_migration_dialog.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../helpers/dawproject_fixture.dart';
import '../../helpers/legacy_all_fixture.dart';

final _l = AppLocalizationsEn();

Future<void> _mount(
  WidgetTester tester, {
  required Future<File?> Function(List<String>) pick,
  Future<Map<String, Object?>> Function(String)? recover,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1100, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const ValueKey('open-migration'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  LegacyCubaseMigrationDialog(pickFile: pick, recover: recover),
            ),
            child: const Text('Open fixture route'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-migration')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _finishIo(WidgetTester tester) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

void main() {
  late Directory root;
  setUp(() {
    final temporary = Directory.systemTemp.createTempSync('dpm-legacy-dialog-');
    root = Directory(temporary.resolveSymbolicLinksSync());
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets(
    'route uses material_ui and cancellation preserves manual choices',
    (tester) async {
      var calls = 0;
      await _mount(
        tester,
        pick: (extensions) async {
          expect(extensions, ['all', 'arr']);
          calls++;
          return null;
        },
      );
      expect(find.text(_l.legacyMigrationTitle), findsOneWidget);
      expect(find.text(_l.legacyMigrationOfficialTitle), findsOneWidget);
      expect(find.text(_l.legacyMigrationAtariTitle), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('legacy-migration-cpr')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, find.byKey(const ValueKey('legacy-migration-choose')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(LegacyAllRecoveryAction), findsNothing);
      expect(root.listSync(), isEmpty);
      await tester.tap(find.widgetWithText(TextButton, _l.close));
      await tester.pumpAndSettle();
      expect(find.byType(LegacyCubaseMigrationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('French route resolves material and application localizations', (
    tester,
  ) async {
    final labels = AppLocalizationsFr();
    await _mount(tester, locale: 'fr', pick: (_) async => null);
    expect(find.text(labels.legacyMigrationTitle), findsOneWidget);
    expect(find.text(labels.legacyMigrationChooseLegacy), findsOneWidget);
    expect(find.text(_l.legacyMigrationTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'verified preview delegates native recovery to the shared guarded action',
    (tester) async {
      final source = File(p.join(root.path, 'Classic.ALL'));
      final original = legacyAllFixture();
      source.writeAsBytesSync(original);
      final received = <String>[];
      await _mount(
        tester,
        pick: (_) async => source,
        recover: (path) async {
          received.add(path);
          return {
            'status': 'generated_unverified',
            'track_count': 1,
            'note_count': 1,
            'skipped_parts': 0,
            'limitations': <String>[],
            'output': p.join(root.path, 'Recovered.mid'),
            'report': p.join(root.path, 'Recovery.json'),
          };
        },
      );
      await _tap(tester, find.byKey(const ValueKey('legacy-migration-choose')));
      await _finishIo(tester);
      expect(
        find.text(_l.legacyMigrationPreviewSummary(1, 1, 1)),
        findsOneWidget,
        reason: tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data)
            .join('\n'),
      );
      expect(find.text('Keys'), findsOneWidget);
      expect(find.byType(LegacyAllRecoveryAction), findsOneWidget);
      expect(
        tester
            .widget<LegacyAllRecoveryAction>(
              find.byType(LegacyAllRecoveryAction),
            )
            .path,
        source.path,
      );
      final backupLabel = _l.legacyMigrationBackup('');
      final backup = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .singleWhere((text) => text.data?.startsWith(backupLabel) ?? false)
          .data!
          .substring(backupLabel.length);
      expect(File(backup).readAsBytesSync(), original);
      expect(source.readAsBytesSync(), original);

      await _tap(
        tester,
        find.widgetWithText(FilledButton, _l.projectRepairRecoverMidi),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l.projectRepairRecoveryConsent), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, _l.cancel));
      await tester.pumpAndSettle();
      expect(received, isEmpty);
      await _tap(
        tester,
        find.widgetWithText(FilledButton, _l.projectRepairRecoverMidi),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, _l.projectRepairRecoverAction),
      );
      await tester.pumpAndSettle();
      expect(received, [source.path]);
      expect(find.text(_l.projectRepairUnverifiedRecovery), findsOneWidget);
      expect(source.readAsBytesSync(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ARR keeps DAWproject inspection and failed CPR validation available',
    (tester) async {
      final source = File(p.join(root.path, 'Arrangement.ARR'))
        ..writeAsBytesSync([1, 2, 3]);
      final dawProject = File(p.join(root.path, 'Intermediate.dawproject'))
        ..writeAsBytesSync(dawProjectFixture());
      final malformed = File(p.join(root.path, 'Invalid.cpr'))
        ..writeAsStringSync('invalid CPR');
      final extensions = <List<String>>[];
      await _mount(
        tester,
        pick: (requested) async {
          extensions.add(requested);
          if (requested.contains('arr')) return source;
          return requested.single == 'dawproject' ? dawProject : malformed;
        },
      );
      await _tap(tester, find.byKey(const ValueKey('legacy-migration-choose')));
      await _finishIo(tester);
      expect(find.text(_l.legacyMigrationArrUnsupported), findsOneWidget);
      expect(find.byType(LegacyAllRecoveryAction), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('legacy-migration-cpr')),
            )
            .onPressed,
        isNotNull,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('legacy-migration-dawproject')),
      );
      await _finishIo(tester);
      expect(find.text(_l.legacyMigrationDawProjectChecked), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('legacy-migration-cpr')));
      await _finishIo(tester);
      expect(
        find.byKey(const ValueKey('legacy-migration-error')),
        findsOneWidget,
      );
      expect(find.text(_l.legacyMigrationCprChecked), findsNothing);
      expect(extensions, [
        ['all', 'arr'],
        ['dawproject'],
        ['cpr'],
      ]);
      expect(source.readAsBytesSync(), [1, 2, 3]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown ALL layout keeps manual routes and writes no MIDI', (
    tester,
  ) async {
    final source = File(p.join(root.path, 'Unknown.ALL'))
      ..writeAsBytesSync([1, 2, 3]);
    await _mount(tester, pick: (_) async => source);
    await _tap(tester, find.byKey(const ValueKey('legacy-migration-choose')));
    await _finishIo(tester);
    expect(find.text(_l.legacyMigrationUnsupportedPreview), findsOneWidget);
    expect(find.byType(LegacyAllRecoveryAction), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('legacy-migration-cpr')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.mid')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker completing after route disposal cannot prepare a backup',
    (tester) async {
      final pending = Completer<File?>();
      final source = File(p.join(root.path, 'Late.ALL'))
        ..writeAsBytesSync(legacyAllFixture());
      await _mount(tester, pick: (_) => pending.future);
      await _tap(tester, find.byKey(const ValueKey('legacy-migration-choose')));
      await tester.tap(find.widgetWithText(TextButton, _l.close));
      await tester.pump(const Duration(milliseconds: 400));
      pending.complete(source);
      await tester.pumpAndSettle();
      expect(root.listSync(), hasLength(1));
      expect(find.byType(LegacyCubaseMigrationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
