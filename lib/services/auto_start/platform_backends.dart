import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';
import 'package:xdg_desktop_portal/xdg_desktop_portal.dart';

import '../../utils/windows_install.dart';
import 'auto_start_backend.dart';
import 'auto_start_rules.dart';
import 'shell_link.dart';

/// The backend for the platform and packaging this process runs as.
/// Constructing one touches nothing; only its methods reach the OS.
AutoStartBackend createPlatformAutoStartBackend() {
  if (Platform.isWindows) {
    return isRunningAsMsix
        ? _WindowsStartupShortcutBackend()
        : _WindowsRunKeyBackend();
  }
  if (Platform.isMacOS) return _MacOsBackend();
  if (Platform.isLinux) {
    // Same marker GoogleDriveSyncService.isSupported goes by: every Flatpak
    // app has /.flatpak-info at runtime.
    return File('/.flatpak-info').existsSync()
        ? _FlatpakPortalBackend()
        : _LinuxDesktopFileBackend();
  }
  return _UnsupportedBackend();
}

class _UnsupportedBackend implements AutoStartBackend {
  @override
  Future<void> setup({required bool minimized}) async {}
  @override
  Future<AutoStartStatus> status() async => AutoStartStatus.off;
  @override
  Future<bool> enable() async => false;
  @override
  Future<bool> disable() async => false;
}

// ---------------------------------------------------------------------------
// Windows, `.exe` installer and portable builds: HKCU\…\Run
// ---------------------------------------------------------------------------

class _WindowsRunKeyBackend implements AutoStartBackend {
  static const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  bool _minimized = false;

  String get _exe => Platform.resolvedExecutable;

  @override
  Future<void> setup({required bool minimized}) async => _minimized = minimized;

  /// Reads from a key that may not exist yet (`StartupApproved\Run` doesn't
  /// on a fresh profile) — a missing key reads as a missing value.
  T? _open<T>(
    String path,
    T? Function(RegistryKey key) body, {
    RegistryAccess access = RegistryAccess.read,
  }) {
    final RegistryKey key;
    try {
      key = CURRENT_USER.open(path, config: RegistryOpenConfig(access: access));
    } catch (_) {
      return null;
    }
    try {
      return body(key);
    } finally {
      key.close();
    }
  }

  void _write(String path, void Function(RegistryKey key) body) {
    final key = CURRENT_USER.create(path);
    try {
      body(key);
    } finally {
      key.close();
    }
  }

  @override
  Future<AutoStartStatus> status() async {
    final value = _open(_runPath, (k) => k.getString(kAutoStartAppName));
    if (value == null) return AutoStartStatus.off;
    final approval =
        _open(_approvedPath, (k) => k.getBinary(kAutoStartAppName));
    final registeredExe = windowsRunCommandExecutable(value);
    return classifyRegistration(
      present: true,
      disabledByUser: startupApprovalDisables(approval),
      matchesExpected: windowsPathsEqual(
        value,
        windowsRunCommand(_exe, minimized: _minimized),
      ),
      pointsAtThisApp:
          registeredExe != null && windowsPathsEqual(registeredExe, _exe),
      targetExists: registeredExe != null && File(registeredExe).existsSync(),
    );
  }

  @override
  Future<bool> enable() async {
    _write(_runPath, (k) {
      k.setValue(
        kAutoStartAppName,
        StringValue(windowsRunCommand(_exe, minimized: _minimized)),
      );
    });
    // An even first byte is "allowed" — this clears a switch-off made in
    // Task Manager, which is what turning the setting on in the app means.
    final approved = Uint8List(12)..[0] = 2;
    _write(_approvedPath, (k) {
      k.setValue(kAutoStartAppName, BinaryValue(approved));
    });
    return true;
  }

  @override
  Future<bool> disable() async {
    for (final path in const [_runPath, _approvedPath]) {
      _open(
        path,
        (k) {
          if (k.getValue(kAutoStartAppName) != null) {
            k.removeValue(kAutoStartAppName);
          }
          return null;
        },
        access: RegistryAccess.all,
      );
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Windows, MSIX (Microsoft Store / sideloaded package): Startup folder
// ---------------------------------------------------------------------------

/// A packaged app's registry writes to `HKCU` land in its private hive,
/// which Windows doesn't read at login — so the Store build registers with
/// a Startup folder shortcut instead, which does land in the real folder.
///
/// The shortcut targets the package's execution alias, never the exe: the
/// exe's folder is named after the package version and every Store update
/// deletes it, which silently broke auto-start after each update while the
/// settings switch kept saying "on".
class _WindowsStartupShortcutBackend implements AutoStartBackend {
  static const _approvedPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder';

  bool _minimized = false;

  @override
  Future<void> setup({required bool minimized}) async => _minimized = minimized;

  String get _shortcutPath =>
      startupShortcutPath(Platform.environment['APPDATA']!);

  /// The alias is a zero-byte reparse point Dart's `existsSync` can't see
  /// through, so it is checked without following it. The user can switch
  /// it off in Settings → Apps → App execution aliases; the exe is the
  /// fallback then, and the next launch after an update repairs it.
  String get _target {
    final alias = msixAliasPath(Platform.environment['LOCALAPPDATA']);
    if (alias != null &&
        FileSystemEntity.typeSync(alias, followLinks: false) !=
            FileSystemEntityType.notFound) {
      return alias;
    }
    return Platform.resolvedExecutable;
  }

  bool get _disabledByUser {
    // A missing key (no item was ever switched off) reads as allowed.
    final RegistryKey key;
    try {
      key = CURRENT_USER.open(_approvedPath);
    } catch (_) {
      return false;
    }
    try {
      return startupApprovalDisables(
          key.getBinary('$kAutoStartAppName.lnk'));
    } finally {
      key.close();
    }
  }

  @override
  Future<AutoStartStatus> status() async {
    final file = File(_shortcutPath);
    if (!file.existsSync()) return AutoStartStatus.off;
    final link = parseShellLink(file.readAsBytesSync());
    final target = link?.target;
    return classifyRegistration(
      present: true,
      disabledByUser: _disabledByUser,
      matchesExpected: target != null &&
          windowsPathsEqual(target, _target) &&
          argumentsCarryFlag(link!.arguments, kStartMinimizedFlag) ==
              _minimized,
      // Only the packaged app writes this shortcut, so whatever it points
      // at — an old version's folder, the exe instead of the alias, the
      // wrong flag — is this app's own registration to repair.
      pointsAtThisApp: true,
      targetExists: true,
    );
  }

  @override
  Future<bool> enable() async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      startupShortcutScript(
        shortcutPath: _shortcutPath,
        target: _target,
        arguments: _minimized ? kStartMinimizedFlag : '',
      ),
    ]);
    if (result.exitCode != 0) {
      throw Exception('Failed to create shortcut: ${result.stderr}');
    }
    // A shortcut the user switched off in Task Manager stays off: the
    // packaged app can't clear that switch (its registry writes are
    // private), so report it rather than claim the setting took.
    return File(_shortcutPath).existsSync() && !_disabledByUser;
  }

