import 'dart:convert';

import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
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
      final release = parseCompanionRelease(githubRelease([
        'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe',
        'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe.sha256',
        'DAW_Project_Manager_Plugin_Windows_VST3_v0.2.0.zip',
        'DAW_Project_Manager_Plugin_macOS_Installer_v0.2.0.pkg',
        'DAW_Project_Manager_Plugin_macOS_v0.2.0.zip',
        'DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz',
        'DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz.sha256',
      ]))!;

      expect(release.downloads, {
        CompanionPlatform.windows: asset('DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'),
        CompanionPlatform.macOS: asset('DAW_Project_Manager_Plugin_macOS_Installer_v0.2.0.pkg'),
        CompanionPlatform.linux: asset('DAW_Project_Manager_Plugin_Linux_x86_64_v0.2.0.tar.gz'),
      });
    });

    test('a release from before the rename still has its installers found', () {
      final release = parseCompanionRelease(githubRelease([
        'DPM_Companion_Installer_v0.1.0.exe',
        'DPM_Companion_macOS_Installer_v0.1.0.pkg',
        'DPM_Companion_Linux_x86_64_v0.1.0.tar.gz',
      ]))!;
      expect(release.downloads.keys, unorderedEquals(CompanionPlatform.values));
    });

    test('the download button opens the installer, else the release page, else the releases page', () {
      final withWindowsOnly = parseCompanionRelease(githubRelease(['DAW_Project_Manager_Plugin_Installer_v0.2.0.exe']))!;
      expect(companionDownloadUrl(withWindowsOnly, CompanionPlatform.windows),
          asset('DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'));
      expect(companionDownloadUrl(withWindowsOnly, CompanionPlatform.macOS), page);
      expect(companionDownloadUrl(null, CompanionPlatform.linux), companionReleasesPage);
    });

    test('odd asset entries are skipped', () {
      final release = parseCompanionRelease({
        'tag_name': 'v0.2.0',
        'html_url': page,
        'assets': ['not a map', {'name': 'DAW_Project_Manager_Plugin_Installer_v0.2.0.exe'}, 42],
      })!;
      expect(release.downloads, isEmpty);
    });
  });

  test('versions compare by number', () {
    expect(isNewerCompanionVersion('0.2.0', '0.1.0'), isTrue);
    expect(isNewerCompanionVersion('0.10.0', '0.9.9'), isTrue);
    expect(isNewerCompanionVersion('v1.0.0', '0.99.0'), isTrue);
    expect(isNewerCompanionVersion('0.1.0', '0.1.0'), isFalse);
    expect(isNewerCompanionVersion('0.1.0', '0.2.0'), isFalse);
    expect(isNewerCompanionVersion('nightly', '0.1.0'), isFalse);
    expect(isNewerCompanionVersion('0.2.0', ''), isFalse);
  });

  group('sightings', () {
    final at = DateTime(2026, 10, 19, 12, 51);

    test('survive a round trip through the settings box', () {
      final s = CompanionSighting('0.1.0', 'Steinberg Cubase 13', at);
      final back = CompanionSighting.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect(back.version, '0.1.0');
      expect(back.hostName, 'Steinberg Cubase 13');
      expect(back.at, at);
      expect(back.at.isUtc, isFalse);
      expect(CompanionSighting.fromJson({'host': 'x'}), isNull);
      expect(CompanionSighting.fromJson('garbage'), isNull);
    });

    test('are news on a change of version or host, or a minute later — not every heartbeat', () {
      final seen = CompanionSighting('0.1.0', 'Cubase', at);
      expect(CompanionSighting('0.1.0', 'Cubase', at.add(const Duration(seconds: 10))).isNewsAfter(seen), isFalse);
      expect(CompanionSighting('0.1.0', 'Cubase', at.add(const Duration(minutes: 1))).isNewsAfter(seen), isTrue);
      expect(CompanionSighting('0.2.0', 'Cubase', at).isNewsAfter(seen), isTrue);
      expect(CompanionSighting('0.1.0', 'REAPER', at).isNewsAfter(seen), isTrue);
      expect(seen.isNewsAfter(null), isTrue);
    });

    test('hello and heartbeat carry the plugin\'s version', () {
      final hello = parseCompanionMessage(jsonEncode({
        'id': 'm',
        'type': 'session.hello',
        'createdAt': '2026-10-19T10:51:00.000Z',
        'plugin': {'version': '0.1.0', 'runId': 'r'},
        'project': {'id': 'p1', 'profileId': 'solo'},
      }))!;
      expect(hello.pluginVersion, '0.1.0');

      final beat = parseCompanionHeartbeat(jsonEncode({
        'runId': 'r',
        'pluginVersion': '0.1.0',
        'lastSeen': '2026-10-19T10:51:00.000Z',
        'project': {'id': 'p1', 'profileId': 'solo'},
      }))!;
      expect(beat.pluginVersion, '0.1.0');
    });
  });
}
