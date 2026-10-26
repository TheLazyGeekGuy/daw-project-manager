import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'all_to_midi_bridge.dart';
import 'native_legacy_all_reader.dart';
import 'native_legacy_all_midi_encoder.dart';
import 'verified_project_backup.dart';

/// DPM-native .ALL -> .mid recovery, with no Cubase 3, Windows executable,
/// Python runtime or network connection. Uses pure Dart on macOS/Windows/Linux.
///
/// Requires a successful SHA-256 backup before reading and rejects an
/// unsupported ALL layout, never overwrites the original or any existing
/// output, and keeps a diagnostic JSON alongside the new type-1 MIDI.
class NativeLegacyAllConversion {
  const NativeLegacyAllConversion();

  Future<NativeLegacyAllResult> convert({
    required File original,
    Directory? outputRoot,
  }) async {
    if (p.extension(original.path).toLowerCase() != '.all') {
      throw const FormatException(
        'Native legacy conversion supports .ALL only; .ARR remains unsupported',
      );
    }
    if (!await original.exists() ||
        await original.length() < 192 ||
        await original.length() > NativeLegacyAllReader.maxInputBytes) {
      throw const FormatException(
        'Legacy ALL source is missing or outside parser limits',
      );
    }

    // A fully checked backup is mandatory before inspecting an untrusted ALL.
    final backup = await VerifiedProjectBackup.create(original);
    final backupFile = File(backup.backupPath);
    final parent = outputRoot ??
        Directory(p.join(
            original.parent.absolute.path, '.project-repair-exports'));
    if (p.split(p.normalize(parent.absolute.path))
        .contains('.project-repair-backups')) {
      throw const FileSystemException(
          'Cannot write exports into the managed backup directory');
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
        parent.absolute.path);
    await parent.create(recursive: true);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
        parent.absolute.path);
    final outputDir = await parent.createTemp('dpm-native-all-');
    final output = File(p.join(
      outputDir.path, p.basenameWithoutExtension(original.path) + '.mid',
    ));
    final reportFile = File(p.join(
      outputDir.path, 'legacy-midi-report.json',
    ));

    try {
      final bytes = await backupFile.readAsBytes();
      final song = const NativeLegacyAllReader().read(bytes);
      final encoded = const NativeLegacyAllMidiEncoder().encode(
        song,
        songName: p.basenameWithoutExtension(original.path),
      );
      final parsedMidi = AllToMidiOutputProbe.inspect(encoded);
      if (parsedMidi.tracks != song.tracks.length + 1 ||
          parsedMidi.notes != song.noteCount) {
        throw const FormatException(
            'Recovered MIDI did not match decoded track/note counts');
      }

      // File is new inside a unique, DPM-managed run directory.
      await output.writeAsBytes(encoded, flush: true);
      final generatedHash = await _digest(output);
      if (generatedHash != sha256.convert(encoded).toString() ||
          await _digest(original) != backup.sha256Digest ||
          await _digest(backupFile) != backup.sha256Digest ||
          await original.length() != backup.length) {
        throw const FileSystemException(
            'Source, backup or MIDI output changed unexpectedly');
      }

      final result = NativeLegacyAllResult(
        sourcePath: original.absolute.path,
        backupPath: backup.backupPath,
        outputPath: output.absolute.path,
        reportPath: reportFile.absolute.path,
        sourceHash: backup.sha256Digest,
        outputHash: generatedHash,
        trackCount: song.tracks.length,
        partCount: song.tracks.fold<int>(
            0, (count, track) => count + track.partCount),
        noteCount: song.noteCount,
        summary: song.toJson(),
      );
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
        flush: true,
      );
      return result;
    } catch (error) {
      // Preserve backups and export workspaces on failure. Do not leave a
      // partial MIDI file looking like a successful conversion.
      if (await output.exists()) {
        await output.rename(output.path + '.unverified');
      }
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'status': 'conversion_failed',
          'original': original.absolute.path,
          'verified_source_backup': backup.backupPath,
          'error_type': error.runtimeType.toString(),
          'error': error.toString(),
          'source_modified_by_dpm': false,
          'native_cubase_fidelity_verified': false,
        }),
        flush: true,
      );
      rethrow;
    }
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

class NativeLegacyAllResult {
  const NativeLegacyAllResult({
    required this.sourcePath,
    required this.backupPath,
    required this.outputPath,
    required this.reportPath,
    required this.sourceHash,
    required this.outputHash,
    required this.trackCount,
    required this.partCount,
    required this.noteCount,
    required this.summary,
  });

  final String sourcePath;
  final String backupPath;
  final String outputPath;
  final String reportPath;
  final String sourceHash;
  final String outputHash;
  final int trackCount;
  final int partCount;
  final int noteCount;
  final Map<String, Object?> summary;

  Map<String, Object?> toJson() => {
    'status': 'native_midi_generated_unverified',
    'format': 'cubase-vst-all',
    'converter': 'DPM Dart native (MIT AllToMidi-derived algorithms)',
    'original': sourcePath,
    'source_sha256': sourceHash,
    'immutable_backup': backupPath,
    'midi_output': outputPath,
    'midi_sha256': outputHash,
    'report': reportPath,
    'midi_tracks': trackCount,
    'recovered_parts': partCount,
    'midi_notes': noteCount,
    'ppq': 480,
    'reader_report': summary,
    'external_runtime_required': false,
    'original_modified': false,
    'native_cubase_fidelity_verified': false,
    'audio_preserved': false,
    'vst_state_preserved': false,
    'automation_preservation_verified': false,
    'routing_preserved': false,
  };
}