  @override
  Future<bool> disable() async {
    final file = File(_shortcutPath);
    if (file.existsSync()) file.deleteSync();
    return !file.existsSync();
  }
}

// ---------------------------------------------------------------------------
// Linux tarball / AppImage: ~/.config/autostart
// ---------------------------------------------------------------------------

class _LinuxDesktopFileBackend implements AutoStartBackend {
  bool _minimized = false;

  @override
  Future<void> setup({required bool minimized}) async => _minimized = minimized;

  String get _exe =>
      linuxLaunchExecutable(Platform.environment, Platform.resolvedExecutable);

  List<String> get _argv => [_exe, if (_minimized) kStartMinimizedFlag];

  File get _file {
    final dir = autostartDirectory(Platform.environment);
    if (dir == null) throw StateError('Neither XDG_CONFIG_HOME nor HOME is set');
    return File(p.join(dir, '$kAutoStartAppName.desktop'));
  }

  @override
  Future<AutoStartStatus> status() async {
    final file = _file;
    if (!file.existsSync()) return AutoStartStatus.off;
    final facts = readAutostartEntry(file.readAsStringSync());
    final exec = facts.exec;
    final args = exec == null ? const <String>[] : parseDesktopExec(exec);
    final registeredExe = args.isEmpty ? null : args.first;
    return classifyRegistration(
      present: true,
      disabledByUser: facts.disabled,
      matchesExpected: exec == desktopExecLine(_argv),
      // The running binary counts too: inside an AppImage that is the
      // temporary mount path earlier builds registered.
      pointsAtThisApp: registeredExe == _exe ||
          registeredExe == Platform.resolvedExecutable,
      targetExists: registeredExe != null && File(registeredExe).existsSync(),
    );
  }

  @override
  Future<bool> enable() async {
    final file = _file;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(autostartDesktopEntry(_argv));
    return true;
  }

  @override
  Future<bool> disable() async {
    final file = _file;
    if (file.existsSync()) file.deleteSync();
    return true;
  }
}

// ---------------------------------------------------------------------------
// Flatpak: the Background portal
// ---------------------------------------------------------------------------

/// The sandbox can't see the host's `~/.config/autostart`, and a path under
/// `/app` means nothing outside it. The Background portal writes the host's
/// autostart entry itself (as `flatpak run …`), and may ask the user first —
/// which is why a request can wait on a dialog. It can't be asked what it
/// has, so [status] is [AutoStartStatus.unknown] and the cached preference
/// stands.
class _FlatpakPortalBackend implements AutoStartBackend {
  bool _minimized = false;

  @override
  Future<void> setup({required bool minimized}) async => _minimized = minimized;

  @override
  Future<AutoStartStatus> status() async => AutoStartStatus.unknown;

  Future<XdgBackgroundPortalRequestResult> _request({required bool autostart}) async {
    final client = XdgDesktopPortalClient();
    try {
      return await client.background
          .requestBackground(
            autostart: autostart,
            commandLine: [kFlatpakCommand, if (_minimized) kStartMinimizedFlag],
          )
          .first
          // Generous: the portal may be waiting on the user's answer.
          .timeout(const Duration(minutes: 2));
    } finally {
      await client.close();
    }
  }

  @override
  Future<bool> enable() async => (await _request(autostart: true)).autostart;

  @override
  Future<bool> disable() async => !(await _request(autostart: false)).autostart;
}

// ---------------------------------------------------------------------------
// macOS: answered natively by macos/Runner/MainFlutterWindow.swift
// ---------------------------------------------------------------------------

class _MacOsBackend implements AutoStartBackend {
  static const _channel = MethodChannel('launch_at_startup');

  @override
  Future<void> setup({required bool minimized}) => _channel.invokeMethod<void>(
        'launchAtStartupSetLaunchMinimized',
        {'minimized': minimized},
      );

  @override
  Future<AutoStartStatus> status() async {
    final name = await _channel.invokeMethod<String>('launchAtStartupStatus');
    return AutoStartStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => throw StateError('Unexpected login item status: $name'),
    );
  }

  @override
  Future<bool> enable() async =>
      await _channel.invokeMethod<bool>(
        'launchAtStartupSetEnabled',
        {'setEnabledValue': true},
      ) ??
      false;

  @override
  Future<bool> disable() async =>
      await _channel.invokeMethod<bool>(
        'launchAtStartupSetEnabled',
        {'setEnabledValue': false},
      ) ??
      false;
}
