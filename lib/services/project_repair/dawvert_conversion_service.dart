import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'project_format_registry.dart';
import 'verified_project_backup.dart';
import 'reaper_sidecar_stager.dart';

/// The script and Python runtime are user-supplied, trusted local executables.
///
/// Processes are not OS-sandboxed. Nothing is automatically downloaded, and
/// this bridge never offers a CPR/native Cubase target.
typedef DawVertProcessRunner = Future<DawVertProcessOutcome> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
  Duration timeout,
);

class DawVertProcessOutcome {
  const DawVertProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A generated conversion file is not evidence of a successful DAW reopen,
/// plug-in state transfer, MIDI automation equivalence or audio fidelity.
class DawVertConversionResult {
  const DawVertConversionResult({
    required this.sourcePath,
    required this.outputPath,
    required this.backupPath,
    required this.reportPath,
    required this.sourceSha256,
    required this.outputSha256,
    required this.sourceFormat,
    required this.targetFormat,
  });

  final String sourcePath;
  final String outputPath;
  final String backupPath;
  final String reportPath;
  final String sourceSha256;
  final String outputSha256;
  final String sourceFormat;
  final String targetFormat;

  Map<String, Object?> toJson() => {
    'status': 'generated_unverified',
    'source': sourcePath,
    'source_sha256': sourceSha256,
    'backup': backupPath,
    'output': outputPath,
    'output_sha256': outputSha256,
    'report': reportPath,
    'source_format': sourceFormat,
    'target_format': targetFormat,
    'original_modified': false,
    'native_daw_reopen_verified': false,
    'plugin_state_preservation_verified': false,
    'automation_preservation_verified': false,
    'routing_preservation_verified': false,
    'audio_fidelity_verified': false,
  };
}

/// Opt-in local DawVert execution using a verified backup and isolated copies.
///
/// All outputs remain in a unique managed directory and are never promoted
/// over an existing project. No helper silently downloads third-party code.
class DawVertConversionService {
  DawVertConversionService({DawVertProcessRunner? runner})
      : _runner = runner ?? _runProcess;

  final DawVertProcessRunner _runner;

  /// Format identifier -> (DawVert short name, output file extension).
  /// CPR is deliberately absent: DawVert does not document CPR input.
  static const supportedFormats = <String, (String, String)>{
    'reaper': ('reaper', '.rpp'),
    'dawproject': ('dawproject', '.dawproject'),
    'flstudio': ('flp', '.flp'),
    'ableton': ('ableton', '.als'),
    'lmms': ('lmms', '.mmp'),
    'midi': ('midi', '.mid'),
  };

  Future<DawVertConversionResult> convert({
    required File original,
    required File dawvertScript,
    required String pythonExecutable,
    required String targetFormat,
    required bool acknowledgeFidelityRisks,
    Directory? outputRoot,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!acknowledgeFidelityRisks) {
      throw const FormatException(
        'Explicit acceptance of unverified conversion fidelity is required',
      );
    }
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout);
    if (!p.isAbsolute(pythonExecutable) ||
        !await File(pythonExecutable).exists()) {
      throw const FileSystemException('An existing absolute Python runtime is required');
    }
    if (!await dawvertScript.exists() ||
        p.basename(dawvertScript.path) != 'dawvert_cmd.py') {
      throw const FileSystemException('Select a local DawVert dawvert_cmd.py');
    }
    if (!await original.exists()) {
      throw const FileSystemException('The input project does not exist');
    }
    final size = await original.length();
    if (size == 0 || size > 256 * 1024 * 1024) {
      throw const FormatException('Input project outside conversion size bounds');
    }

    final sourceDescriptor = await _detectFile(original);
    final from = supportedFormats[sourceDescriptor.id];
    final to = supportedFormats[targetFormat];
    if (from == null || to == null || sourceDescriptor.id == targetFormat) {
      throw const FormatException('Unsupported DawVert conversion direction');
    }

