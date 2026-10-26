import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../midi/midi_file_reader.dart';
import 'legacy_cubase_migration.dart';
import 'verified_project_backup.dart';

/// Opt-in integration of the MIT-licensed, Windows-only AllToMidi CLI.
///
/// AllToMidi 1.0 accepts Cubase .ALL songs, not .ARR arrangements, and
/// produces type-1 MIDI files. Audio, plug-in states and mixer settings are
/// explicitly outside this bridge. No third-party executable is bundled.
typedef AllToMidiRunner = Future<AllToMidiProcessOutcome> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
  Duration timeout,
);

class AllToMidiProcessOutcome {
  const AllToMidiProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Strict bounded MIDI envelope validation, independent of permissive
/// metadata decoding. A valid SMF container cannot establish musical
/// equivalence with the legacy Cubase source.
class AllToMidiOutputProbe {
  static ({int tracks, int ppq, int notes}) inspect(Uint8List bytes) {
    if (bytes.length < 22 || bytes.length > 128 * 1024 * 1024) {
      throw const FormatException('Invalid MIDI output file size');
    }
    final view = ByteData.sublistView(bytes);
    bool starts(int offset, String value) {
      if (offset < 0 || offset + value.length > bytes.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (bytes[offset + i] != value.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (!starts(0, 'MThd') ||
        view.getUint32(4, Endian.big) != 6 ||
        view.getUint16(8, Endian.big) != 1) {
      throw const FormatException('Expected Standard MIDI File type 1');
    }
    final declaredTracks = view.getUint16(10, Endian.big);
    final ppq = view.getUint16(12, Endian.big);
    if (declaredTracks == 0 || declaredTracks > 1024 || ppq != 480) {
      throw const FormatException('Invalid MIDI track count or PPQ');
    }

    var at = 14;
    for (var track = 0; track < declaredTracks; track++) {
      if (!starts(at, 'MTrk') || at + 8 > bytes.length) {
        throw const FormatException('Missing MIDI track chunk');
      }
      final length = view.getUint32(at + 4, Endian.big);
      if (length > bytes.length - (at + 8)) {
        throw const FormatException('Truncated MIDI track chunk');
      }
      at += 8 + length;
    }
    if (at != bytes.length) {
      throw const FormatException('Trailing bytes or unexpected MIDI chunks');
    }
    final tracks = decodeMidiFileTracks(bytes);
    if (tracks == null || tracks.tracks.length != declaredTracks) {
      throw const FormatException('MIDI track decoding failed');
    }
    return (
      tracks: declaredTracks,
      ppq: ppq,
      notes: tracks.tracks.fold<int>(
        0, (sum, track) => sum + track.notes.length,
      ),
    );
  }
}

class AllToMidiConversionResult {
  const AllToMidiConversionResult({
    required this.sourcePath,
    required this.backupPath,
    required this.outputPath,
    required this.reportPath,
    required this.sourceSha256,
    required this.outputSha256,
    required this.trackCount,
    required this.noteCount,
    required this.ppq,
  });

  final String sourcePath;
  final String backupPath;
  final String outputPath;
  final String reportPath;
  final String sourceSha256;
  final String outputSha256;
  final int trackCount;
  final int noteCount;
  final int ppq;

  Map<String, Object?> toJson() => {
    'status': 'midi_generated_unverified',
    'source': sourcePath,
    'source_sha256': sourceSha256,
    'source_backup': backupPath,
    'midi_output': outputPath,
    'midi_sha256': outputSha256,
    'midi_tracks': trackCount,
    'midi_notes_decoded': noteCount,
    'midi_ppq': ppq,
    'report': reportPath,
    'original_modified': false,
    'conversion_performed_by_dpm': false,
    'native_cubase_reopen_verified': false,
    'original_midi_equivalence_verified': false,
    'audio_preserved': false,
    'vst_state_preserved': false,
    'mixer_preserved': false,
  };
}

/// Executes a separately installed AllToMidi.exe on a verified copy.
///
/// The external executable is NOT operating-system sandboxed. It must be
/// locally installed and trusted by the user. No hidden downloads occur.
class AllToMidiBridge {
  AllToMidiBridge({
    AllToMidiRunner? runner,
    bool? windowsOverrideForTests,
  })  : _runner = runner ?? _runProcess,
        _isWindows = windowsOverrideForTests ?? Platform.isWindows;

  final AllToMidiRunner _runner;
  final bool _isWindows;

  Future<AllToMidiConversionResult> convert({
    required File original,
    required File executable,
    required bool acknowledgeLosses,
    Directory? outputRoot,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (!acknowledgeLosses) {
      throw const FormatException('Explicit acceptance of MIDI-only recovery is required');
    }
    if (!_isWindows) {
      throw const UnsupportedError(
        'AllToMidi.exe requires Windows; use the manual route or a port',
      );
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout);
    if (p.extension(original.path).toLowerCase() != '.all') {
      throw const FormatException('AllToMidi supports .ALL only, not .ARR');
    }
    if (!p.isAbsolute(executable.path) ||
        p.basename(executable.path).toLowerCase() != 'alltomidi.exe' ||
        !await executable.exists()) {
      throw const FileSystemException('Select an installed AllToMidi.exe using an absolute path');
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(executable.absolute.path);
    if (await FileSystemEntity.type(executable.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('AllToMidi executable is not a regular file');
    }
    if (!await original.exists() ||
        await original.length() == 0 ||
        await original.length() > 128 * 1024 * 1024) {
      throw const FormatException('Legacy Cubase source is missing or oversized');
    }

    // A hash-verified original backup is a prerequisite for any execution.
    final prepared = await LegacyCubaseMigration.prepare(original);
    final parent = outputRoot ??
        Directory(p.join(original.parent.absolute.path, '.project-repair-exports'));
    await VerifiedProjectBackup.ensureNoSymlinkComponents(parent.absolute.path);
    if (p.split(parent.absolute.path).contains('.project-repair-backups')) {
      throw const FileSystemException('Output must not be inside managed backups');
    }
    await parent.create(recursive: true);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(parent.absolute.path);
    final run = await parent.createTemp('dpm-alltomidi-');
    final input = File(p.join(run.path, 'input', p.basename(original.path)));
    final outputs = Directory(p.join(run.path, 'output'));
    final report = File(p.join(run.path, 'alltomidi-report.json'));
    await input.parent.create();
    await outputs.create();
    await original.copy(input.path);
    if (await _sha256(input) != prepared.legacySha256 ||
        await _sha256(original) != prepared.legacySha256) {
      throw const FileSystemException('Source changed during conversion staging');
    }

    // AllToMidi v1.0 honors --output-folder and --same-name and produces
    // exactly one Song.mid for a staged Song.ALL file.
    final args = <String>[
      '--output-folder', outputs.absolute.path,
      '--same-name',
      '--no-preserve-date',
      input.absolute.path,
    ];
    AllToMidiProcessOutcome outcome;
    try {
      outcome = await _runner(
        executable.absolute.path, args, run.path, timeout,
      );
    } catch (error) {
      await _failure(report, prepared.backupPath,
          'External converter execution failed: ' + error.toString());
      rethrow;
    }

    if (outcome.exitCode != 0) {
      await _failure(report, prepared.backupPath,
          'AllToMidi exited with status ${outcome.exitCode}: '
          '${_truncated(outcome.stderr)}');
      throw ProcessException(
        executable.path, args, 'AllToMidi failed', outcome.exitCode,
      );
    }
    final output = File(p.join(
      outputs.path, p.basenameWithoutExtension(input.path) + '.mid',
    ));
    late final ({int tracks, int ppq, int notes}) midi;
    try {
      if (await FileSystemEntity.type(output.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !await output.exists() ||
          await output.length() > 128 * 1024 * 1024) {
        throw const FormatException('Converter did not produce one safe MIDI file');
      }
      midi = AllToMidiOutputProbe.inspect(await output.readAsBytes());
      if (await _sha256(original) != prepared.legacySha256 ||
          await _sha256(File(prepared.backupPath)) != prepared.legacySha256 ||
          await original.length() != prepared.legacySize) {
        throw const FileSystemException('Original or protected backup changed during conversion');
      }
    } catch (error) {
      await _failure(report, prepared.backupPath,
          'MIDI validation failed: ' + error.toString());
      rethrow;
    }

    final result = AllToMidiConversionResult(
      sourcePath: original.absolute.path,
      backupPath: prepared.backupPath,
      outputPath: output.absolute.path,
      reportPath: report.absolute.path,
      sourceSha256: prepared.legacySha256,
      outputSha256: await _sha256(output),
      trackCount: midi.tracks,
      noteCount: midi.notes,
      ppq: midi.ppq,
    );
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...result.toJson(),
        'converter': 'OnjLouis/AllToMidi 1.0 (user-supplied MIT application)',
        'converter_exit_code': outcome.exitCode,
        'stdout_excerpt': _truncated(outcome.stdout),
        'stderr_excerpt': _truncated(outcome.stderr),
        'limitations': const [
          'MIDI-only extraction; audio and VST plug-in states are not recoverable.',
          'Mid-song tempo, time signatures and SysEx may be incomplete.',
          'The output has not been imported or played in Cubase.',
          'The local external executable is not OS-sandboxed.',
        ],
      }),
      flush: true,
    );
    return result;
  }

  static Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static String _truncated(String value) =>
      value.length > 4096 ? value.substring(0, 4096) : value;

  static Future<void> _failure(
      File report, String backup, String message) async {
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': 'failed',
        'verified_backup': backup,
        'reason': _truncated(message),
        'native_reopen_verified': false,
      }),
      flush: true,
    );
  }

  static Future<AllToMidiProcessOutcome> _runProcess(
    String executable,
    List<String> args,
    String workingDirectory,
    Duration timeout,
  ) async {
    final process = await Process.start(
      executable, args,
      workingDirectory: workingDirectory,
      runInShell: false,
    );

    Future<String> drain(Stream<List<int>> stream) async {
      final buffer = BytesBuilder(copy: false);
      var copied = 0;
      await for (final part in stream) {
        if (copied >= 4096) continue;
        final count = part.length < 4096 - copied
            ? part.length : 4096 - copied;
        buffer.add(part.sublist(0, count));
        copied += count;
      }
      return utf8.decode(buffer.takeBytes(), allowMalformed: true);
    }

    final out = drain(process.stdout);
    final err = drain(process.stderr);
    int result;
    try {
      result = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw TimeoutException('AllToMidi timed out');
    }
    return AllToMidiProcessOutcome(
      exitCode: result,
      stdout: await out,
      stderr: await err,
    );
  }
}
