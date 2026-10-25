import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/services/update_download.dart';
import 'package:daw_project_manager/services/velopack/velopack_feed.dart';
import 'package:daw_project_manager/services/velopack/velopack_install.dart';
import 'package:daw_project_manager/services/velopack/velopack_update_service.dart';

class _FakeClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) handler;
  _FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}

VelopackAsset package(String version, List<int> bytes) => VelopackAsset(
      packageId: kVelopackPackId,
      version: version,
      type: VelopackAssetType.full,
      fileName: '$kVelopackPackId-$version-full.nupkg',
      sha256: sha256.convert(bytes).toString().toUpperCase(),
      size: bytes.length,
    );

Map<String, dynamic> releaseAsset(String name) =>
    {'name': name, 'browser_download_url': 'https://github.com/o/r/releases/download/v2.10.0/$name'};

void main() {
  group('VelopackUpdateService.updateFrom', () {
    test("takes the newest full package, from this release's assets", () {
      final feed = [package('2.9.3', [1]), package('2.10.0', [2])];
      final update = VelopackUpdateService.updateFrom(
        [releaseAsset(kVelopackFeedAsset), releaseAsset('$kVelopackPackId-2.10.0-full.nupkg')],
        feed,
        currentVersion: '2.9.3',
      );

      expect(update?.package.version, '2.10.0');
      expect(update?.packageUrl.path, endsWith('/$kVelopackPackId-2.10.0-full.nupkg'));
    });

    test("nothing when the package isn't attached to the release", () {
      final update = VelopackUpdateService.updateFrom(
        [releaseAsset(kVelopackFeedAsset)],
        [package('2.10.0', [2])],
        currentVersion: '2.9.3',
      );
      expect(update, isNull);
    });
  });

  group('VelopackUpdateService.download', () {
    late Directory root;
    late VelopackInstall install;

    setUp(() {
      root = Directory.systemTemp.createTempSync('velopack_update_test_');
      install = VelopackInstall(root.path);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    VelopackUpdate updateOf(List<int> bytes) => VelopackUpdate(
          package: package('2.10.0', bytes),
          packageUrl: Uri.parse('https://example.com/pkg.nupkg'),
        );

    test('puts the package in packages\\ once its hash matches the feed', () async {
      final bytes = utf8.encode('a full package');
      final service = VelopackUpdateService(
        install: install,
        currentVersion: '2.9.3',
        client: _FakeClient((_) async => http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length)),
      );

      final path = await service.download(updateOf(bytes));

      expect(path, p.join(install.packagesDir, '$kVelopackPackId-2.10.0-full.nupkg'));
      expect(await File(path).readAsBytes(), bytes);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('leaves nothing behind when the download does not match the feed', () async {
      final service = VelopackUpdateService(
        install: install,
        currentVersion: '2.9.3',
        client: _FakeClient((_) async => http.StreamedResponse(Stream.value(utf8.encode('tampered')), 200)),
      );
      final update = updateOf(utf8.encode('the real package'));

      await expectLater(service.download(update), throwsA(isA<StateError>()));
      expect(File(service.packagePath(update)).existsSync(), isFalse);
      expect(File('${service.packagePath(update)}.part').existsSync(), isFalse);
    });

    test('a cancelled download leaves nothing behind', () async {
      final controller = StreamController<List<int>>();
      final requested = Completer<void>();
      final service = VelopackUpdateService(
        install: install,
        currentVersion: '2.9.3',
        client: _FakeClient((_) async {
          requested.complete();
          return http.StreamedResponse(controller.stream, 200, contentLength: 100);
        }),
      );
      final update = updateOf(List.filled(100, 1));
      final cancel = UpdateCancelToken();

      final future = service.download(update, cancelToken: cancel);
      await requested.future;
      controller.add(List.filled(10, 1)); // a chunk arrives before the cancel
      cancel.cancel();

      await expectLater(future, throwsA(isA<UpdateCancelledException>()));
      expect(File('${service.packagePath(update)}.part').existsSync(), isFalse);
      unawaited(controller.close());
    });

    test('a package already downloaded and intact is not downloaded again', () async {
      final bytes = utf8.encode('already here');
      var requests = 0;
      final service = VelopackUpdateService(
        install: install,
        currentVersion: '2.9.3',
        client: _FakeClient((_) async {
          requests++;
          return http.StreamedResponse(Stream.value(bytes), 200);
        }),
      );
      final update = updateOf(bytes);
      File(service.packagePath(update))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await service.download(update);

      expect(requests, 0);
    });
  });

  test("applying hands the package to the install's Update.exe", () async {
    final started = <(String, List<String>)>[];
    final install = VelopackInstall(p.join('root'));
    final service = VelopackUpdateService(
      install: install,
      currentVersion: '2.9.3',
      startDetached: (exe, args) async => started.add((exe, args)),
    );

    await service.applyAndRestart('pkg.nupkg', waitPid: 7);

    expect(started, hasLength(1));
    expect(started.single.$1, install.updateExe);
    expect(started.single.$2, ['apply', '--package', 'pkg.nupkg', '--waitPid', '7']);
  });
}
