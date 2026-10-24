import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../update_download.dart';
import 'velopack_feed.dart';
import 'velopack_install.dart';

/// GitHub repo to fetch release assets from — redeclared per file, as the
/// other update services do.
const String _kGithubOwner = String.fromEnvironment('GITHUB_OWNER', defaultValue: 'bandpassrecords');
const String _kGithubRepo = String.fromEnvironment('GITHUB_REPO', defaultValue: 'daw-project-manager');

/// A package to update to, and where its release keeps it.
class VelopackUpdate {
  final VelopackAsset package;
  final Uri packageUrl;

  const VelopackUpdate({required this.package, required this.packageUrl});
}

/// Updates a Velopack install of the app (the Windows installer's) in place:
/// reads the release's feed, downloads the full package into the install's
/// `packages\` folder, checks it against the feed's SHA-256, and hands it to
/// `Update.exe`, which swaps `current\` once the app has exited and starts it
/// again. Nothing here runs Velopack's own code in the app: its update
/// manager is .NET or Rust, and the steps it takes are these.
class VelopackUpdateService {
  final http.Client _client;
  final VelopackInstall install;
  final String currentVersion;
  final Future<void> Function(String executable, List<String> arguments) _startDetached;

  VelopackUpdateService({
    required this.install,
    required this.currentVersion,
    http.Client? client,
    Future<void> Function(String executable, List<String> arguments)? startDetached,
  })  : _client = client ?? http.Client(),
        _startDetached = startDetached ??
            ((executable, arguments) =>
                Process.start(executable, arguments, mode: ProcessStartMode.detached));

  void close() => _client.close();

  /// The update in the release tagged `v$version`, or null when that release
  /// has no feed or nothing in it is newer than [currentVersion].
  Future<VelopackUpdate?> fetchUpdate(String version) async {
    if (_kGithubOwner.isEmpty || _kGithubRepo.isEmpty) return null;
    final releaseUri = Uri.parse(
      'https://api.github.com/repos/$_kGithubOwner/$_kGithubRepo/releases/tags/v$version',
    );
    final response = await _client
        .get(releaseUri, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final feedUrl = assetUrl(assets, kVelopackFeedAsset);
    if (feedUrl == null) return null;
    final feedResponse = await _client.get(feedUrl).timeout(const Duration(seconds: 15));
    if (feedResponse.statusCode != 200) {
      throw StateError('Failed to download the update feed (HTTP ${feedResponse.statusCode}).');
    }
    return updateFrom(assets, parseVelopackFeed(feedResponse.body), currentVersion: currentVersion);
  }

  /// Pure part of [fetchUpdate]: the newest full package in [feed] that is
  /// attached to this release ([assets], the GitHub API's `assets` array).
  /// The feed also lists older releases' packages, which live on those
  /// releases — only this one's are needed.
  static VelopackUpdate? updateFrom(
    List<Map<String, dynamic>> assets,
    List<VelopackAsset> feed, {
    required String currentVersion,
  }) {
    final package = fullPackageToInstall(feed, packageId: kVelopackPackId, currentVersion: currentVersion);
    if (package == null) return null;
    final url = assetUrl(assets, package.fileName);
    if (url == null) return null;
    return VelopackUpdate(package: package, packageUrl: url);
  }

  static Uri? assetUrl(List<Map<String, dynamic>> assets, String name) {
    for (final asset in assets) {
      if (asset['name'] == name && asset['browser_download_url'] is String) {
        return Uri.parse(asset['browser_download_url'] as String);
      }
    }
    return null;
  }

  /// Where [update]'s package is put once it has been checked.
  String packagePath(VelopackUpdate update) => p.join(install.packagesDir, update.package.fileName);

  /// Downloads [update]'s package and checks it against the feed. It is
  /// written to a `.part` file and renamed only once its hash matches, so a
  /// cancelled or failed download never leaves something that looks ready.
  /// A package already there with the right hash isn't downloaded again.
  Future<String> download(
    VelopackUpdate update, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    final target = File(packagePath(update));
    final expected = update.package.sha256.toLowerCase();
    if (await target.exists() && await sha256OfFile(target) == expected) {
      onProgress?.call(1);
      return target.path;
    }

    await Directory(install.packagesDir).create(recursive: true);
    final part = File('${target.path}.part');
    try {
      if (cancelToken?.isCancelled ?? false) throw const UpdateCancelledException();
      await downloadToFile(_client, update.packageUrl, part, onProgress: onProgress, cancelToken: cancelToken);
      if (cancelToken?.isCancelled ?? false) throw const UpdateCancelledException();
      if (await sha256OfFile(part) != expected) {
        throw StateError('Checksum mismatch: the downloaded update did not match the release feed.');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return target.path;
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Starts `Update.exe` to put [packagePath] in place once this process has
  /// exited, and restart the app. The caller exits right after.
  Future<void> applyAndRestart(String packagePath, {int? waitPid}) => _startDetached(
        install.updateExe,
        velopackApplyArguments(packagePath: packagePath, waitPid: waitPid ?? pid),
      );
}
