import 'dart:io';

import 'package:daw_project_manager/services/plugin_bridge/plugin_install_scan.dart';
import 'package:daw_project_manager/services/plugin_bridge/plugin_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// moduleinfo.json exactly as JUCE writes it into the plugin's VST3 bundle —
/// trailing commas and all.
final realModuleInfo = File('test/fixtures/plugin/moduleinfo.json').readAsStringSync();

const plist = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key>
  <string>com.bandpassrecords.dpm.plugin</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
</dict></plist>''';

void main() {
  group('where to look', () {
    test('Windows: all users, just me, and the folder the installer recorded', () {
      final folders = standardDpmPluginFolders(
        platform: DpmPluginPlatform.windows,
        home: r'C:\Users\ana',
        localAppData: r'C:\Users\ana\AppData\Local',
        commonProgramFiles: r'C:\Program Files\Common Files',
        installerFolder: r'D:\Audio\Plugins',
        pathContext: p.Context(style: p.Style.windows),
      );
      expect(folders.map((f) => f.folder), [
        r'C:\Program Files\Common Files\VST3',
        r'C:\Users\ana\AppData\Local\Programs\Common\VST3',
        r'D:\Audio\Plugins',
      ]);
      expect(folders.every((f) => f.format == DpmPluginFormat.vst3), isTrue);
    });

    test('macOS: VST3 and AU, for all users and just me', () {
      final folders = standardDpmPluginFolders(
        platform: DpmPluginPlatform.macOS,
        home: '/Users/ana',
        pathContext: p.Context(style: p.Style.posix),
      );
      expect(folders.map((f) => '${f.format.name}:${f.folder}'), [
        'vst3:/Library/Audio/Plug-Ins/VST3',
        'vst3:/Users/ana/Library/Audio/Plug-Ins/VST3',
        'au:/Library/Audio/Plug-Ins/Components',
        'au:/Users/ana/Library/Audio/Plug-Ins/Components',
      ]);
    });

    test('Linux: ~/.vst3 and the system folders', () {
      final folders = standardDpmPluginFolders(
        platform: DpmPluginPlatform.linux,
        home: '/home/ana',
        pathContext: p.Context(style: p.Style.posix),
      );
      expect(folders.map((f) => f.folder), ['/home/ana/.vst3', '/usr/local/lib/vst3', '/usr/lib/vst3']);
    });
  });

  group('reading a copy\'s version, without loading it', () {
    test('from the moduleinfo.json JUCE writes, trailing commas and all', () {
      expect(dpmPluginVersionFromModuleInfo(realModuleInfo), '0.1.0');
    });

    test('another vendor\'s or another plugin\'s bundle is not ours', () {
      expect(dpmPluginVersionFromModuleInfo(realModuleInfo.replaceFirst('BandPass Records', 'Someone Else')), isNull);
      expect(dpmPluginVersionFromModuleInfo(realModuleInfo.replaceFirst('"Name": "DAW Project Manager"', '"Name": "Other"')), isNull);
      expect(dpmPluginVersionFromModuleInfo('not json'), isNull);
    });

    test('from a macOS Info.plist', () {
      expect(dpmPluginVersionFromInfoPlist(plist), '0.1.0');
      expect(dpmPluginVersionFromInfoPlist(plist.replaceFirst('com.bandpassrecords.dpm.plugin', 'com.other.plugin')), isNull);
    });

    test('the Windows installer\'s recorded folder, from reg query', () {
      const output = '\r\nHKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{6E2C9B0A-4C1E-4D8B-9B2F-3A7E5C1D8F42}_is1\r\n'
          r'    InstallLocation    REG_SZ    C:\Program Files\Common Files\VST3\'
          '\r\n\r\n';
      expect(parseRegQueryInstallLocation(output), r'C:\Program Files\Common Files\VST3');
      expect(parseRegQueryInstallLocation('ERROR: The system was unable to find the specified registry key or value.'), isNull);
    });
  });

  group('searching the disk', () {
    late Directory tmp;

    setUp(() async => tmp = await Directory.systemTemp.createTemp('plugin_scan_test'));
    tearDown(() async => tmp.delete(recursive: true));

    Future<String> installAt(String folderName, {String version = '0.1.0', String vendor = 'BandPass Records'}) async {
      final folder = p.join(tmp.path, folderName);
      final info = File(p.join(folder, dpmPluginVst3BundleName, 'Contents', 'Resources', 'moduleinfo.json'));
      await info.parent.create(recursive: true);
      await info.writeAsString(
          realModuleInfo.replaceAll('"Version": "0.1.0"', '"Version": "$version"').replaceFirst('BandPass Records', vendor));
      return folder;
    }

    ({String folder, DpmPluginFormat format}) vst3(String folder) =>
        (folder: folder, format: DpmPluginFormat.vst3);

    test('finds each copy with its version; missing folders and foreign bundles are skipped', () async {
      final allUsers = await installAt('all users', version: '0.1.0');
      final justMe = await installAt('just me', version: '0.2.0');
      final foreign = await installAt('foreign', vendor: 'Someone Else');

      final found = await scanDpmPluginFolders([vst3(allUsers), vst3(justMe), vst3(foreign), vst3(p.join(tmp.path, 'none'))]);
      expect(found.map((i) => i.version), ['0.1.0', '0.2.0']);
      expect(found.first.path, p.join(allUsers, dpmPluginVst3BundleName));
      expect(hasDuplicateDpmPluginInstalls(found), isTrue);
      expect(newestInstalledDpmPluginVersion(found), '0.2.0');
    });

    test('one folder listed twice is one copy', () async {
      final folder = await installAt('vst3');
      final found = await scanDpmPluginFolders([vst3(folder), vst3(folder)]);
      expect(found, hasLength(1));
      expect(hasDuplicateDpmPluginInstalls(found), isFalse);
    });

    test('the user\'s own folders are searched only when the standard ones have no copy', () async {
      final standard = await installAt('standard');
      final custom = await installAt('custom', version: '0.3.0');
      final empty = p.join(tmp.path, 'empty standard');

      final withStandard = await findDpmPluginInstalls(
          standard: [vst3(standard)], customFolders: [custom], platform: DpmPluginPlatform.windows);
      expect(withStandard.map((i) => i.version), ['0.1.0']);
      expect(withStandard.single.inCustomFolder, isFalse);

      final withoutStandard = await findDpmPluginInstalls(
          standard: [vst3(empty)], customFolders: [custom], platform: DpmPluginPlatform.windows);
      expect(withoutStandard.single.version, '0.3.0');
      expect(withoutStandard.single.inCustomFolder, isTrue);
    });
  });
}
