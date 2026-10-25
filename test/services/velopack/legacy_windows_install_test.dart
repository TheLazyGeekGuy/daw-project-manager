import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/velopack/legacy_windows_install.dart';

void main() {
  const uninstaller = r'C:\Program Files (x86)\DAW Project Manager\unins000.exe';

  group('LegacyWindowsInstall.fromValues', () {
    test("reads Inno's quoted uninstall command", () {
      final install = LegacyWindowsInstall.fromValues(
        {
          'UninstallString': '"$uninstaller"',
          'InstallLocation': r'C:\Program Files (x86)\DAW Project Manager\',
          'DisplayVersion': '2.9.3',
        },
        fileExists: (path) => path == uninstaller,
      );

      expect(install?.uninstaller, uninstaller);
      expect(install?.installLocation, r'C:\Program Files (x86)\DAW Project Manager\');
      expect(install?.version, '2.9.3');
    });

    test('reads an unquoted command, arguments left off', () {
      final install = LegacyWindowsInstall.fromValues(
        {'UninstallString': r'C:\Apps\DPM\unins000.exe /LOG'},
        fileExists: (path) => path == r'C:\Apps\DPM\unins000.exe',
      );
      expect(install?.uninstaller, r'C:\Apps\DPM\unins000.exe');
    });

    test('is nothing when the uninstaller is gone — nothing is left to remove', () {
      expect(
        LegacyWindowsInstall.fromValues({'UninstallString': '"$uninstaller"'}, fileExists: (_) => false),
        isNull,
      );
    });

    test('is nothing without an uninstall command', () {
      expect(LegacyWindowsInstall.fromValues({'UninstallString': '  '}, fileExists: (_) => true), isNull);
      expect(LegacyWindowsInstall.fromValues({}, fileExists: (_) => true), isNull);
    });

    test('blank optional values read as absent', () {
      final install = LegacyWindowsInstall.fromValues(
        {'UninstallString': '"$uninstaller"', 'InstallLocation': '', 'DisplayVersion': ' '},
        fileExists: (_) => true,
      );
      expect(install?.installLocation, isNull);
      expect(install?.version, isNull);
    });
  });

  test('removes it silently, never restarting the computer', () {
    expect(LegacyWindowsInstall.uninstallArguments, containsAll(['/SILENT', '/NORESTART']));
  });

  test('looks for the uninstall entry Inno wrote under the app name', () {
    expect(kLegacyUninstallKey, endsWith(r'\Uninstall\DAW Project Manager_is1'));
  });
}
