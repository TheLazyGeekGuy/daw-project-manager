import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/auto_start/auto_start_backend.dart';
import 'package:daw_project_manager/services/auto_start/auto_start_rules.dart';

/// The pure halves of each launch-at-login backend: what gets written, how
/// it is read back, and when a registration counts as stale. The backends
/// themselves only add the registry / file / process calls around these.
void main() {
  group('classifyRegistration', () {
    AutoStartStatus classify({
      bool present = true,
      bool disabledByUser = false,
      bool matchesExpected = false,
      bool pointsAtThisApp = false,
      bool targetExists = true,
    }) =>
        classifyRegistration(
          present: present,
          disabledByUser: disabledByUser,
          matchesExpected: matchesExpected,
          pointsAtThisApp: pointsAtThisApp,
          targetExists: targetExists,
        );

    test('nothing registered is off', () {
      expect(classify(present: false), AutoStartStatus.off);
    });

    test('switched off by the user in the OS is off, whatever it points at',
        () {
      expect(
        classify(disabledByUser: true, matchesExpected: true),
        AutoStartStatus.off,
      );
      expect(
        classify(disabledByUser: true, pointsAtThisApp: true),
        AutoStartStatus.off,
      );
      expect(
        classify(disabledByUser: true, targetExists: false),
        AutoStartStatus.off,
      );
    });

    test('exactly what would be written now is on', () {
      expect(classify(matchesExpected: true), AutoStartStatus.on);
    });

    test('this app with the wrong form or flag is stale', () {
      expect(classify(pointsAtThisApp: true), AutoStartStatus.stale);
    });

    test('pointing at something gone is stale', () {
      // The Store update deleted the versioned folder; the app was moved.
      expect(classify(targetExists: false), AutoStartStatus.stale);
    });

    test("another install's existing registration is left alone", () {
      // A dev build must not rewrite the release build's entry to itself.
      expect(classify(), AutoStartStatus.off);
    });
  });

  group('Windows Run key', () {
    test('an exe without spaces is written unquoted, as earlier builds did',
        () {
      expect(
        windowsRunCommand(r'C:\Apps\dpm.exe', minimized: false),
        r'C:\Apps\dpm.exe',
      );
      expect(
        windowsRunCommand(r'C:\Apps\dpm.exe', minimized: true),
        r'C:\Apps\dpm.exe --minimized',
      );
    });

    test('an exe with spaces is quoted so the flag stays separate', () {
      const exe = r'C:\Program Files\DAW Project Manager\daw_project_manager.exe';
      expect(windowsRunCommand(exe, minimized: false), '"$exe"');
      expect(windowsRunCommand(exe, minimized: true), '"$exe" --minimized');
    });

    test('reads the executable back out of what it wrote', () {
      for (final exe in const [
        r'C:\Apps\dpm.exe',
        r'C:\Program Files\DAW Project Manager\daw_project_manager.exe',
      ]) {
        for (final minimized in const [false, true]) {
          expect(
            windowsRunCommandExecutable(
                windowsRunCommand(exe, minimized: minimized)),
            exe,
          );
        }
      }
    });

    test('an unterminated quote has no executable', () {
      expect(windowsRunCommandExecutable(r'"C:\Program Files\x.exe'), isNull);
    });

    test('paths compare case-insensitively', () {
      expect(windowsPathsEqual(r'C:\Apps\DPM.exe', r'c:\apps\dpm.EXE'), isTrue);
      expect(windowsPathsEqual(r'C:\Apps\a.exe', r'C:\Apps\b.exe'), isFalse);
    });

    test('the flag is found only as a whole argument', () {
      expect(argumentsCarryFlag('--minimized', kStartMinimizedFlag), isTrue);
      expect(argumentsCarryFlag('-x  --minimized', kStartMinimizedFlag), isTrue);
      expect(argumentsCarryFlag('', kStartMinimizedFlag), isFalse);
      expect(argumentsCarryFlag('--minimized-ish', kStartMinimizedFlag), isFalse);
    });

    test("StartupApproved: an odd first byte is the user's switch-off", () {
      expect(startupApprovalDisables(null), isFalse);
      expect(startupApprovalDisables(Uint8List(0)), isFalse);
      expect(startupApprovalDisables(Uint8List(12)..[0] = 2), isFalse);
      expect(startupApprovalDisables(Uint8List(12)..[0] = 6), isFalse);
      expect(startupApprovalDisables(Uint8List(12)..[0] = 3), isTrue);
      expect(startupApprovalDisables(Uint8List(12)..[0] = 1), isTrue);
    });
  });

  group('Windows MSIX shortcut', () {
    test('targets the execution alias, which has no version in its path', () {
      final alias = msixAliasPath(r'C:\Users\me\AppData\Local');
      expect(
        alias,
        r'C:\Users\me\AppData\Local\Microsoft\WindowsApps\dawprojectmanager.exe',
      );
      // Regression guard: the exe's own folder carries the package version
      // (…DAWProjectManager_2.9.3.0_x64__…) and every Store update deletes
      // it, which killed auto-start after each update.
      expect(alias, isNot(contains('_x64__')));
    });

    test('has no alias without LOCALAPPDATA', () {
      expect(msixAliasPath(null), isNull);
      expect(msixAliasPath(''), isNull);
    });

    test('lives in the Startup folder under the stable name', () {
      expect(
        startupShortcutPath(r'C:\Users\me\AppData\Roaming'),
        r'C:\Users\me\AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
        r'\Startup\DAW Project Manager.lnk',
      );
    });

    test('PowerShell literals expand nothing and survive a quote', () {
      expect(powerShellQuote("O'Brien"), "'O''Brien'");
      expect(powerShellQuote(r'$env:APPDATA'), r"'$env:APPDATA'");
    });

    test('the script sets target and arguments as literals', () {
      final script = startupShortcutScript(
        shortcutPath: r"C:\Users\O'Brien\Startup\DAW Project Manager.lnk",
        target: r'C:\Users\me\WindowsApps\dawprojectmanager.exe',
        arguments: '--minimized',
      );
      expect(
        script,
        contains(r"CreateShortcut('C:\Users\O''Brien\Startup\DAW Project Manager.lnk')"),
      );
      expect(
        script,
        contains(r"$s.TargetPath = 'C:\Users\me\WindowsApps\dawprojectmanager.exe'"),
      );
      expect(script, contains(r"$s.Arguments = '--minimized'"));
      expect(script, endsWith(r'$s.Save()'));
    });
  });

  group('Linux autostart', () {
    test('goes in XDG_CONFIG_HOME, or ~/.config without it', () {
      expect(
        autostartDirectory({'XDG_CONFIG_HOME': '/cfg', 'HOME': '/home/me'}),
        '/cfg/autostart',
      );
      expect(
        autostartDirectory({'HOME': '/home/me'}),
        '/home/me/.config/autostart',
      );
      // The XDG spec says to ignore a relative value.
      expect(
        autostartDirectory({'XDG_CONFIG_HOME': 'cfg', 'HOME': '/home/me'}),
        '/home/me/.config/autostart',
      );
      expect(autostartDirectory({}), isNull);
    });

    test("an AppImage registers the image file, not its temporary mount", () {
      // Regression guard: the mount under /tmp is gone after a reboot, so
      // registering it meant auto-start never worked for AppImage users.
      expect(
        linuxLaunchExecutable(
          {'APPIMAGE': '/home/me/Apps/DAW Project Manager.AppImage'},
          '/tmp/.mount_DAWPrxyz/daw_project_manager',
        ),
        '/home/me/Apps/DAW Project Manager.AppImage',
      );
      expect(
        linuxLaunchExecutable({}, '/opt/dpm/daw_project_manager'),
        '/opt/dpm/daw_project_manager',
      );
      expect(
        linuxLaunchExecutable({'APPIMAGE': ''}, '/opt/dpm/daw_project_manager'),
        '/opt/dpm/daw_project_manager',
      );
    });

    test('a plain path is written as is', () {
      expect(
        desktopExecLine(['/opt/dpm/daw_project_manager', kStartMinimizedFlag]),
        '/opt/dpm/daw_project_manager --minimized',
      );
    });

    test('a path with spaces is quoted', () {
      // Regression guard: written unquoted, the desktop ran "/home/me/My".
      expect(
        desktopExecLine(['/home/me/My Apps/dpm.AppImage']),
        '"/home/me/My Apps/dpm.AppImage"',
      );
    });

    test('reserved characters are escaped and % doubled', () {
      expect(desktopExecLine([r'/a/$b']), r'"/a/\\$b"');
      expect(desktopExecLine(['/a/100%']), '/a/100%%');
      expect(desktopExecLine([r'/a/b"c']), r'"/a/b\\"c"');
    });

    test('everything written parses back to the same arguments', () {
      for (final argv in const [
        ['/opt/dpm/daw_project_manager'],
        ['/home/me/My Apps/dpm.AppImage', '--minimized'],
        [r'/odd/$dir/`x`/"q"/back\slash/100%/dpm'],
        ["/it's/here/dpm", '--minimized'],
      ]) {
        expect(parseDesktopExec(desktopExecLine(argv)), argv);
      }
    });

    test('an unquoted line from an earlier build splits on spaces', () {
      // What the desktop itself would have run — so the first word is the
      // (missing) executable and the registration reads as stale.
      expect(
        parseDesktopExec('/home/me/My Apps/dpm --minimized'),
        ['/home/me/My', 'Apps/dpm', '--minimized'],
      );
    });

    test('the entry written is read back', () {
      final argv = ['/home/me/My Apps/dpm.AppImage', '--minimized'];
      final facts = readAutostartEntry(autostartDesktopEntry(argv));
      expect(facts.exec, desktopExecLine(argv));
      expect(facts.disabled, isFalse);
    });

    test("the desktop's own switch-off is recognised", () {
      expect(
        readAutostartEntry('[Desktop Entry]\nExec=x\nHidden=true\n').disabled,
        isTrue,
      );
      expect(
        readAutostartEntry(
          '[Desktop Entry]\nExec=x\nX-GNOME-Autostart-enabled=false\n',
        ).disabled,
        isTrue,
      );
      expect(
        readAutostartEntry(
          '[Desktop Entry]\nExec=x\nX-GNOME-Autostart-enabled=true\n',
        ).disabled,
        isFalse,
      );
    });

    test('only the [Desktop Entry] group counts', () {
      final facts = readAutostartEntry(
        '[Desktop Entry]\nExec=/right\n\n[Desktop Action other]\nExec=/wrong\nHidden=true\n',
      );
      expect(facts.exec, '/right');
      expect(facts.disabled, isFalse);
    });
  });
}
