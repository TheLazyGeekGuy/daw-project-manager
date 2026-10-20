import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'companion_protocol.dart';

/// Finding the DAW Project Manager plugin on disk, for Settings > DAW plugin:
/// which copies are installed, where, and which version — read from the
/// plugin's own metadata files, never by loading its code.

enum CompanionPluginFormat { vst3, au }

/// One installed copy of the plugin.
class CompanionInstall {
  final String path;
  final CompanionPluginFormat format;
  final String version;

  /// Found in a folder the user added, not a standard one.
  final bool inCustomFolder;

  const CompanionInstall(this.path, this.format, this.version, {this.inCustomFolder = false});
}

/// The bundle names the plugin installs as.
const companionVst3BundleName = 'DAW Project Manager.vst3';
const companionAuBundleName = 'DAW Project Manager.component';
const _pluginName = 'DAW Project Manager';
const _vendor = 'BandPass Records';
const _bundleId = 'com.bandpassrecords.dpm.plugin';

/// The folders hosts scan, where the plugin's installers put it — and, on
/// Windows, wherever the installer recorded it was put ([installerFolder]).
/// Paths are built with [pathContext] so the list is testable for any OS.
List<({String folder, CompanionPluginFormat format})> standardCompanionFolders({
  required CompanionPlatform platform,
  required String home,
  String? localAppData,
  String? commonProgramFiles,
  String? installerFolder,
  p.Context? pathContext,
}) {
  final ctx = pathContext ?? p.context;
  const vst3 = CompanionPluginFormat.vst3, au = CompanionPluginFormat.au;

  switch (platform) {
    case CompanionPlatform.windows:
      return [
        (folder: ctx.join(commonProgramFiles ?? r'C:\Program Files\Common Files', 'VST3'), format: vst3),
        (folder: ctx.join(localAppData ?? ctx.join(home, 'AppData', 'Local'), 'Programs', 'Common', 'VST3'), format: vst3),
        if (installerFolder != null && installerFolder.trim().isNotEmpty) (folder: installerFolder.trim(), format: vst3),
      ];
    case CompanionPlatform.macOS:
      return [
        (folder: '/Library/Audio/Plug-Ins/VST3', format: vst3),
        (folder: ctx.join(home, 'Library', 'Audio', 'Plug-Ins', 'VST3'), format: vst3),
        (folder: '/Library/Audio/Plug-Ins/Components', format: au),
        (folder: ctx.join(home, 'Library', 'Audio', 'Plug-Ins', 'Components'), format: au),
      ];
    case CompanionPlatform.linux:
      return [
        (folder: ctx.join(home, '.vst3'), format: vst3),
        (folder: '/usr/local/lib/vst3', format: vst3),
        (folder: '/usr/lib/vst3', format: vst3),
      ];
  }
}

/// The version in a VST3 bundle's `Contents/Resources/moduleinfo.json`, when
/// it is ours. JUCE writes the file with trailing commas, which strict JSON
/// rejects, so they are dropped first.
String? companionVersionFromModuleInfo(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!));
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final factory = decoded['Factory Info'];
  final vendor = factory is Map<String, dynamic> ? factory['Vendor'] : null;
  final version = decoded['Version'];
  if (decoded['Name'] != _pluginName || vendor != _vendor || version is! String || version.isEmpty) return null;
  return version;
}

/// The version in a macOS bundle's `Contents/Info.plist`, when it is ours.
String? companionVersionFromInfoPlist(String text) {
  String? value(String key) =>
      RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(text)?.group(1)?.trim();
  if (!(value('CFBundleIdentifier') ?? '').startsWith(_bundleId)) return null;
  final version = value('CFBundleShortVersionString') ?? value('CFBundleVersion');
  return version == null || version.isEmpty ? null : version;
}

/// The folder the Windows installer recorded, from `reg query`'s answer for
/// the plugin's uninstall key ("InstallLocation    REG_SZ    C:\…\VST3\").
String? parseRegQueryInstallLocation(String output) {
  final m = RegExp(r'InstallLocation\s+REG_\w+\s+(.+)').firstMatch(output);
  final value = m?.group(1)?.trim();
  if (value == null || value.isEmpty) return null;
  return value.endsWith(r'\') && value.length > 3 ? value.substring(0, value.length - 1) : value;
}

/// The plugin's Windows uninstall key (installer.iss: AppId), per user and per machine.
const companionUninstallKeys = [
  r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6E2C9B0A-4C1E-4D8B-9B2F-3A7E5C1D8F42}_is1',
  r'HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6E2C9B0A-4C1E-4D8B-9B2F-3A7E5C1D8F42}_is1',
];

