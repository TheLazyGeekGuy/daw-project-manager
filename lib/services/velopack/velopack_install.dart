import 'dart:io';

import 'package:path/path.dart' as p;

/// The id the self-updating Setup is packed with (`vpk pack --packId` in
/// release.yml). Velopack installs into `%LocalAppData%\<packId>\` and
/// deletes that whole folder on uninstall — so it must never be the app's
/// data folder, `%LOCALAPPDATA%\daw_project_manager` (`defaultAppDataDirName`),
/// which holds the library and the DAW plugin's bridge. A test holds the two
/// apart.
const kVelopackPackId = 'DAWProjectManager';

/// Where a Velopack install keeps its parts:
///
/// ```
/// %LocalAppData%\DAWProjectManager\
///   Update.exe            applies updates, starts the app, uninstalls
///   current\              the app itself, replaced whole by an update
///   packages\             downloaded update packages
/// ```
class VelopackInstall {
  final String rootDir;

  const VelopackInstall(this.rootDir);

  String get updateExe => p.join(rootDir, 'Update.exe');
  String get packagesDir => p.join(rootDir, 'packages');

  /// The install [exePath] runs from, or null when it isn't one: Velopack's
  /// own test is an `Update.exe` beside the folder the app runs from, and
  /// that folder is always `current`. [fileExists] is the seam for tests.
  static VelopackInstall? of(
    String exePath, {
    bool Function(String path)? fileExists,
  }) {
    final exists = fileExists ?? (path) => File(path).existsSync();
    final appDir = p.windows.dirname(exePath);
    if (p.windows.basename(appDir).toLowerCase() != 'current') return null;
    final rootDir = p.windows.dirname(appDir);
    if (!exists(p.windows.join(rootDir, 'Update.exe'))) return null;
    return VelopackInstall(rootDir);
  }

  /// This process's install; null off Windows and for every other kind of
  /// copy (MSIX, the Inno installer's, a portable folder).
  static VelopackInstall? get current =>
      Platform.isWindows ? of(Platform.resolvedExecutable) : null;
}
