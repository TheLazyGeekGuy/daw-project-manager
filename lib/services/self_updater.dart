import 'appimage_update_service.dart';
import 'velopack/velopack_install.dart';
import 'velopack/velopack_update_service.dart';

/// A copy of the app that updates itself: the Linux AppImage, and the
/// Windows installer's (Velopack) copy. [SelfUpdateDialog] drives either.
abstract class SelfUpdater {
  /// Gets [version] ready — downloaded and checked. It takes effect on
  /// [restart]. Throws [UpdateCancelledException] when [cancelToken] stops it.
  Future<void> prepare(
    String version, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  });

  /// Starts the updated app. The caller exits right after.
  Future<void> restart();

  /// What kind of copy failed to update, for a bug report.
  String get reportName;

  void close();
}

class AppImageSelfUpdater implements SelfUpdater {
  final AppImageUpdateService _service = AppImageUpdateService();

  @override
  String get reportName => 'AppImage';

  @override
  Future<void> prepare(
    String version, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    final assets = await _service.fetchReleaseAssets(version);
    if (cancelToken?.isCancelled ?? false) throw const UpdateCancelledException();
    if (assets == null) throw StateError('No AppImage asset found for v$version.');
    await _service.applyUpdate(assets, onProgress: onProgress, cancelToken: cancelToken);
  }

  @override
  Future<void> restart() => _service.relaunch();

  @override
  void close() => _service.close();
}

class VelopackSelfUpdater implements SelfUpdater {
  final VelopackUpdateService _service;
  String? _packagePath;

  VelopackSelfUpdater({required VelopackInstall install, required String currentVersion})
      : _service = VelopackUpdateService(install: install, currentVersion: currentVersion);

  @override
  String get reportName => 'Windows installer';

  @override
  Future<void> prepare(
    String version, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    final update = await _service.fetchUpdate(version);
    if (cancelToken?.isCancelled ?? false) throw const UpdateCancelledException();
    if (update == null) throw StateError('No update package found for v$version.');
    _packagePath = await _service.download(update, onProgress: onProgress, cancelToken: cancelToken);
  }

  @override
  Future<void> restart() async {
    final path = _packagePath;
    if (path == null) throw StateError('No update has been downloaded.');
    await _service.applyAndRestart(path);
  }

  @override
  void close() => _service.close();
}
