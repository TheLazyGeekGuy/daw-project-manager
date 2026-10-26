import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_en.dart';
import 'package:daw_project_manager/ui/widgets/legacy_all_recovery_action.dart';
import 'package:daw_project_manager/services/project_repair/midi_file_validator.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../helpers/legacy_all_fixture.dart';

final _l = AppLocalizationsEn();
final _source = p.join(
  Directory.systemTemp.path,
  'dpm-recovery-ui',
  'Old song.ALL',
);
final _output = p.join(
  Directory.systemTemp.path,
  'dpm-recovery-ui',
  'Recovered.mid',
);
final _report = p.join(
  Directory.systemTemp.path,
  'dpm-recovery-ui',
  'Recovery.json',
);

Map<String, Object?> _result({bool partial = false}) => {
  'status': partial ? 'partial_recovery_unverified' : 'generated_unverified',
  'track_count': 3,
  'note_count': 17,
  'skipped_parts': partial ? 2 : 0,
  'output': _output,
  'report': _report,
  'limitations': ['Fixture diagnostic: instruments are not recovered.'],
  'native_daw_reopen_verified': false,
};

Future<void> _mount(
  WidgetTester tester,
  Future<Map<String, Object?>> Function(String path)? recover, {
  String? sourcePath,
}) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: LegacyAllRecoveryAction(
            path: sourcePath ?? _source,
            recover: recover,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _requestRecovery(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(FilledButton, _l.projectRepairRecoverMidi),
  );
  await tester.pumpAndSettle();
  expect(find.text(_l.projectRepairRecoveryTitle), findsOneWidget);
  expect(find.text(_l.projectRepairRecoveryConsent), findsOneWidget);
}

Future<void> _confirmRecovery(WidgetTester tester) async {
  await _requestRecovery(tester);
  await tester.tap(
    find.widgetWithText(FilledButton, _l.projectRepairRecoverAction),
  );
  // A pending recovery deliberately keeps its progress animation running.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _expectCounts(WidgetTester tester, {required bool partial}) {
  expect(
    tester
        .widget<SelectableText>(find.byKey(const ValueKey('recovery-status')))
        .data,
    '${_l.projectRepairRecoveryStatus}: '
    '${partial ? 'partial_recovery_unverified' : 'generated_unverified'}',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('recovery-track-count')))
        .data,
    '${_l.projectRepairRecoveredTracks}: 3',
  );
  expect(
    tester.widget<Text>(find.byKey(const ValueKey('recovery-note-count'))).data,
    '${_l.projectRepairRecoveredNotes}: 17',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('recovery-skipped-parts')))
        .data,
    '${_l.projectRepairSkippedParts}: ${partial ? 2 : 0}',
  );
}

void main() {
  testWidgets(
    'production worker recovers actual MIDI without capturing widget state',
    (tester) async {
      final temporary = Directory.systemTemp.createTempSync(
        'dpm-recovery-worker-',
      );
      final root = Directory(temporary.resolveSymbolicLinksSync());
      addTearDown(() => root.deleteSync(recursive: true));
      final source = File(p.join(root.path, 'Classic.ALL'));
      final original = legacyAllFixture();
      source.writeAsBytesSync(original);
      await _mount(tester, null, sourcePath: source.path);
      await _confirmRecovery(tester);
      for (var i = 0; i < 300; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(
        find.text(_l.projectRepairRecoveryCreated),
        findsOneWidget,
        reason: tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data)
            .join('\n'),
      );
      final reportFile = root
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere(
            (file) => p.basename(file.path) == 'legacy-conversion-report.json',
          );
      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
      final midi = MidiFileValidator.inspect(
        File(report['output'] as String).readAsBytesSync(),
      );
      expect(midi.format, 1);
      expect(midi.noteCount, 1);
      expect(midi.division, 480);
      expect(report['native_daw_reopen_verified'], isFalse);
      expect(report['original_modified'], isFalse);
      expect(source.readAsBytesSync(), original);
      expect(File(report['backup'] as String).readAsBytesSync(), original);
      expect(find.text(report['output'] as String), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling consent never invokes recovery', (tester) async {
    var calls = 0;
    await _mount(tester, (_) async {
      calls++;
      return _result();
    });
    expect(find.text(_l.projectRepairNativeAllHint), findsOneWidget);
    await _requestRecovery(tester);
    expect(calls, 0);
    await tester.tap(find.widgetWithText(TextButton, _l.cancel));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_l.projectRepairRecoveryCreated), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'confirmation passes the source path once and disables a busy action',
    (tester) async {
      final pending = Completer<Map<String, Object?>>();
      final received = <String>[];
      await _mount(tester, (path) {
        received.add(path);
        return pending.future;
      });
      await _confirmRecovery(tester);
      expect(received, [_source]);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final busyButton = find.widgetWithText(
        FilledButton,
        _l.projectRepairWorking,
      );
      expect(tester.widget<FilledButton>(busyButton).onPressed, isNull);
      await tester.tap(busyButton);
      await tester.pump();
      expect(received, [_source]);
      expect(find.byType(AlertDialog), findsNothing);

      pending.complete(_result());
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(_l.projectRepairRecoveryCreated), findsOneWidget);
      expect(find.text(_l.projectRepairUnverifiedRecovery), findsOneWidget);
      expect(find.text(_l.projectRepairPartialRecovery), findsNothing);
      expect(find.text(_output), findsOneWidget);
      expect(find.text(_report), findsOneWidget);
      expect(
        find.text('Fixture diagnostic: instruments are not recovered.'),
        findsOneWidget,
      );
      _expectCounts(tester, partial: false);
    },
  );

  testWidgets(
    'partial recovery keeps skipped counts and unverified status visible',
    (tester) async {
      await _mount(tester, (_) async => _result(partial: true));
      await _confirmRecovery(tester);
      await tester.pumpAndSettle();
      expect(find.text(_l.projectRepairPartialRecovery), findsOneWidget);
      expect(find.text(_l.projectRepairUnverifiedRecovery), findsNothing);
      expect(find.text(_output), findsOneWidget);
      expect(find.text(_report), findsOneWidget);
      _expectCounts(tester, partial: true);
    },
  );

  testWidgets(
    'failure is visible and retry clears the old error before completion',
    (tester) async {
      var attempts = 0;
      final retry = Completer<Map<String, Object?>>();
      await _mount(tester, (_) {
        attempts++;
        if (attempts == 1) {
          return Future.error(
            const FormatException('Unsupported fixture layout'),
          );
        }
        return retry.future;
      });
      await _confirmRecovery(tester);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(
        find.text(
          '${_l.projectRepairFailed}\nFormatException: Unsupported fixture layout',
        ),
        findsOneWidget,
      );
      expect(find.text(_l.projectRepairRecoveryCreated), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await _confirmRecovery(tester);
      expect(attempts, 2);
      expect(find.textContaining('Unsupported fixture layout'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      retry.complete(_result());
      await tester.pumpAndSettle();
      expect(find.text(_l.projectRepairRecoveryCreated), findsOneWidget);
      expect(find.textContaining('Unsupported fixture layout'), findsNothing);
    },
  );

  testWidgets('finishing after disposal does not update a removed action', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    await _mount(tester, (_) => pending.future);
    await _confirmRecovery(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_result());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
