// The DAW plugin's own bridge code, run headless: the plugin repo's
// DAWProjectManagerBridgeDriver is one plugin instance (its BridgeSession)
// with no DAW, audio or window, driven a line of JSON at a time. The
// integration tests put it and the app's real bridge service on one folder.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PluginDriver {
  PluginDriver._(this._process, this.runId, this.version) {
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }

  final Process _process;

  /// This instance's run id, as its hellos and heartbeats name it.
  final String runId;

  /// The plugin's version string.
  final String version;

  final _stderr = StringBuffer();
  late final _LineReader _lines;

  static const _binaryName = 'DAWProjectManagerBridgeDriver';

  /// How long a command may take: they touch a handful of small files.
  static const replyTimeout = Duration(seconds: 15);

  /// The driver to run: `DPM_PLUGIN_DRIVER` when set (CI), else a build in
  /// the plugin repo checked out next to this one. Null: no driver here, and
  /// the integration tests skip.
  static String? locate() {
    final fromEnv = Platform.environment['DPM_PLUGIN_DRIVER'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return File(fromEnv).existsSync() ? fromEnv : null;
    }
    final exe = Platform.isWindows ? '$_binaryName.exe' : _binaryName;
    final parent = Directory.current.parent.path;
    for (final repo in const ['daw-project-manager-plugin', 'dpm-companion']) {
      for (final config in const ['Release', 'Debug', '']) {
        final candidate =
            p.join(parent, repo, 'build', '${_binaryName}_artefacts', config, exe);
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  /// Starts one plugin instance on [bridgeDir] and waits for it to say it's
  /// ready.
  static Future<PluginDriver> start(String executable, {required String bridgeDir}) async {
    final process = await Process.start(
      executable,
      const [],
      environment: {'DPM_BRIDGE_DIR': bridgeDir},
    );
    final lines = _LineReader(process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final Map<String, dynamic> ready;
    try {
      ready = jsonDecode(await lines.next().timeout(replyTimeout)) as Map<String, dynamic>;
    } catch (e) {
      process.kill();
      throw StateError('Plugin driver did not start: $e');
    }
    if (ready['ok'] != true || ready['ready'] != true) {
      process.kill();
      throw StateError('Plugin driver did not start: $ready');
    }
    final driver = PluginDriver._(process, ready['runId'] as String, ready['version'] as String);
    driver._lines = lines;
    return driver;
  }

  /// Runs [cmd] and returns its reply; a reply that isn't `ok` throws.
  Future<Map<String, dynamic>> send(String cmd, [Map<String, Object?> args = const {}]) async {
    _process.stdin.writeln(jsonEncode({'cmd': cmd, ...args}));
    await _process.stdin.flush();
    final String line;
    try {
      line = await _lines.next().timeout(replyTimeout);
    } on TimeoutException {
      throw StateError('Plugin driver gave no reply to "$cmd". stderr:\n$_stderr');
    }
    final reply = jsonDecode(line) as Map<String, dynamic>;
    if (reply['ok'] != true) {
      throw StateError('Plugin driver: "$cmd" failed: ${reply['error']}');
    }
    return reply;
  }

  /// Sets the plugin's clock: its messages and heartbeats are stamped with
  /// it, so a test can let a heartbeat go stale without waiting.
  Future<void> setClock(DateTime now) => send('clock', {'now': now.toUtc().toIso8601String()});

  /// What the plugin would read from its DAW: the host's own name and the
  /// main window's title, which names the open project.
  Future<void> host(String name, String windowTitle) =>
      send('host', {'name': name, 'windowTitle': windowTitle});

  Future<Map<String, dynamic>> state() => send('state');

  /// Ends the instance without a goodbye, as a DAW that crashed.
  Future<void> kill() async {
    _process.kill();
    await _process.exitCode;
  }

  Future<void> quit() async {
    try {
      await send('quit');
    } catch (_) {
      // Exiting may close stdout before the reply is read.
    }
    await _process.exitCode.timeout(replyTimeout, onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}

/// Lines from a stream, one at a time on request.
class _LineReader {
  _LineReader(Stream<String> lines) {
    lines.listen((line) {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(line);
      } else {
        _buffered.add(line);
      }
    }, onDone: () {
      for (final w in _waiting) {
        w.completeError(StateError('Plugin driver exited'));
      }
      _waiting.clear();
      _done = true;
    });
  }

  final _buffered = <String>[];
  final _waiting = <Completer<String>>[];
  var _done = false;

  Future<String> next() {
    if (_buffered.isNotEmpty) return Future.value(_buffered.removeAt(0));
    if (_done) return Future.error(StateError('Plugin driver exited'));
    final c = Completer<String>();
    _waiting.add(c);
    return c.future;
  }
}
