import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/velopack/velopack_feed.dart';

/// Shaped like a real `releases.win.json` written by `vpk pack`.
String feedJson(List<Map<String, Object?>> assets) => jsonEncode({'Assets': assets});

Map<String, Object?> entry(
  String version, {
  String type = 'Full',
  String packageId = 'DAWProjectManager',
}) =>
    {
      'PackageId': packageId,
      'Version': version,
      'Type': type,
      'FileName': '$packageId-$version-${type.toLowerCase()}.nupkg',
      'SHA1': '87EACFD8F673AECB5E5927E86A5C81ADB97E3749',
      'SHA256': 'D093559F6BE25B97E4B3756FCA8903F887C96673113E045A8695D96B8C3FDFAC',
      'Size': 39445059,
    };

void main() {
  group('parseVelopackFeed', () {
    test('reads every package with its type, file and hash', () {
      final feed = parseVelopackFeed(feedJson([entry('2.10.0'), entry('2.10.0', type: 'Delta')]));

      expect(feed, hasLength(2));
      expect(feed[0].packageId, 'DAWProjectManager');
      expect(feed[0].version, '2.10.0');
      expect(feed[0].type, VelopackAssetType.full);
      expect(feed[0].fileName, 'DAWProjectManager-2.10.0-full.nupkg');
      expect(feed[0].sha256, 'D093559F6BE25B97E4B3756FCA8903F887C96673113E045A8695D96B8C3FDFAC');
      expect(feed[0].size, 39445059);
      expect(feed[1].type, VelopackAssetType.delta);
    });

    test('reads the type written as a number too', () {
      final feed = parseVelopackFeed(feedJson([
        {...entry('1.0.0'), 'Type': 1},
        {...entry('1.0.0'), 'Type': 2},
      ]));
      expect(feed.map((a) => a.type), [VelopackAssetType.full, VelopackAssetType.delta]);
    });

    test('skips an entry missing what it needs, keeps the rest', () {
      final feed = parseVelopackFeed(feedJson([
        {...entry('1.0.0'), 'SHA256': null},
        entry('1.0.1'),
      ]));
      expect(feed.map((a) => a.version), ['1.0.1']);
    });

    test('refuses something that is not a feed', () {
      expect(() => parseVelopackFeed('{"tag_name": "v1"}'), throwsFormatException);
      expect(() => parseVelopackFeed('[]'), throwsFormatException);
    });
  });

  group('fullPackageToInstall', () {
    List<VelopackAsset> feed(List<Map<String, Object?>> entries) => parseVelopackFeed(feedJson(entries));

    test('picks the newest full package newer than this version', () {
      final pick = fullPackageToInstall(
        feed([entry('2.9.3'), entry('2.10.1'), entry('2.10.0')]),
        packageId: 'DAWProjectManager',
        currentVersion: '2.9.3',
      );
      expect(pick?.version, '2.10.1');
    });

    test('never a delta: it needs the package before it applied first', () {
      final pick = fullPackageToInstall(
        feed([entry('2.10.0', type: 'Delta')]),
        packageId: 'DAWProjectManager',
        currentVersion: '2.9.3',
      );
      expect(pick, isNull);
    });

    test('nothing when this version is the newest', () {
      final pick = fullPackageToInstall(
        feed([entry('2.9.2'), entry('2.9.3')]),
        packageId: 'DAWProjectManager',
        currentVersion: '2.9.3',
      );
      expect(pick, isNull);
    });

    test("ignores another app's packages", () {
      final pick = fullPackageToInstall(
        feed([entry('9.0.0', packageId: 'SomethingElse')]),
        packageId: 'DAWProjectManager',
        currentVersion: '2.9.3',
      );
      expect(pick, isNull);
    });
  });

  test("Update.exe is asked to wait for this process, then swap and restart", () {
    expect(
      velopackApplyArguments(packagePath: r'C:\x\packages\a-full.nupkg', waitPid: 42),
      ['apply', '--package', r'C:\x\packages\a-full.nupkg', '--waitPid', '42'],
    );
  });
}
