import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_install_scan.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:daw_project_manager/ui/widgets/companion_plugin_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

/// Settings > DAW plugin, as a plain view: no Hive, no Riverpod.
void main() {
  const installer = 'https://github.com/bandpassrecords/daw-project-manager-plugin/releases/download/v0.2.0/DAW_Project_Manager_Plugin_Installer_v0.2.0.exe';
  const release = CompanionRelease('0.2.0', 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0',
      downloads: {CompanionPlatform.windows: installer});

  late List<String> opened;
  late List<bool> endChanges, startChanges;
  late int addFolderTaps, searchAgainTaps;

  Future<void> pump(
    WidgetTester tester, {
    CompanionSighting? sighting,
    CompanionRelease? latest,
    List<CompanionInstall>? installs = const [],
    bool scanAvailable = true,
    List<String> customFolders = const [],
  }) async {
    opened = [];
    endChanges = [];
    startChanges = [];
    addFolderTaps = 0;
    searchAgainTaps = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
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
            installs: installs,
            scanAvailable: scanAvailable,
            customFolders: customFolders,
            onSearchAgain: () => searchAgainTaps++,
            onAddFolder: () => addFolderTaps++,
            onRemoveFolder: (_) {},
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

  group('installed copies', () {
    const allUsers = CompanionInstall(r'C:\Program Files\Common Files\VST3\DAW Project Manager.vst3', CompanionPluginFormat.vst3, '0.1.0');
    const justMe = CompanionInstall(r'C:\Users\ana\AppData\Local\Programs\Common\VST3\DAW Project Manager.vst3', CompanionPluginFormat.vst3, '0.1.0');

    testWidgets('each copy shows its format, version and folder; no custom folders offered', (tester) async {
      await pump(tester, installs: [allUsers]);
      expect(find.text('VST3  ·  Version 0.1.0'), findsOneWidget);
      expect(find.text(allUsers.path), findsOneWidget);
      expect(find.text('Add Folder'), findsNothing);
      expect(find.textContaining('More than one copy'), findsNothing);
    });

    testWidgets('two copies of one format are flagged', (tester) async {
      await pump(tester, installs: [allUsers, justMe]);
      expect(find.textContaining('More than one copy is installed'), findsOneWidget);
    });

    testWidgets('nothing in the standard folders: says so and offers the user\'s own', (tester) async {
      await pump(tester, customFolders: [r'D:\My Plugins']);
      expect(find.text('Not found in the standard plug-in folders.'), findsOneWidget);
      expect(find.text(r'D:\My Plugins'), findsOneWidget);
      await tester.tap(find.text('Add Folder'));
      await tester.tap(find.text('Search again'));
      expect(addFolderTaps, 1);
      expect(searchAgainTaps, 1);
    });

    testWidgets('a copy found in the user\'s folder keeps those folders on show', (tester) async {
      const custom = CompanionInstall(r'D:\My Plugins\DAW Project Manager.vst3', CompanionPluginFormat.vst3, '0.1.0', inCustomFolder: true);
      await pump(tester, installs: [custom], customFolders: [r'D:\My Plugins']);
      expect(find.textContaining('your folder'), findsOneWidget);
      expect(find.text('Add Folder'), findsOneWidget);
    });

    testWidgets('an installed copy older than the newest release offers the update, even never seen running', (tester) async {
      await pump(tester, installs: [allUsers], latest: release);
      expect(find.text('Version 0.2.0 is available.'), findsOneWidget);
      expect(find.text('Download the update'), findsOneWidget);
    });

    testWidgets('inside the Flatpak it explains it can\'t look', (tester) async {
      await pump(tester, installs: null, scanAvailable: false);
      expect(find.textContaining("The Flatpak can't look"), findsOneWidget);
      expect(find.text('Search again'), findsNothing);
    });
  });

  testWidgets('the work session switches report their changes', (tester) async {
    await pump(tester);
    for (final label in ['End the session when the DAW closes the project', 'Start a session when a project opens in the DAW']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(endChanges, [false]);
    expect(startChanges, [true]);
  });
}
