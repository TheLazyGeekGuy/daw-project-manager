import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'auto_start/auto_start_backend.dart';
import 'auto_start/platform_backends_stub.dart'
    if (dart.library.io) 'auto_start/platform_backends.dart';

export 'auto_start/auto_start_backend.dart';

/// Desktop-only "start the app when I sign in" registration.
///
/// One backend per way the app is installed (`auto_start/platform_backends.dart`):
/// - Windows `.exe` install: `HKCU\…\CurrentVersion\Run`.
/// - Windows MSIX (Store): a Startup folder shortcut to the package's
///   execution alias — never to the exe, whose folder every update replaces.
/// - macOS: a login item or LaunchAgent, answered natively by
///   `macos/Runner/MainFlutterWindow.swift`.
/// - Linux tarball / AppImage: a `.desktop` file in `~/.config/autostart`
///   (naming the AppImage file, not its temporary mount).
/// - Flatpak: the Background portal.
///
/// Every method is failure-tolerant: registering at login touches the
/// registry / the filesystem / a native channel / D-Bus, all of which can
/// fail for reasons the user can't act on (locked-down machine, sandboxed
/// install, no portal). None of that should break a settings toggle, so
/// failures are logged in debug and reported as `false` (or
/// [AutoStartStatus.unknown] for a status read).
class AutoStartService {
  AutoStartService._();

  @visibleForTesting
  static AutoStartBackend backend = createPlatformAutoStartBackend();

  /// Resets [backend] to the real implementation. For tests that swap it.
  @visibleForTesting
  static void resetBackend() => backend = createPlatformAutoStartBackend();

  /// Launch-at-login only exists on desktop. Mobile OSes don't let an app
  /// register itself to start at boot, so the whole feature is hidden there.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Whether this process was launched by the OS's auto-start mechanism with
  /// the "start minimized" flag. Only ever true on a login launch.
  static bool launchedMinimized(List<String> args) =>
      isSupported && args.contains(kStartMinimizedFlag);

  // Tracked rather than a plain bool: the flag is baked into the registration
  // by enable(), so a change to `minimized` has to reach the backend first or
  // the registration would keep the stale flag.
  static bool? _setUpMinimized;

  /// Must run before any other call. Cheap to call repeatedly — it only does
  /// work when [minimized] differs from the last setup.
  static Future<void> setup({required bool minimized}) async {
    if (!isSupported || _setUpMinimized == minimized) return;
    try {
      await backend.setup(minimized: minimized);
      _setUpMinimized = minimized;
    } catch (e) {
      if (kDebugMode) print('[AutoStartService] setup failed: $e');
    }
  }

  /// What the OS has registered. A failed read is [AutoStartStatus.unknown],
  /// not "off": a registry hiccup must not flip the user's switch.
  static Future<AutoStartStatus> status() async {
    if (!isSupported) return AutoStartStatus.off;
    try {
      return await backend.status();
    } catch (e) {
      if (kDebugMode) print('[AutoStartService] status failed: $e');
      return AutoStartStatus.unknown;
    }
  }

  /// Registers or unregisters the app. Returns whether the OS state ended up
  /// matching [value] — a `false` return means the toggle didn't take effect
  /// and the caller should not persist [value] as the user's preference.
  static Future<bool> setEnabled(bool value) async {
    if (!isSupported) return false;
    try {
      return value ? await backend.enable() : await backend.disable();
    } catch (e) {
      if (kDebugMode) print('[AutoStartService] setEnabled($value) failed: $e');
      return false;
    }
  }

  /// Rewrites an existing registration so it picks up a changed [minimized]
  /// flag, or repairs a stale one. Unregisters first because the flag lives
  /// *inside* the registration (registry value / shortcut / Exec= line /
  /// plist) and, on macOS, changing it can even change which mechanism is
  /// used — so re-enabling over the top would either no-op or leave the old
  /// one behind.
  static Future<bool> reapply({required bool minimized}) async {
    if (!isSupported) return false;
    try {
      await backend.disable();
      _setUpMinimized = null;
      await setup(minimized: minimized);
      return await backend.enable();
    } catch (e) {
      if (kDebugMode) print('[AutoStartService] reapply failed: $e');
      return false;
    }
  }

  /// Whether the app will launch at login, after repairing a registration
  /// that has gone stale (see [AutoStartStatus.stale]) — the repair is what
  /// keeps a Store update or a moved install from silently ending auto-start.
  /// Null when the OS can't say ([AutoStartStatus.unknown]).
  static Future<bool?> reconcile({required bool minimized}) async {
    if (!isSupported) return false;
    await setup(minimized: minimized);
    return switch (await status()) {
      AutoStartStatus.on => true,
      AutoStartStatus.off => false,
      AutoStartStatus.unknown => null,
      AutoStartStatus.stale => await reapply(minimized: minimized),
    };
  }

  @visibleForTesting
  static void resetSetupFlagForTest() => _setUpMinimized = null;
}
