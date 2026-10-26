import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_asset_verifier.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('release-asset-');
    file = await File(
      '${directory.path}/master.wav',
    ).writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'streams integrity evidence and preserves unrelated asset fields',
    () async {
      final source = {
        'id': 'master',
        'path': file.path,
        'role': 'master',
        'custom': {'kept': true},
      };
      final result = await ReleaseAssetVerifier(
        clock: () => DateTime.utc(2026, 10, 26),
      ).verify(source);
      expect(result['validation'], 'verified');
      expect(result['sha256'], sha256.convert([1, 2, 3, 4]).toString());
      expect(result['bytes'], 4);
      expect(result['verified_at'], '2026-10-26T00:00:00.000Z');
      expect(result['custom'], source['custom']);
      expect(source.containsKey('sha256'), false);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('a changed file never replaces the known digest baseline', () async {
    final verified = await ReleaseAssetVerifier().verify({
      'id': 'a',
      'path': file.path,
    });
    await file.writeAsBytes([4, 3, 2, 1]);
    final changed = await ReleaseAssetVerifier().verify(verified);
    expect(changed['validation'], 'changed');
    expect(changed['verification_error'], 'digest_mismatch');
    expect(changed['sha256'], verified['sha256']);
    expect(changed['observed_sha256'], sha256.convert([4, 3, 2, 1]).toString());
  });

  test(
    'reports unavailable files and directories without reading them',
    () async {
      final verifier = ReleaseAssetVerifier();
      expect(
        (await verifier.verify({
          'path': '${directory.path}/missing.wav',
        }))['validation'],
        'missing',
      );
      expect(
        (await verifier.verify({'path': directory.path}))['verification_error'],
        'not_a_regular_file',
      );
      expect(
        (await verifier.verify({'path': 3}))['verification_error'],
        'invalid_path',
      );
    },
  );

  test(
    'oversized and invalid expected baselines fail without certifying',
    () async {
      final limited = await ReleaseAssetVerifier(
        maxBytes: 2,
      ).verify({'path': file.path});
      expect(limited['validation'], 'unverified');
      expect(limited['verification_error'], 'size_limit');
      final invalid = await ReleaseAssetVerifier().verify({
        'path': file.path,
        'sha256': 'garbage',
      });
      expect(invalid['verification_error'], 'invalid_expected_digest');
    },
  );

  test('detects source modification during streaming', () async {
    final result = await ReleaseAssetVerifier(
      readChunks: (input) async* {
        yield [1, 2, 3, 4];
        await input.writeAsBytes([1, 2, 3, 4, 5]);
      },
    ).verify({'path': file.path});
    expect(result['validation'], 'changed');
    expect(result['verification_error'], 'file_changed_during_verification');
    expect(result.containsKey('sha256'), false);
  });

  test('total deadline cancels the file stream', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final result = await ReleaseAssetVerifier(
      timeout: const Duration(milliseconds: 30),
      readChunks: (_) => controller.stream,
    ).verify({'path': file.path});
    expect(result['verification_error'], 'verification_timeout');
    expect(result['validation'], 'unverified');
    expect(cancelled, true);
    await controller.close();
  });

  test(
    'symlinks remain unverified',
    () async {
      final link = await Link('${directory.path}/linked.wav').create(file.path);
      final result = await ReleaseAssetVerifier().verify({'path': link.path});
      expect(result['validation'], 'unverified');
      expect(result['verification_error'], 'not_a_regular_file');
    },
    skip: Platform.isWindows
        ? 'Creating links requires Windows developer mode'
        : false,
  );
}
