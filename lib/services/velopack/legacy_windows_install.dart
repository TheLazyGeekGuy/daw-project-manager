import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// The uninstall entry the Inno Setup installer writes. installer.iss sets
/// no `AppId`, so Inno uses the app's name, plus its `_is1` suffix. It
/// installs for all users in 32-bit mode, so the entry sits in the 32-bit
/// view of `HKLM`; the other places are checked too, as a stray install
/// could have been made either way.
const kLegacyUninstallKey = r'Microsoft\Windows\CurrentVersion\Uninstall\DAW Project Manager_is1';

const _uninstallKeyPaths = [
  (hive: 'HKLM', path: 'SOFTWARE\\WOW6432Node\\$kLegacyUninstallKey'),
  (hive: 'HKLM', path: 'SOFTWARE\\$kLegacyUninstallKey'),
  (hive: 'HKCU', path: 'SOFTWARE\\$kLegacyUninstallKey'),
];

/// A copy installed by the Inno Setup installer, still on this computer
/// next to a Velopack install that took its place.
class LegacyWindowsInstall {
  /// The uninstaller (`unins000.exe`), unquoted.
  final String uninstaller;
  final String? installLocation;
  final String? version;

  const LegacyWindowsInstall({required this.uninstaller, this.installLocation, this.version});

  /// Removes it without questions: the uninstaller asks Windows for the
  /// rights it needs (one UAC prompt), deletes the program files and the
  /// shortcuts, and leaves `%LOCALAPPDATA%\daw_project_manager` — the
  /// library — alone, as installer.iss never listed it.
  static const uninstallArguments = ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'];

  /// Reads an uninstall entry's values (`UninstallString`, `InstallLocation`,
  /// `DisplayVersion`); null when it names no uninstaller, or one that is
  /// gone — then there is nothing left to remove.
  static LegacyWindowsInstall? fromValues(
    Map<String, String?> values, {
    bool Function(String path)? fileExists,
  }) {
    final exists = fileExists ?? (path) => File(path).existsSync();
    final command = values['UninstallString']?.trim();
    if (command == null || command.isEmpty) return null;
    final uninstaller = command.startsWith('"')
        ? command.substring(1, command.indexOf('"', 1) < 0 ? command.length : command.indexOf('"', 1))
        : command.split(' /').first;
    if (!exists(uninstaller)) return null;
    String? nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return LegacyWindowsInstall(
      uninstaller: uninstaller,
      installLocation: nonEmpty(values['InstallLocation']),
      version: nonEmpty(values['DisplayVersion']),
    );
  }

  /// The old install on this computer, if there is one. Windows only.
  static LegacyWindowsInstall? find() {
    if (!Platform.isWindows) return null;
    for (final entry in _uninstallKeyPaths) {
      final values = _readValues(entry.hive == 'HKLM' ? LOCAL_MACHINE : CURRENT_USER, entry.path);
      if (values == null) continue;
      final install = fromValues(values);
      if (install != null) return install;
    }
    return null;
  }

  static Map<String, String?>? _readValues(PredefinedRegistryKey hive, String path) {
    final RegistryKey key;
    try {
      key = hive.open(path, config: const RegistryOpenConfig(access: RegistryAccess.read));
    } catch (_) {
      return null;
    }
    try {
      return {
        for (final name in const ['UninstallString', 'InstallLocation', 'DisplayVersion'])
          name: key.getString(name),
      };
    } finally {
      key.close();
    }
  }

  /// Starts the uninstaller. Inno's copies itself to a temporary folder and
  /// exits at once, so this doesn't wait for the removal; [find] tells
  /// afterwards whether it went. An uninstaller that insists on running as
  /// administrator can't be started by CreateProcess (error 740); Windows'
  /// "run as" verb, through PowerShell, starts it with the UAC prompt.
  Future<void> uninstall() async {
    try {
      await Process.start(uninstaller, uninstallArguments, mode: ProcessStartMode.detached);
    } on ProcessException catch (e) {
      if (e.errorCode != _errorElevationRequired) rethrow;
      String quoted(String s) => "'${s.replaceAll("'", "''")}'";
      await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Process -Verb RunAs -FilePath ${quoted(uninstaller)} '
            '-ArgumentList ${uninstallArguments.map(quoted).join(',')}',
      ], mode: ProcessStartMode.detached);
    }
  }

  static const _errorElevationRequired = 740;
}
