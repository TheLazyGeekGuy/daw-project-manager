import 'dart:async';
import 'dart:io';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_en.dart';
import 'package:daw_project_manager/ui/widgets/project_dependency_report_panel.dart';
import 'package:daw_project_manager/ui/widgets/project_file_inspection_button.dart';
import 'package:daw_project_manager/ui/widgets/project_inspection_dialog.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

final _l = AppLocalizationsEn();

Future<void> _mount(
  WidgetTester tester,
  Future<File?> Function() pickFile,
) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ProjectFileInspectionButton(pickFile: pickFile)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picker failure is reported without opening an inspection', (
    tester,
  ) async {
    await _mount(tester, () async => throw StateError('Picker unavailable'));
    await tester.tap(find.byTooltip(_l.projectRepairOpen));
    await tester.pumpAndSettle();
    expect(find.textContaining('Picker unavailable'), findsOneWidget);
    expect(find.byType(ProjectInspectionDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the picker leaves inspection closed', (tester) async {
    var calls = 0;
    await _mount(tester, () async {
      calls++;
      return null;
    });
    await tester.tap(find.byTooltip(_l.projectRepairOpen));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ProjectInspectionDialog), findsNothing);
    expect(find.byType(ProjectDependencyReportPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected file opens its own read-only inspection', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('dpm-inspection-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    final selected = File(p.join(root.path, 'Selected project.rpp'));
    const source = '<REAPER_PROJECT 0.1 7.0 1\n>\n';
    selected.writeAsStringSync(source);
    var calls = 0;
    await _mount(tester, () async {
      calls++;
      return selected;
    });
    await tester.tap(find.byTooltip(_l.projectRepairOpen));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<ProjectInspectionDialog>(find.byType(ProjectInspectionDialog))
          .projectFile,
      same(selected),
    );
    // Inspection deliberately runs real asynchronous file I/O and an isolate.
    // Give those tasks real event-loop turns without waiting on an endless
    // loading animation in Flutter's fake clock.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(ProjectDependencyReportPanel).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(ProjectDependencyReportPanel), findsOneWidget);
    await tester.pumpAndSettle();
    final panel = tester.widget<ProjectDependencyReportPanel>(
      find.byType(ProjectDependencyReportPanel),
    );
    expect(panel.report.path, selected.path);
    expect(panel.report.formatId, 'reaper');
    expect(selected.readAsStringSync(), source);
    await tester.tap(find.widgetWithText(TextButton, _l.close));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectInspectionDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker completing after launcher disposal opens no route', (
    tester,
  ) async {
    final pending = Completer<File?>();
    await _mount(tester, () => pending.future);
    await tester.tap(find.byTooltip(_l.projectRepairOpen));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(File(p.join(Directory.systemTemp.path, 'not-read.ALL')));
    await tester.pump();
    expect(find.byType(ProjectInspectionDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
