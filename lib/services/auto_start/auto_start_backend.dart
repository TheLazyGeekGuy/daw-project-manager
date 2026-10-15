/// Command-line flag the OS passes back to us on an auto-start launch when
/// the user asked to start minimized. Baked into the registry value /
/// shortcut / .desktop `Exec=` / LaunchAgent plist at registration time, and
/// read by `main()` (and by the Windows, Linux and macOS runners, which must
/// not show the window themselves) to decide whether to show the window.
///
/// A manual launch never carries it, which is the whole point — "start
/// minimized" must only apply to the login launch, not to the user
/// double-clicking the app.
const String kStartMinimizedFlag = '--minimized';

/// What the OS has registered, as far as this install is concerned.
enum AutoStartStatus {
  /// Nothing registered — or registered, but switched off by the user in the
  /// OS (Task Manager → Startup apps, GNOME's autostart toggle, macOS Login
  /// Items). The user's choice there is never overridden.
  off,

  /// Registered, exactly as [AutoStartBackend.setup] would write it now.
  on,

  /// Registered by this app, but no longer launching what it should: the
  /// executable it names is gone (a Store update replaced the versioned
  /// folder, the app was moved, an AppImage's temporary mount path), or it
  /// carries the wrong "start minimized" flag. Startup rewrites it.
  stale,

  /// The OS offers no way to ask — the Flatpak Background portal can set
  /// autostart but not report it. The cached preference stands.
  unknown,
}

/// Indirection over the OS-level "launch at login" registration so the
/// provider can be unit-tested without touching the Windows registry, the
/// Startup folder, `~/.config/autostart` or the macOS login items.
/// [AutoStartService.backend] is swapped for a fake in tests.
abstract class AutoStartBackend {
  /// Sets the flag the next [enable] and [status] go by. Touches nothing.
  Future<void> setup({required bool minimized});
  Future<AutoStartStatus> status();
  Future<bool> enable();
  Future<bool> disable();
}
