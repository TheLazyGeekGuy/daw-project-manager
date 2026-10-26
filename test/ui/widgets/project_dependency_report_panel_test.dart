import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_en.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_fr.dart';
import 'package:daw_project_manager/services/project_repair/project_dependency_inspector.dart';
import 'package:daw_project_manager/ui/widgets/project_dependency_report_panel.dart';
import 'package:daw_project_manager/services/project_repair/local_plugin_inventory.dart';
import 'package:daw_project_manager/services/project_repair/cubase_structural_probe.dart';
import 'package:daw_project_manager/services/project_repair/legacy_cubase_conversion.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

Future<void> _mountWorkerPanel(
  WidgetTester tester,
  ProjectDependencyReport report, {
  List<String>? roots,
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
          child: ProjectDependencyReportPanel(
            report: report,
            inventoryRoots: roots,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishWorker(WidgetTester tester) async {
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
  testWidgets(
    'production CPR worker preserves synthetic bytes without capturing State',
    (tester) async {
      final temporary = Directory.systemTemp.createTempSync('dpm-cpr-worker-');
      final root = Directory(temporary.resolveSymbolicLinksSync());
      addTearDown(() => root.deleteSync(recursive: true));
      final bytes = Uint8List(26)
        ..setRange(0, 4, ascii.encode('RIFF'))
        ..setRange(8, 12, ascii.encode('NUND'))
        ..setRange(12, 16, ascii.encode('ARCH'))
        ..setRange(20, 26, [255, 255, 255, 255, 0, 1]);
      ByteData.sublistView(bytes)
        ..setUint32(4, bytes.length - 12, Endian.big)
        ..setUint32(16, 6, Endian.big);
      final source = File(p.join(root.path, 'Fixture.cpr'))
        ..writeAsBytesSync(bytes);
      await _mountWorkerPanel(
        tester,
        ProjectDependencyReport(
          path: source.path,
          formatId: 'cubase',
          pluginNames: const [],
          trackCount: null,
          limitations: const [],
          cubaseContainer: CubaseContainerManifest.inspect(bytes),
        ),
      );
      final labels = AppLocalizationsEn();
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          labels.projectInspectorPreserveButton,
        ),
      );
      await tester.pump();
      await _finishWorker(tester);
      final reports = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.basename(file.path) == 'report.json')
          .toList();
      expect(
        reports,
        hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('\n'),
      );
      final report =
          jsonDecode(reports.single.readAsStringSync()) as Map<String, dynamic>;
      expect(report['status'], 'preserved');
      expect(report['byte_identical'], isTrue);
      expect(source.readAsBytesSync(), bytes);
      expect(File(report['backup_path'] as String).readAsBytesSync(), bytes);
      expect(
        File(report['reconstructed_path'] as String).readAsBytesSync(),
        bytes,
      );
      expect(
        find.textContaining(labels.projectInspectorPreserveLimit),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production passive inventory worker scans only injected temporary roots',
    (tester) async {
      final temporary = Directory.systemTemp.createTempSync(
        'dpm-inventory-worker-',
      );
      final root = Directory(temporary.resolveSymbolicLinksSync());
      addTearDown(() => root.deleteSync(recursive: true));
      final manifest = File(
        p.join(
          root.path,
          'Fixture.vst3',
          'Contents',
          'Resources',
          'moduleinfo.json',
        ),
      );
      manifest.parent.createSync(recursive: true);
      final content = jsonEncode({
        'Factory Info': {'Vendor': 'Fixture Vendor'},
        'Classes': [
          {
            'CID': '0123456789ABCDEF0123456789ABCDEF',
            'Name': 'Fixture Synth',
            'Category': 'Audio Module Class',
            'Version': '1.2.3',
          },
        ],
      });
      manifest.writeAsStringSync(content);
      await _mountWorkerPanel(
        tester,
        ProjectDependencyReport(
          path: p.join(root.path, 'Project.cpr'),
          formatId: 'cubase',
          pluginNames: const ['Recorded synth'],
          trackCount: 1,
          limitations: const [],
          pluginUidEvidence: const [
            CubasePluginUidEvidence(
              name: 'Recorded synth',
              uid: '0123456789ABCDEF0123456789ABCDEF',
              occurrences: 1,
              internalDevice: false,
            ),
          ],
        ),
        roots: [root.path],
      );
      final labels = AppLocalizationsEn();
      final button = find.widgetWithText(
        OutlinedButton,
        labels.projectInspectorScanButton,
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await _finishWorker(tester);
      expect(
        find.text(labels.projectInspectorScanSummary(1, 1)),
        findsOneWidget,
      );
      expect(
        find.text(labels.projectInspectorStatusIdentifierPresent),
        findsOneWidget,
      );
      expect(
        find.textContaining('Fixture Synth · VST3 · 1.2.3 · Fixture Vendor'),
        findsOneWidget,
      );
      expect(find.text(labels.projectInspectorPassiveScan), findsOneWidget);
      expect(manifest.readAsStringSync(), content);
      expect(root.listSync(recursive: true).whereType<File>(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('displays unknown dependency status without claiming success', (
    tester,
  ) async {
    const report = ProjectDependencyReport(
      path: 'demo.cpr',
      formatId: 'cubase',
      pluginNames: ['Mystic'],
      trackCount: 2,
      limitations: ['Preset state: not verified'],
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProjectDependencyReportPanel(report: report),
          ),
        ),
      ),
    );
    expect(find.text('Mystic'), findsOneWidget);
    expect(
      find.text('Installation and loadability: not tested'),
      findsOneWidget,
    );
    expect(find.text('Preset state: not verified'), findsOneWidget);
  });

  testWidgets(
    'scan uses project IDs, exposes warnings and accepts extra folders',
    (tester) async {
      const report = ProjectDependencyReport(
        path: 'demo.cpr',
        formatId: 'cubase',
        pluginNames: ['Old name'],
        trackCount: 1,
        limitations: [],
        pluginUidEvidence: [
          CubasePluginUidEvidence(
            name: 'Old name',
            uid: '0123456789ABCDEF0123456789ABCDEF',
            occurrences: 2,
            internalDevice: false,
          ),
        ],
      );
      List<String>? scannedRoots;
      final plugins = p.join(
        Directory.systemTemp.path,
        'dpm-panel-ui',
        'plugins',
      );
      final customPlugins = p.join(
        Directory.systemTemp.path,
        'dpm-panel-ui',
        'extra',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProjectDependencyReportPanel(
                report: report,
                inventoryScanner: (roots) {
                  scannedRoots = roots;
                  return LocalPluginInventoryReport(
                    candidates: [
                      LocalPluginCandidate(
                        path: p.join(plugins, 'Synth.vst3'),
                        name: 'New name',
                        format: 'VST3',
                        identifier: '0123456789ABCDEF0123456789ABCDEF',
                        vendor: 'Studio',
                        version: '2.0',
                      ),
                    ],
                    requestedRoots: roots,
                    scannedRoots: [plugins],
                    warnings: ['A folder was unavailable'],
                    visitedEntries: 2,
                    truncated: true,
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(scannedRoots, isNull);
      await tester.enterText(find.byType(TextField), customPlugins);
      await tester.ensureVisible(
        find.text('Scan local plug-in candidates (optional)'),
      );
      await tester.tap(find.text('Scan local plug-in candidates (optional)'));
      await tester.pumpAndSettle();
      expect(scannedRoots, contains(customPlugins));
      expect(
        find.text('Declared identifier found; loading and licence not tested'),
        findsOneWidget,
      );
      expect(
        find.text('Scan incomplete: entry or depth limit reached.'),
        findsOneWidget,
      );
      expect(find.text('Scan coverage and warnings (1)'), findsOneWidget);
      expect(
        find.textContaining('New name · VST3 · 2.0 · Studio'),
        findsOneWidget,
      );
    },
  );

  testWidgets('legacy import displays manual steps and loss boundary', (
    tester,
  ) async {
    final report = ProjectDependencyReport(
      path: 'old.arr',
      formatId: 'cubase-arr',
      pluginNames: const [],
      trackCount: null,
      limitations: const [],
      legacyConversionGuide: LegacyCubaseConversion.guideFor('old.arr'),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProjectDependencyReportPanel(report: report),
          ),
        ),
      ),
    );
    expect(find.text('Import legacy Cubase song'), findsOneWidget);
    expect(
      find.textContaining(
        'VST instruments, effects and mixer settings will be lost.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('File > Import > Cubase Song'), findsOneWidget);
    expect(find.text('Scan local plug-in candidates (optional)'), findsNothing);
  });

  testWidgets(
    'French labels use app delegates while diagnostic values stay intact',
    (tester) async {
      final l = AppLocalizationsFr();
      const report = ProjectDependencyReport(
        path: 'fixture.cpr',
        formatId: 'cubase',
        pluginNames: ['Fixture Synth'],
        trackCount: 4,
        savedDawVersion: '14.0.5',
        limitations: ['source_diagnostic_unchanged'],
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ProjectDependencyReportPanel(report: report),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.projectInspectorDependencies), findsOneWidget);
      expect(find.text(l.projectInspectorFormat('cubase')), findsOneWidget);
      expect(find.text(l.projectInspectorTracks('4')), findsOneWidget);
      expect(
        find.text(l.projectInspectorSavedVersion('14.0.5')),
        findsOneWidget,
      );
      expect(find.text(l.projectInspectorLoadabilityUntested), findsOneWidget);
      expect(find.text(l.projectInspectorScanButton), findsOneWidget);
      expect(find.text(l.projectInspectorLimitations), findsOneWidget);
      expect(find.text('source_diagnostic_unchanged'), findsOneWidget);
      expect(find.text('Fixture Synth'), findsOneWidget);
      expect(find.text('Project dependencies'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
