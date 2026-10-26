import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cubase_lossless_container.dart';
import 'verified_project_backup.dart';

/// Creates a verified backup, an unchanged reconstructed project and opaque
/// chunk evidence in a new managed workspace. Never edits or replaces source.
class CubasePreservationService {
  Future<Map<String, Object?>> preserve(
    File source, {
    Directory? outputRoot,
  }) async {
    await VerifiedProjectBackup.ensureNoSymlinkComponents(source.absolute.path);
    if (await source.length() > 256 * 1024 * 1024) {
      throw const FormatException('CPR exceeds the preservation size limit');
    }
    final original = await source.readAsBytes();
    final container = CubaseLosslessContainer.parse(original);
    final backup = await VerifiedProjectBackup.create(source);
    if (backup.sha256Digest != container.sourceSha256) {
      throw const FileSystemException('Source changed before preservation');
    }
    final root =
        outputRoot ??
        Directory(
          p.join(source.absolute.parent.path, '.project-repair-exports'),
        );
    await VerifiedProjectBackup.ensureNoSymlinkComponents(root.absolute.path);
    await root.create(recursive: true);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(root.absolute.path);
    final workspace = await root.createTemp('cpr-preservation-');
    final reportFile = File(p.join(workspace.path, 'report.json'));
    final report = <String, Object?>{
      ...container.verificationReport(),
      'source_path': source.absolute.path,
      'backup_path': backup.backupPath,
      'workspace_path': workspace.path,
      'status': 'staging',
    };
    try {
      // Keep arbitrary source names separate from reserved report/chunk paths.
      // A CPR identified by its bytes may itself be named report.json or chunks.
      final reconstructed = await Directory(
        p.join(workspace.path, 'reconstructed'),
      ).create();
      final output = File(p.join(reconstructed.path, p.basename(source.path)));
      await output.writeAsBytes(container.serializeUnchanged(), flush: true);
      if (await _digest(output) != backup.sha256Digest) {
        throw const FileSystemException(
          'Reconstructed CPR failed verification',
        );
      }
      final chunks = await Directory(p.join(workspace.path, 'chunks')).create();
      final paths = <String>[];
      for (var i = 0; i < container.manifest.chunks.length; i++) {
        // Names deliberately exclude untrusted raw chunk tags.
        final file = File(
          p.join(chunks.path, '${i.toString().padLeft(5, '0')}.bin'),
        );
        final payload = container.chunkPayload(i);
        await file.writeAsBytes(payload, flush: true);
        if (await _digest(file) != sha256.convert(payload).toString()) {
          throw const FileSystemException(
            'Preserved chunk failed verification',
          );
        }
        paths.add(p.relative(file.path, from: workspace.path));
      }
      await VerifiedProjectBackup.ensureNoSymlinkComponents(
        source.absolute.path,
      );
      if (await _digest(source) != backup.sha256Digest ||
          await _digest(File(backup.backupPath)) != backup.sha256Digest) {
        throw const FileSystemException(
          'Source or backup changed during preservation',
        );
      }
      report.addAll({
        'status': 'preserved',
        'reconstructed_path': output.path,
        'chunk_paths': paths,
        'original_modified': false,
      });
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      return report;
    } catch (error) {
      report.addAll({
        'status': 'failed',
        'failure_type': '${error.runtimeType}',
      });
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      rethrow;
    }
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
