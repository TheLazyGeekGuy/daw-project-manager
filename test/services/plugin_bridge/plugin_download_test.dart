import 'dart:convert';

import 'package:daw_project_manager/services/plugin_bridge/plugin_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const page = 'https://github.com/bandpassrecords/daw-project-manager-plugin/releases/tag/v0.2.0';
  String asset(String name) => 'https://github.com/bandpassrecords/daw-project-manager-plugin/releases/download/v0.2.0/$name';

  Map<String, dynamic> githubRelease(List<String> assetNames) => {
        'tag_name': 'v0.2.0',
        'html_url': page,
        'assets': [
          for (final n in assetNames) {'name': n, 'browser_download_url': asset(n)},
        ],
      };

  group('the release\'s installers', () {
    test('each platform gets its installer, never a checksum or a zip', () {
      final release = parseDpmPluginRelease(githubRelease([
        'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe',
        'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe.sha256',
        'DAW_Project_Manager_Plugin_Windows_VST3_v0.2.0.zip',
        'DAW_Project_Manager_Plugin_macOS_Installer_v0.2.0.pkg',
        'DAW_Project_Manager_Plugin_macOS_v0.2.0.zip',
        'DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz',
        'DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz.sha256',
      ]))!;

      expect(release.downloads, {
        DpmPluginPlatform.windows: asset('DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'),
        DpmPluginPlatform.macOS: asset('DAW_Project_Manager_Plugin_macOS_Installer_v0.2.0.pkg'),
        DpmPluginPlatform.linux: asset('DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz'),
      });
    });


    test('the download button opens the installer, else the release page, else the releases page', () {
      final withWindowsOnly = parseDpmPluginRelease(githubRelease(['DAW_Project_Manager_Plugin_Installer_v0.2.0.exe']))!;
      expect(dpmPluginDownloadUrl(withWindowsOnly, DpmPluginPlatform.windows),
          asset('DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'));
      expect(dpmPluginDownloadUrl(withWindowsOnly, DpmPluginPlatform.macOS), page);
      expect(dpmPluginDownloadUrl(null, DpmPluginPlatform.linux), dpmPluginReleasesPage);
    });

    test('odd asset entries are skipped', () {
      final release = parseDpmPluginRelease({
        'tag_name': 'v0.2.0',
        'html_url': page,
        'assets': ['not a map', {'name': 'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'}, 42],
      })!;
      expect(release.downloads, isEmpty);
    });
  });

  test('versions compare by number', () {
    expect(isNewerDpmPluginVersion('0.2.0', '0.1.0'), isTrue);
    expect(isNewerDpmPluginVersion('0.10.0', '0.9.9'), isTrue);
    expect(isNewerDpmPluginVersion('v1.0.0', '0.99.0'), isTrue);
    expect(isNewerDpmPluginVersion('0.1.0', '0.1.0'), isFalse);
    expect(isNewerDpmPluginVersion('0.1.0', '0.2.0'), isFalse);
    expect(isNewerDpmPluginVersion('nightly', '0.1.0'), isFalse);
    expect(isNewerDpmPluginVersion('0.2.0', ''), isFalse);
  });

  group('sightings', () {
    final at = DateTime(2026, 10, 19, 12, 51);

    test('survive a round trip through the settings box', () {
      final s = DpmPluginSighting('0.1.0', 'Steinberg Cubase 13', at);
      final back = DpmPluginSighting.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.version, '0.1.0');
      expect(back.hostName, 'Steinberg Cubase 13');
      expect(back.at, at);
      expect(back.at.isUtc, isFalse);
      expect(DpmPluginSighting.fromJson({'host': 'x'}), isNull);
      expect(DpmPluginSighting.fromJson('garbage'), isNull);
    });

    test('are news on a change of version or host, or a minute later — not every heartbeat', () {
      final seen = DpmPluginSighting('0.1.0', 'Cubase', at);
      expect(DpmPluginSighting('0.1.0', 'Cubase', at.add(const Duration(seconds: 10))).isNewsAfter(seen), isFalse);
      expect(DpmPluginSighting('0.1.0', 'Cubase', at.add(const Duration(minutes: 1))).isNewsAfter(seen), isTrue);
      expect(DpmPluginSighting('0.2.0', 'Cubase', at).isNewsAfter(seen), isTrue);
      expect(DpmPluginSighting('0.1.0', 'REAPER', at).isNewsAfter(seen), isTrue);
      expect(seen.isNewsAfter(null), isTrue);
    });

    test('hello and heartbeat carry the plugin\'s version', () {
      final hello = parseDpmPluginMessage(jsonEncode({
        'id': 'm',
        'type': 'session.hello',
        'createdAt': '2026-10-19T10:51:00.000Z',
        'plugin': {'version': '0.1.0', 'runId': 'r'},
        'project': {'id': 'p1', 'profileId': 'solo'},
      }))!;
      expect(hello.pluginVersion, '0.1.0');

      final beat = parseDpmPluginHeartbeat(jsonEncode({
        'runId': 'r',
        'pluginVersion': '0.1.0',
        'lastSeen': '2026-10-19T10:51:00.000Z',
        'project': {'id': 'p1', 'profileId': 'solo'},
      }))!;
      expect(beat.pluginVersion, '0.1.0');
    });
  });
}
