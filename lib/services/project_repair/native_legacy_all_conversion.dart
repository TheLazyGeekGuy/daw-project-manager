import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'legacy_all_conversion_service.dart';

/// Compatibility entry point for DPM's guarded, local ALL-to-MIDI recovery.
///
/// All decoding, source checks, staging, backup and MIDI validation delegate to
/// LegacyAllConversionService. The original result/report API remains available
/// for existing callers; the canonical safety report is retained alongside it.
/// UI callers must present the MIDI-only loss explanation before invoking this
/// historical convenience API. New UI should call the explicit-consent service.
class NativeLegacyAllConversion {
  const NativeLegacyAllConversion();

  Future<NativeLegacyAllResult> convert({
    required File original,
    Directory? outputRoot,
    bool acknowledgeFidelityRisks = true,
  }) async {
    final report = await LegacyAllConversionService.convert(
      original: original,
      outputRoot: outputRoot,
      acknowledgeFidelityRisks: acknowledgeFidelityRisks,
    );
    final tracks = (report['tracks'] as List).cast<Map>();
    final skipped = report['skipped_parts'] as int;
    final defaulted = report['initial_tempo_defaulted'] as bool;
    final summary = <String, Object?>{
      'format': 'cubase-vst-all',
      'decoder': 'native-dart-experimental',
      'status': report['status'],
      'skipped_parts': skipped,
      'initial_tempo_defaulted': defaulted,
      'tracks': [
        for (final track in tracks) {...track, 'midi_events': track['events']},
      ],
      'total_midi_events': tracks.fold<int>(
        0,
        (count, track) => count + (track['events'] as int),
      ),
      'total_notes': report['note_count'],
      'initial_bpm': 60000000 / (report['initial_tempo_microseconds'] as int),
      'time_signatures': report['time_signatures'],
      'warnings': report['limitations'],
      'verified_against_native_cubase': false,
      'vst_state_preserved': false,
    };
    final canonicalReport = report['report'] as String;
    final compatibilityReport = File(
      p.join(p.dirname(canonicalReport), 'legacy-midi-report.json'),
    );
    final result = NativeLegacyAllResult(
      sourcePath: report['source'] as String,
      backupPath: report['backup'] as String,
      outputPath: report['output'] as String,
      reportPath: compatibilityReport.path,
      sourceHash: report['source_sha256'] as String,
      outputHash: report['output_sha256'] as String,
      trackCount: report['track_count'] as int,
      partCount: tracks.fold<int>(
        0,
        (count, track) => count + (track['parts'] as int),
      ),
      noteCount: report['note_count'] as int,
      skippedParts: skipped,
      canonicalReportPath: canonicalReport,
      summary: summary,
    );
    await compatibilityReport.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
      flush: true,
    );
    return result;
  }
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
    this.skippedParts = 0,
    this.canonicalReportPath,
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
  final int skippedParts;
  final String? canonicalReportPath;
  final Map<String, Object?> summary;

  Map<String, Object?> toJson() => {
    'status': skippedParts > 0
        ? 'partial_recovery_unverified'
        : 'native_midi_generated_unverified',
    'format': 'cubase-vst-all',
    'converter': 'DPM Dart native (MIT AllToMidi-derived algorithms)',
    'original': sourcePath,
    'source_sha256': sourceHash,
    'immutable_backup': backupPath,
    'midi_output': outputPath,
    'midi_sha256': outputHash,
    'report': reportPath,
    'canonical_report': canonicalReportPath,
    'midi_tracks': trackCount,
    'recovered_parts': partCount,
    'skipped_parts': skippedParts,
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