    // Always complete the verified backup before any third-party process.
    final backup = await VerifiedProjectBackup.create(original);
    final parent = outputRoot ??
        Directory(p.join(p.dirname(original.absolute.path), '.project-repair-exports'));
    if (p.split(parent.absolute.path).contains('.project-repair-backups')) {
      throw const FileSystemException('Conversion output cannot be inside managed backups');
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(parent.absolute.path);
    await parent.create(recursive: true);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(parent.absolute.path);
    final run = await parent.createTemp('dpm-dawvert-');
    final clone = File(p.join(run.path, p.basename(original.path)));
    final output = File(p.join(run.path, 'converted' + to.$2));
    final manifest = File(p.join(run.path, 'conversion-report.json'));

    await original.copy(clone.path);
    if (await _sha256Of(clone) != backup.sha256Digest ||
        await _sha256Of(original) != backup.sha256Digest) {
      throw const FileSystemException('Input changed during safe staging');
    }
    // Stage the REAPER FILE sidecars under the same relative names as in RPP.
    // Absolute or missing references fail closed instead of making a silent
    // conversion that has dropped its audio or external MIDI assets.
    ReaperSidecarManifest? media;
    if (sourceDescriptor.id == 'reaper') {
      try {
        media = await ReaperSidecarStager.stage(
          original: original, workspace: run,
        );
      } catch (error) {
        await _writeFailure(
          manifest, 'Media staging failed: ' + error.toString(),
          backup.backupPath,
        );
        rethrow;
      }
    }
    final args = <String>[
      dawvertScript.absolute.path,
      '-it', from.$1,
      '-i', clone.path,
      '-ot', to.$1,
      '-o', output.path,
    ];

    DawVertProcessOutcome process;
    try {
      // The process receives only the staged project as its input argument.
      // This is not an OS security sandbox: only use a trusted local script.
      process = await _runner(
        pythonExecutable, args, run.path, timeout,
      );
    } catch (error) {
      await _writeFailure(manifest, 'External converter could not run: $error',
          backup.backupPath);
      rethrow;
    }
    if (process.exitCode != 0) {
      await _writeFailure(manifest,
          'DawVert failed with exit code ${process.exitCode}: '
          '${_bounded(process.stderr)}', backup.backupPath);
      throw ProcessException(
        'DawVert', args, 'Converter returned a failure code', process.exitCode,
      );
    }
    if (!await output.exists() ||
        await output.length() == 0 ||
        await output.length() > 512 * 1024 * 1024) {
      await _writeFailure(manifest, 'Missing or excessive converter output',
          backup.backupPath);
      throw const FormatException('Converter produced no bounded output');
    }
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.file) {
      await _writeFailure(manifest, 'Conversion output is not a regular file',
          backup.backupPath);
      throw const FormatException('Unsafe converter output');
    }
    late final ProjectFormatDescriptor outputDescriptor;
    try {
      outputDescriptor = await _detectFile(output);
    } on FormatException catch (error) {
      await _writeFailure(
        manifest, 'Invalid output signature: ' + error.message,
        backup.backupPath,
      );
      rethrow;
    }
    if (outputDescriptor.id != targetFormat) {
      await _writeFailure(
        manifest, 'Output format signature does not match request',
        backup.backupPath,
      );
      throw const FormatException('DawVert output signature mismatch');
    }
    if (await _sha256Of(original) != backup.sha256Digest ||
        await original.length() != backup.length) {
      await _writeFailure(manifest, 'Original project differs from verified backup',
          backup.backupPath);
      throw const FileSystemException('Original project changed during conversion');
    }

    if (media != null) {
      for (final sidecar in media.files) {
        final file = File(p.join(original.parent.path, sidecar.relativePath));
        if (!await file.exists() ||
            await _sha256Of(file) != sidecar.sha256Digest) {
          await _writeFailure(
            manifest, 'Source media changed during conversion',
            backup.backupPath,
          );
          throw const FileSystemException('Source media changed during conversion');
        }
      }
    }

