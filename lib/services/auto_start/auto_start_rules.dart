import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'auto_start_backend.dart';

/// The registration's name everywhere: the Run registry value, the Startup
/// folder shortcut, the autostart `.desktop` file. It must stay stable across
/// releases — changing it would orphan the old entry and leave the app
/// registered twice.
const String kAutoStartAppName = 'DAW Project Manager';

/// The MSIX package's execution alias, without `.exe`. Must stay in sync with
/// pubspec.yaml → msix_config.execution_alias.
///
/// The Store build's Startup shortcut points here rather than at the exe:
/// the exe lives in a folder named after the package *version*, which every
/// update deletes, while the alias in `%LOCALAPPDATA%\Microsoft\WindowsApps`
/// keeps its path across updates and still passes arguments through.
const String kMsixExecutionAlias = 'dawprojectmanager';

/// The command the Flatpak runs inside its sandbox. Must stay in sync with
/// `command:` in flatpak/com.bandpassrecords.dpm.yml.
const String kFlatpakCommand = 'daw_project_manager';

/// The one rule every backend classifies its registration by.
///
/// A registration that names another install of the app which still exists
/// (a release build's entry seen from a dev build, the `.exe` installer's
/// copy seen from somewhere else) is reported [AutoStartStatus.off] and left
/// alone, as before: rewriting it would hijack the user's real startup entry
/// with whatever build happened to run. Only one that points at this very
/// executable, or at nothing any more, is [AutoStartStatus.stale].
AutoStartStatus classifyRegistration({
  required bool present,
  required bool disabledByUser,
  required bool matchesExpected,
  required bool pointsAtThisApp,
  required bool targetExists,
}) {
  if (!present || disabledByUser) return AutoStartStatus.off;
  if (matchesExpected) return AutoStartStatus.on;
  if (pointsAtThisApp || !targetExists) return AutoStartStatus.stale;
  return AutoStartStatus.off;
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

/// Windows paths compare case-insensitively.
bool windowsPathsEqual(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// The `HKCU\…\Run` value for [exe]. Quoted when it has a space: an install
/// under "C:\Program Files\…" is otherwise ambiguous once an argument
/// follows. Unquoted otherwise, which is what earlier builds wrote, so their
/// registrations still read as current.
String windowsRunCommand(String exe, {required bool minimized}) {
  final program = exe.contains(' ') ? '"$exe"' : exe;
  return minimized ? '$program $kStartMinimizedFlag' : program;
}

/// The executable a Run value launches, or null for an unterminated quote.
String? windowsRunCommandExecutable(String command) {
  final value = command.trim();
  if (value.startsWith('"')) {
    final end = value.indexOf('"', 1);
    return end < 0 ? null : value.substring(1, end);
  }
  final space = value.indexOf(' ');
  return space < 0 ? value : value.substring(0, space);
}

/// Whether a space-separated argument string carries [flag] as a whole word.
bool argumentsCarryFlag(String arguments, String flag) =>
    arguments.split(RegExp(r'\s+')).contains(flag);

/// Windows' `StartupApproved` value for a startup item: an odd first byte is
/// the user switching it off in Task Manager; missing or empty means allowed.
bool startupApprovalDisables(Uint8List? approval) =>
    approval != null && approval.isNotEmpty && approval[0].isOdd;

/// Where the MSIX execution alias lives, or null without `%LOCALAPPDATA%`.
String? msixAliasPath(String? localAppData) =>
    localAppData == null || localAppData.isEmpty
        ? null
        : '$localAppData\\Microsoft\\WindowsApps\\$kMsixExecutionAlias.exe';

/// The current user's Startup folder shortcut for the app.
String startupShortcutPath(String appData) =>
    '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\'
    '$kAutoStartAppName.lnk';

/// A PowerShell single-quoted literal: nothing inside is expanded, and a
/// quote is written twice.
String powerShellQuote(String value) => "'${value.replaceAll("'", "''")}'";

/// PowerShell that writes the Startup shortcut. Creating a `.lnk` needs the
/// shell's COM object, which PowerShell reaches without native code.
String startupShortcutScript({
  required String shortcutPath,
  required String target,
  required String arguments,
}) =>
    '\$s = (New-Object -ComObject WScript.Shell).CreateShortcut('
    '${powerShellQuote(shortcutPath)}); '
    '\$s.TargetPath = ${powerShellQuote(target)}; '
    '\$s.Arguments = ${powerShellQuote(arguments)}; '
    '\$s.Save()';

// ---------------------------------------------------------------------------
// Linux (.desktop autostart, outside Flatpak)
// ---------------------------------------------------------------------------

/// `$XDG_CONFIG_HOME/autostart`, or `~/.config/autostart` when that is unset
/// or relative (the XDG spec says to ignore a relative one). Null without
/// either.
String? autostartDirectory(Map<String, String> environment) {
  final xdg = environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty && p.posix.isAbsolute(xdg)) {
    return p.posix.join(xdg, 'autostart');
  }
  final home = environment['HOME'];
  if (home == null || home.isEmpty) return null;
  return p.posix.join(home, '.config', 'autostart');
}

/// What login should run. Inside an AppImage the process runs from a
/// temporary `/tmp/.mount_*` folder that is gone after a reboot; the
/// runtime names the image file itself in `$APPIMAGE`.
String linuxLaunchExecutable(
  Map<String, String> environment,
  String resolvedExecutable,
) {
  final appImage = environment['APPIMAGE'];
  return appImage != null && appImage.isNotEmpty ? appImage : resolvedExecutable;
}

// Characters that make an Exec argument need quoting (Desktop Entry spec,
// "The Exec key").
const _execReserved = ' \t\n"\'\\><~|&;\$*?#()`';

/// One Exec argument, quoted and escaped as the spec asks, `%` doubled.
String _desktopExecArg(String arg) {
  var out = arg;
  if (out.isEmpty || out.split('').any(_execReserved.contains)) {
    out = '"${out.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}')}"';
  }
  return out.replaceAll('%', '%%');
}

