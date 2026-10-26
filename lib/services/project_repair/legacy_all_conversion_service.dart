import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'legacy_all_midi_decoder.dart';
import 'midi_file_validator.dart';
import 'verified_project_backup.dart';

/// Local, cross-platform ALL-to-MIDI recovery. Does not invoke Cubase or a
/// third-party executable and never overwrites a source project.
class LegacyAllConversionService {
  static Future<Map<String, Object?>> convert({
    required File original,
    required bool acknowledgeFidelityRisks,
    Directory? outputRoot,
  }) async {
    if (!acknowledgeFidelityRisks) {
      throw const FormatException(
        'Explicit acceptance of partial MIDI recovery is required',
      );
    }
    if (p.extension(original.path).toLowerCase() != '.all') {
      throw const FormatException(
        'This decoder supports .ALL only, not .ARR or CPR',
      );
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
      original.absolute.path,
    );
    if (await FileSystemEntity.type(original.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await original.length() > LegacyAllMidiDecoder.maxInputBytes) {
      throw const FileSystemException('Expected a bounded regular ALL file');
    }
    final bytes = await original.readAsBytes();
    final sourceHash = sha256.convert(bytes).toString();
    final decoded = LegacyAllMidiDecoder.decode(
      bytes,
      songName: p.basenameWithoutExtension(original.path),
    );
    final midi = MidiFileValidator.inspect(decoded.midi);
    if (midi.format != 1 ||
        midi.division != 480 ||
        midi.trackCount != decoded.tracks.length + 1 ||
        midi.noteCount != decoded.noteCount) {
      throw const FormatException('Recovered MIDI failed consistency checks');
    }
    final backup = await VerifiedProjectBackup.create(original);
    if (backup.sha256Digest != sourceHash || backup.length != bytes.length) {
      throw const FileSystemException('ALL source changed while decoding');
    }
    final root =
        (outputRoot ??
                Directory(
                  p.join(
                    original.parent.absolute.path,
                    '.project-repair-exports',
                  ),
                ))
            .absolute;
    if (p.split(root.path).contains('.project-repair-backups')) {
      throw const FileSystemException(
        'MIDI export cannot be inside managed backups',
      );
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(root.path);
    await root.create(recursive: true);
    final run = await root.createTemp('dpm-all-to-midi-');
    final staging = File(p.join(run.path, 'recovered.staging.mid'));
    final output = File(p.join(run.path, 'recovered.mid'));
    final reportFile = File(p.join(run.path, 'legacy-conversion-report.json'));
    try {
      await staging.writeAsBytes(decoded.midi, flush: true);
      final outputHash = sha256.convert(decoded.midi).toString();
      if ((await sha256.bind(staging.openRead()).first).toString() !=
              outputHash ||
          (await sha256.bind(original.openRead()).first).toString() !=
              sourceHash) {
        throw const FileSystemException(
          'ALL recovery staging verification failed',
        );
      }
      MidiFileValidator.inspect(await staging.readAsBytes());
      await staging.rename(output.path);
      final report = <String, Object?>{
        ...decoded.toJson(),
        'source': original.absolute.path,
        'source_sha256': sourceHash,
        'backup': backup.backupPath,
        'output': output.path,
        'output_sha256': outputHash,
        'report': reportFile.path,
        'midi_validation': midi.toJson(),
        'original_modified': false,
      };
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      return report;
    } catch (error) {
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'status': 'failed',
          'detail': error.toString(),
          'source_sha256': sourceHash,
          'verified_backup': backup.backupPath,
          'native_daw_reopen_verified': false,
        }),
        flush: true,
      );
      rethrow;
    }
  }
}
