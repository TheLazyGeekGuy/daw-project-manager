import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Verifies local media without executing, copying, deleting or modifying it.
/// A stored digest is a baseline: mismatches keep it and record observations.
class ReleaseAssetVerifier {
  ReleaseAssetVerifier({
    this.maxBytes = 16 * 1024 * 1024 * 1024,
    this.timeout = const Duration(minutes: 5),
    DateTime Function()? clock,
    Stream<List<int>> Function(File file)? readChunks,
  }) : _clock = clock ?? DateTime.now,
       _readChunks = readChunks ?? ((file) => file.openRead()) {
    if (maxBytes < 1 || timeout <= Duration.zero) {
      throw ArgumentError('Verification limits must be positive');
    }
  }

  final int maxBytes;
  final Duration timeout;
  final DateTime Function() _clock;
  final Stream<List<int>> Function(File file) _readChunks;

  Future<Map<String, dynamic>> verify(Map<String, dynamic> asset) async {
    final result = Map<String, dynamic>.from(asset);
    final checkedAt = _clock().toUtc().toIso8601String();
    result['checked_at'] = checkedAt;
    Map<String, dynamic> failed(String status, String reason) {
      result['validation'] = status;
      result['verification_error'] = reason;
      return result;
    }

    final path = asset['path'];
    if (path is! String || path.trim().isEmpty) {
      return failed('unverified', 'invalid_path');
    }
    final expected = asset['sha256'];
    if (expected != null &&
        (expected is! String ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected))) {
      return failed('unverified', 'invalid_expected_digest');
    }
    final file = File(path);
    try {
      final kind = await FileSystemEntity.type(path, followLinks: false);
      if (kind == FileSystemEntityType.notFound) {
        return failed('missing', 'file_missing');
      }
      if (kind != FileSystemEntityType.file) {
        return failed('unverified', 'not_a_regular_file');
      }
      final canonical = await file.resolveSymbolicLinks();
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file) {
        return failed('unverified', 'not_a_regular_file');
      }
      if (before.size > maxBytes) return failed('unverified', 'size_limit');
      final measured = await _hash(file);
      final after = await file.stat();
      final finalCanonical = await file.resolveSymbolicLinks();
      result['observed_sha256'] = measured.digest;
      result['observed_bytes'] = measured.bytes;
      if (canonical != finalCanonical ||
          after.type != FileSystemEntityType.file ||
          before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed ||
          measured.bytes != before.size) {
        return failed('changed', 'file_changed_during_verification');
      }
      if (expected is String && expected.toLowerCase() != measured.digest) {
        return failed('changed', 'digest_mismatch');
      }
      if (asset['bytes'] is int && asset['bytes'] != measured.bytes) {
        return failed('changed', 'byte_length_mismatch');
      }
      result.addAll({
        'validation': 'verified',
        'sha256': measured.digest,
        'bytes': measured.bytes,
        'verified_at': checkedAt,
        'resolved_path': canonical,
      });
      result.remove('verification_error');
      return result;
    } on FileSystemException {
      return failed('unverified', 'file_unreadable_or_changed');
    } on TimeoutException {
      return failed('unverified', 'verification_timeout');
    } on _AssetSizeExceeded {
      return failed('unverified', 'size_limit');
    }
  }

  Future<({String digest, int bytes})> _hash(File file) {
    final completed = Completer<({String digest, int bytes})>();
    final output = _DigestSink();
    final hasher = sha256.startChunkedConversion(output);
    var count = 0;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    void fail(Object error, StackTrace stack) {
      if (completed.isCompleted) return;
      subscription?.cancel();
      timer?.cancel();
      completed.completeError(error, stack);
    }

    subscription = _readChunks(file).listen(
      (chunk) {
        if (completed.isCompleted) return;
        try {
          count += chunk.length;
          if (count > maxBytes) throw const _AssetSizeExceeded();
          hasher.add(chunk);
        } catch (error, stack) {
          fail(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) => fail(error, stack),
      onDone: () {
        if (completed.isCompleted) return;
        try {
          hasher.close();
          completed.complete((digest: output.value!.toString(), bytes: count));
        } catch (error, stack) {
          fail(error, stack);
        }
      },
      cancelOnError: true,
    );
    timer = Timer(
      timeout,
      () => fail(
        TimeoutException('Asset verification exceeded its time limit'),
        StackTrace.current,
      ),
    );
    return completed.future.whenComplete(() => timer?.cancel());
  }
}

class _AssetSizeExceeded implements Exception {
  const _AssetSizeExceeded();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}