/// Looks for the plugin in [folders]: a `DAW Project Manager.vst3` /
/// `.component` bundle whose metadata says it is ours. Missing or unreadable
/// folders are skipped.
Future<List<CompanionInstall>> scanCompanionFolders(
  List<({String folder, CompanionPluginFormat format})> folders, {
  bool custom = false,
}) async {
  final found = <CompanionInstall>[];
  final seen = <String>{};

  for (final f in folders) {
    final name = f.format == CompanionPluginFormat.vst3 ? companionVst3BundleName : companionAuBundleName;
    final bundle = p.normalize(p.join(f.folder, name));
    if (!seen.add(bundle.toLowerCase())) continue;
    if (!await Directory(bundle).exists()) continue;

    String? version;
    try {
      final moduleInfo = File(p.join(bundle, 'Contents', 'Resources', 'moduleinfo.json'));
      if (await moduleInfo.exists()) version = companionVersionFromModuleInfo(await moduleInfo.readAsString());
      final plist = File(p.join(bundle, 'Contents', 'Info.plist'));
      if (version == null && await plist.exists()) version = companionVersionFromInfoPlist(await plist.readAsString());
    } catch (_) {}

    if (version != null) found.add(CompanionInstall(bundle, f.format, version, inCustomFolder: custom));
  }
  return found;
}

/// The search behind the settings: the standard folders first; the user's
/// own folders only when nothing turned up there.
Future<List<CompanionInstall>> findCompanionInstalls({
  required List<({String folder, CompanionPluginFormat format})> standard,
  required List<String> customFolders,
  required CompanionPlatform platform,
}) async {
  final found = await scanCompanionFolders(standard);
  if (found.isNotEmpty || customFolders.isEmpty) return found;

  return scanCompanionFolders([
    for (final folder in customFolders) ...[
      (folder: folder, format: CompanionPluginFormat.vst3),
      if (platform == CompanionPlatform.macOS) (folder: folder, format: CompanionPluginFormat.au),
    ],
  ], custom: true);
}

/// More than one copy of one format: the DAW may load either.
bool hasDuplicateCompanionInstalls(List<CompanionInstall> installs) {
  final vst3 = installs.where((i) => i.format == CompanionPluginFormat.vst3).length;
  final au = installs.where((i) => i.format == CompanionPluginFormat.au).length;
  return vst3 > 1 || au > 1;
}

/// The highest installed version, or null.
String? newestInstalledCompanionVersion(List<CompanionInstall> installs) {
  String? best;
  for (final i in installs) {
    if (best == null || isNewerCompanionVersion(i.version, best)) best = i.version;
  }
  return best;
}

/// Inside the Flatpak sandbox the plug-in folders can't be seen: no search.
bool get companionScanAvailable => !(Platform.isLinux && File('/.flatpak-info').existsSync());

/// The standard folders of the machine the app runs on, the installer's
/// recorded folder included.
Future<List<({String folder, CompanionPluginFormat format})>> standardCompanionFoldersHere() async {
  final platform = Platform.isWindows
      ? CompanionPlatform.windows
      : Platform.isMacOS
          ? CompanionPlatform.macOS
          : CompanionPlatform.linux;
  final env = Platform.environment;

  String? installerFolder;
  if (platform == CompanionPlatform.windows) {
    for (final key in companionUninstallKeys) {
      try {
        final r = await Process.run('reg', ['query', key, '/v', 'InstallLocation']);
        installerFolder = parseRegQueryInstallLocation('${r.stdout}');
        if (installerFolder != null) break;
      } catch (_) {}
    }
  }

  return standardCompanionFolders(
    platform: platform,
    home: env['USERPROFILE'] ?? env['HOME'] ?? '',
    localAppData: env['LOCALAPPDATA'],
    commonProgramFiles: env['CommonProgramFiles'],
    installerFolder: installerFolder,
  );
}
