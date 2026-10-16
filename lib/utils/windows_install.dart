import 'dart:io';

/// The MSIX package's identity name. Must stay in sync with pubspec.yaml →
/// msix_config.identity_name.
const kMsixPackageName = 'BandPassRecords.DAWProjectManager';

/// Whether [exePath] is the app installed as its MSIX package — from the
/// Microsoft Store, or the `.msix` sideloaded from a release. Windows puts
/// every package under `WindowsApps`, in a folder named after its identity.
///
/// Auto-start picks its Windows registration by this test: a packaged app
/// registers with a Startup folder shortcut, an unpackaged one in the Run key.
bool isMsixExecutablePath(String exePath) =>
    exePath.contains('WindowsApps') && exePath.contains(kMsixPackageName);

/// Whether this process is the MSIX-packaged app. False off Windows, and for
/// the `.exe` installer's copy, which is a plain unpackaged install.
bool get isRunningAsMsix =>
    Platform.isWindows && isMsixExecutablePath(Platform.resolvedExecutable);

/// The release asset the `.exe` installer for [version] is uploaded as
/// (`asset_name` of the Windows installer build in release.yml). [version]
/// has no leading "v", as update checks report it.
Uri windowsInstallerDownloadUrl({
  required String owner,
  required String repo,
  required String version,
}) =>
    Uri.parse(
      'https://github.com/$owner/$repo/releases/download/'
      'v$version/DAW_Project_Manager_Installer_v$version.exe',
    );