/// The raw `Exec=` value for [argv]: each argument quoted where needed, then
/// the whole value string-escaped, since the spec unescapes a value
/// (`\\`, `\n`…) before it parses the quoting.
String desktopExecLine(List<String> argv) => argv
    .map(_desktopExecArg)
    .join(' ')
    .replaceAll('\\', r'\\')
    .replaceAll('\n', r'\n');

/// The arguments a raw `Exec=` value runs, the reverse of [desktopExecLine].
/// Unquoted values (what earlier builds wrote, spaces and all) split on
/// whitespace, as the desktop does.
List<String> parseDesktopExec(String raw) {
  // String-level unescape first.
  final value = raw.replaceAllMapped(
    RegExp(r'\\(.)'),
    (m) => switch (m[1]) {
      's' => ' ',
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => m[1]!,
    },
  );
  final args = <String>[];
  final current = StringBuffer();
  var inArg = false;
  var quoted = false;
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (quoted) {
      if (c == '\\' && i + 1 < value.length) {
        current.write(value[++i]);
      } else if (c == '"') {
        quoted = false;
      } else {
        current.write(c);
      }
    } else if (c == '"') {
      quoted = true;
      inArg = true;
    } else if (c == ' ' || c == '\t') {
      if (inArg) {
        args.add(current.toString());
        current.clear();
        inArg = false;
      }
    } else {
      current.write(c);
      inArg = true;
    }
  }
  if (inArg) args.add(current.toString());
  return [for (final a in args) a.replaceAll('%%', '%')];
}

/// The autostart `.desktop` file, its `Exec=` built by [desktopExecLine].
String autostartDesktopEntry(List<String> argv) => '''
[Desktop Entry]
Type=Application
Name=$kAutoStartAppName
Comment=$kAutoStartAppName startup script
Exec=${desktopExecLine(argv)}
StartupNotify=false
Terminal=false
''';

/// What an autostart `.desktop` file says, read from its `[Desktop Entry]`
/// group only.
class AutostartEntryFacts {
  const AutostartEntryFacts({required this.exec, required this.disabled});

  /// The raw `Exec=` value, or null when there is none.
  final String? exec;

  /// `Hidden=true` or `X-GNOME-Autostart-enabled=false`: the user switched
  /// it off in their desktop's startup settings.
  final bool disabled;
}

AutostartEntryFacts readAutostartEntry(String content) {
  String? exec;
  var disabled = false;
  var inMainGroup = false;
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('[')) {
      inMainGroup = line == '[Desktop Entry]';
      continue;
    }
    if (!inMainGroup) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    switch (key) {
      case 'Exec':
        exec = value;
      case 'Hidden':
        if (value == 'true') disabled = true;
      case 'X-GNOME-Autostart-enabled':
        if (value == 'false') disabled = true;
    }
  }
  return AutostartEntryFacts(exec: exec, disabled: disabled);
}
