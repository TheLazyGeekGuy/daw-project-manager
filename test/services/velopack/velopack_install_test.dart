import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/velopack/velopack_install.dart';
import 'package:daw_project_manager/utils/app_paths.dart';

void main() {
  group('the pack id', () {
    // Velopack deletes %LocalAppData%\<packId> on uninstall. The library and
    // the DAW plugin's bridge live in %LOCALAPPDATA%\<data dir name>, so
    // the two must never name the same folder (Windows ignores case).
    test("is not the app's data folder, so uninstalling never takes the library", () {
      for (final dataDir in [defaultAppDataDirName, '${defaultAppDataDirName}_dev']) {
        expect(kVelopackPackId.toLowerCase(), isNot(dataDir.toLowerCase()));
      }
    });

    test('is the one the release workflow packs the Setup with', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();
      final packed = RegExp(r'vpk pack --packId (\S+)').allMatches(workflow).map((m) => m.group(1)).toSet();
      expect(packed, {kVelopackPackId});
    });
  });

  group('VelopackInstall.of', () {
    const root = r'C:\Users\me\AppData\Local\DAWProjectManager';
    const exe = '$root\\current\\daw_project_manager.exe';

    test('finds the install from an exe in current\\ with Update.exe beside it', () {
      final install = VelopackInstall.of(exe, fileExists: (path) => path == '$root\\Update.exe');

      expect(install, isNotNull);
      expect(install!.rootDir, root);
    });

    test("is not one without Update.exe — a portable folder named 'current'", () {
      expect(VelopackInstall.of(exe, fileExists: (_) => false), isNull);
    });

    test('is not one when the exe runs from any other folder', () {
      const inno = r'C:\Program Files (x86)\DAW Project Manager\daw_project_manager.exe';
      expect(VelopackInstall.of(inno, fileExists: (_) => true), isNull);
    });

    test("takes 'Current' in any case, as Windows does", () {
      final install = VelopackInstall.of(
        '$root\\Current\\daw_project_manager.exe',
        fileExists: (path) => path == '$root\\Update.exe',
      );
      expect(install?.rootDir, root);
    });
  });
}