    final result = DawVertConversionResult(
      sourcePath: original.absolute.path,
      outputPath: output.path,
      backupPath: backup.backupPath,
      reportPath: manifest.path,
      sourceSha256: backup.sha256Digest,
      outputSha256: await _sha256Of(output),
      sourceFormat: sourceDescriptor.id,
      targetFormat: targetFormat,
    );
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...result.toJson(),
        'converter': 'DawVert (external, locally supplied)',
        'converter_exit_code': process.exitCode,
        'media_staging': media?.toJson() ?? const {
          'status': 'unverified_for_this_source_format',
        },
        'stdout_excerpt': _bounded(process.stdout),
        'stderr_excerpt': _bounded(process.stderr),
        'warnings': const [
          'This output has not been reopened in the destination DAW.',
          'Missing plug-ins, states, routing and automations may be lost.',
          'The external converter is not an operating-system sandbox.',
        ],
      }),
      flush: true,
    );
    return result;
  }

  static Future<void> _writeFailure(
      File manifest, String detail, String backup) async {
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': 'failed',
        'detail': detail,
        'verified_backup': backup,
        'native_daw_reopen_verified': false,
      }),
      flush: true,
    );
  }

  static String _bounded(String value) =>
      value.length > 4096 ? value.substring(0, 4096) : value;

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<ProjectFormatDescriptor> _detectFile(File file) async {
    final header = <int>[];
    await for (final part in file.openRead(0, 128)) {
      header.addAll(part);
    }
    final result = ProjectFormatRegistry.detect(
      file.path, Uint8List.fromList(header),
    );
    if (result == null) {
      throw const FormatException('Unrecognized project file signature');
    }
    return result;
  }

  static Future<DawVertProcessOutcome> _runProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
    Duration timeout,
  ) async {
    final child = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );

    Future<String> collect(Stream<List<int>> stream) async {
      final bytes = BytesBuilder(copy: false);
      var captured = 0;
      await for (final part in stream) {
        if (captured >= 4096) continue;
        final take = part.length < 4096 - captured
            ? part.length : 4096 - captured;
        bytes.add(part.sublist(0, take));
        captured += take;
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    }

    final out = collect(child.stdout);
    final err = collect(child.stderr);
    int exitCode;
    try {
      exitCode = await child.exitCode.timeout(timeout);
    } on TimeoutException {
      child.kill();
      throw TimeoutException('DawVert exceeded the requested time limit');
    }
    return DawVertProcessOutcome(
      exitCode: exitCode,
      stdout: await out,
      stderr: await err,
    );
  }
}
 + '{error.message}',
          backup.backupPath);
      rethrow;
    }
    if (outputDescriptor.id != targetFormat) {
      await _writeFailure(manifest, 'Output format signature does not match request',
          backup.backupPath);
      throw const FormatException('DawVert output signature mismatch');
    }
    if (await _sha256Of(original) != backup.sha256Digest ||
        await original.length() != backup.length) {
      await _writeFailure(manifest, 'Original project differs from verified backup',
          backup.backupPath);
      throw const FileSystemException('Original project changed during conversion');
    }

    final result = DawVertConversionResult(
      sourcePath: original.absolute.path,
      outputPath: output.path,
      backupPath: backup.backupPath,
      reportPath: manifest.path,
      sourceSha256: backup.sha256Digest,
      outputSha256: await _sha256Of(output),
      sourceFormat: sourceDescriptor.id,
      targetFormat: targetFormat,
    );
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...result.toJson(),
        'converter': 'DawVert (external, locally supplied)',
        'converter_exit_code': process.exitCode,
        'stdout_excerpt': _bounded(process.stdout),
        'stderr_excerpt': _bounded(process.stderr),
        'warnings': const [
          'This output has not been reopened in the destination DAW.',
          'Missing plug-ins, states, routing and automations may be lost.',
          'The external converter is not an operating-system sandbox.',
        ],
      }),
      flush: true,
    );
    return result;
  }

  static Future<void> _writeFailure(
      File manifest, String detail, String backup) async {
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': 'failed',
        'detail': detail,
        'verified_backup': backup,
        'native_daw_reopen_verified': false,
      }),
      flush: true,
    );
  }

  static String _bounded(String value) =>
      value.length > 4096 ? value.substring(0, 4096) : value;

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<ProjectFormatDescriptor> _detectFile(File file) async {
    final header = <int>[];
    await for (final part in file.openRead(0, 128)) {
      header.addAll(part);
    }
    final result = ProjectFormatRegistry.detect(
      file.path, Uint8List.fromList(header),
    );
    if (result == null) {
      throw const FormatException('Unrecognized project file signature');
    }
    return result;
  }

  static Future<DawVertProcessOutcome> _runProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
    Duration timeout,
  ) async {
    final child = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );

    Future<String> collect(Stream<List<int>> stream) async {
      final bytes = BytesBuilder(copy: false);
      var captured = 0;
      await for (final part in stream) {
        if (captured >= 4096) continue;
        final take = part.length < 4096 - captured
            ? part.length : 4096 - captured;
        bytes.add(part.sublist(0, take));
        captured += take;
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    }

    final out = collect(child.stdout);
    final err = collect(child.stderr);
    int exitCode;
    try {
      exitCode = await child.exitCode.timeout(timeout);
    } on TimeoutException {
      child.kill();
      throw TimeoutException('DawVert exceeded the requested time limit');
    }
    return DawVertProcessOutcome(
      exitCode: exitCode,
      stdout: await out,
      stderr: await err,
    );
  }
}
