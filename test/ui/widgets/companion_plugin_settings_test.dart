import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:daw_project_manager/ui/widgets/companion_plugin_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings > DAW plugin, as a plain view: no Hive, no Riverpod.
void main() {
  const installer = 'https://github.com/bandpassrecords/dpm-companion/releases/download/v0.2.0/DPM_Companion_Installer_v0.2.0.exe';
  const release = CompanionRelease('0.2.0', 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0',
      downloads: {CompanionPlatform.windows: installer});

  late List<String> opened;
  late List<bool> endChanges, startChanges;

  Future<void> pump(WidgetTester tester, {CompanionSighting? sighting, CompanionRelease? latest}) async {
    opened = [];
    endChanges = [];
    startChanges = [];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompanionPluginSettingsView(
            sighting: sighting,
            latestRelease: latest,
            platform: CompanionPlatform.windows,
            endSessionWhenDawCloses: true,
            startSessionWhenDawOpens: false,
            onDownload: opened.add,
            onEndSessionChanged: endChanges.add,
            onStartSessionChanged: startChanges.add,
          ),
        ),
      ),
    ));
  }

  testWidgets('not seen yet: says so, and the button downloads this platform\'s installer', (tester) async {
    await pump(tester, latest: release);
    expect(find.textContaining('Not seen on this computer yet'), findsOneWidget);
    expect(find.text('Download the DAW plugin'), findsOneWidget);
    expect(find.textContaining('is available'), findsNothing);

    await tester.tap(find.text('Download the DAW plugin'));
    expect(opened, [installer]);
  });

  testWidgets('seen: names the DAW and version; a newer release turns the button into an update', (tester) async {
    await pump(tester, sighting: CompanionSighting('0.1.0', 'Steinberg Cubase 13', DateTime(2026, 10, 19, 12, 51)), latest: release);
    expect(find.textContaining('Last seen in Steinberg Cubase 13 (version 0.1.0)'), findsOneWidget);
    expect(find.text('Version 0.2.0 is available.'), findsOneWidget);
    expect(find.text('Download the update'), findsOneWidget);
  });

  testWidgets('seen and up to date: no update offered', (tester) async {
    await pump(tester, sighting: CompanionSighting('0.2.0', 'REAPER', DateTime(2026, 10, 19)), latest: release);
    expect(find.textContaining('is available'), findsNothing);
    expect(find.text('Download the DAW plugin'), findsOneWidget);
  });

  testWidgets('without a known release the button opens the releases page', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Download the DAW plugin'));
    expect(opened, [companionReleasesPage]);
  });

  testWidgets('the work session switches report their changes', (tester) async {
    await pump(tester);
    await tester.tap(find.text('End the session when the DAW closes the project'));
    await tester.tap(find.text('Start a session when a project opens in the DAW'));
    expect(endChanges, [false]);
    expect(startChanges, [true]);
  });
}
