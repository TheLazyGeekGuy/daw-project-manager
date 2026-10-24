import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Thrown by an update's download when [UpdateCancelToken.cancel] was called
/// mid-update. Callers should treat this as "the user backed out", not as a
/// failure — the partially downloaded file has already been cleaned up by the
/// time this is thrown.
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();

  @override
  String toString() => 'Update cancelled.';
}

/// Lets a caller ask an in-progress update to stop. One token is good for one
/// update attempt — create a fresh one per attempt.
class UpdateCancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Future that completes the moment [cancel] is called. The download races
  /// this against the network stream so a cancel takes effect immediately
  /// instead of waiting for the current chunk/step to finish.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Decides whether a progress update should actually be delivered, given how
/// much progress has been made and how long it's been since the last
/// delivered update. A download reports once per network chunk — there can
/// be thousands of those for a ~100MB file — and the update dialogs rebuild
/// on every delivered update, so delivering on every single chunk would
/// stall the stream's read loop behind UI work on the same isolate.
/// [lastReported] is null before the first update has been delivered.
bool shouldReportUpdateProgress({
  required double? lastReported,
  required double current,
  required Duration sinceLastReport,
}) {
  if (lastReported == null || current >= 1.0) return true;
  return current - lastReported >= 0.01 || sinceLastReport >= const Duration(milliseconds: 100);
}

/// The lowercase hex SHA-256 of [file], read as a stream so a large update
/// is never held in memory whole.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Streams [url] into [destination], throttling [onProgress] via
/// [shouldReportUpdateProgress] (null progress means the size is unknown).
/// Uses `stream.listen` rather than `await for` so [cancelToken] can
/// interrupt the subscription immediately instead of waiting for the next
/// chunk to arrive. Leaves cleaning up a partial [destination] to the caller,
/// which knows whether the file is its to delete.
Future<void> downloadToFile(
  http.Client client,
  Uri url,
  File destination, {
  void Function(double? progress)? onProgress,
  UpdateCancelToken? cancelToken,
}) async {
  final sink = destination.openWrite();
  try {
    final request = http.Request('GET', url);
    final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
    if (streamedResponse.statusCode != 200) {
      throw StateError('Failed to download update (HTTP ${streamedResponse.statusCode}).');
    }
    final total = streamedResponse.contentLength;
    var received = 0;
    onProgress?.call(total == null ? null : 0);
    double? lastReported = total == null ? null : 0;
    final stopwatch = Stopwatch()..start();

    final completer = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = streamedResponse.stream.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          final progress = received / total;
          if (shouldReportUpdateProgress(
            lastReported: lastReported,
            current: progress,
            sinceLastReport: stopwatch.elapsed,
          )) {
            onProgress?.call(progress);
            lastReported = progress;
            stopwatch.reset();
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      cancelOnError: true,
    );

    unawaited(cancelToken?.whenCancelled.then((_) {
      subscription.cancel();
      if (!completer.isCompleted) completer.completeError(const UpdateCancelledException());
    }));

    await completer.future;
  } finally {
    await sink.close();
  }
}
