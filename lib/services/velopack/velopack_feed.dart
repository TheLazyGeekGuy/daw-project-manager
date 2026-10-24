import 'dart:convert';

import '../update_check_service.dart';

/// Every release carries `releases.win.json`, written by `vpk pack`: the
/// packages of this release and of the ones before it. The file name of the
/// feed on a GitHub release.
const kVelopackFeedAsset = 'releases.win.json';

enum VelopackAssetType { full, delta, other }

/// One package in the feed.
class VelopackAsset {
  final String packageId;
  final String version;
  final VelopackAssetType type;
  final String fileName;

  /// Uppercase hex, as vpk writes it.
  final String sha256;
  final int size;

  const VelopackAsset({
    required this.packageId,
    required this.version,
    required this.type,
    required this.fileName,
    required this.sha256,
    required this.size,
  });
}

/// Parses a `releases.win.json` feed:
/// `{"Assets":[{"PackageId":…,"Version":…,"Type":"Full"|"Delta",
/// "FileName":…,"SHA1":…,"SHA256":…,"Size":…}]}`. An entry missing a field
/// it needs is skipped; anything else unreadable throws [FormatException].
List<VelopackAsset> parseVelopackFeed(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic> || decoded['Assets'] is! List) {
    throw const FormatException('Not a Velopack feed.');
  }
  final assets = <VelopackAsset>[];
  for (final entry in (decoded['Assets'] as List).whereType<Map<String, dynamic>>()) {
    final packageId = entry['PackageId'];
    final version = entry['Version'];
    final fileName = entry['FileName'];
    final sha256 = entry['SHA256'];
    final size = entry['Size'];
    if (packageId is! String || version is! String || fileName is! String || sha256 is! String || size is! int) {
      continue;
    }
    assets.add(VelopackAsset(
      packageId: packageId,
      version: version,
      type: switch (entry['Type']) {
        'Full' || 1 => VelopackAssetType.full,
        'Delta' || 2 => VelopackAssetType.delta,
        _ => VelopackAssetType.other,
      },
      fileName: fileName,
      sha256: sha256,
      size: size,
    ));
  }
  return assets;
}

/// The full package to update [currentVersion] to: the newest one of
/// [packageId] newer than it, or null when there is none. Only full
/// packages: a delta needs the one before it applied first, and a full one
/// is a single download that always works.
VelopackAsset? fullPackageToInstall(
  List<VelopackAsset> feed, {
  required String packageId,
  required String currentVersion,
}) {
  VelopackAsset? newest;
  for (final asset in feed) {
    if (asset.type != VelopackAssetType.full) continue;
    if (asset.packageId.toLowerCase() != packageId.toLowerCase()) continue;
    if (!UpdateCheckService.isNewer(asset.version, currentVersion)) continue;
    if (newest == null || UpdateCheckService.isNewer(asset.version, newest.version)) {
      newest = asset;
    }
  }
  return newest;
}

/// How the app asks `Update.exe` to put a downloaded package in place: it
/// waits for this process ([waitPid]) to exit, swaps `current\`, and starts
/// the app again (restarting is `Update.exe apply`'s default).
List<String> velopackApplyArguments({
  required String packagePath,
  required int waitPid,
}) =>
    ['apply', '--package', packagePath, '--waitPid', '$waitPid'];
