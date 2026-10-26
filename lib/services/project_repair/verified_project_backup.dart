import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Verified immutable backup for future repair operations.
///
/// This class does not modify the source or delete managed backups.
/// Writers must refuse to start unless [create] completed successfully.
class VerifiedProjectBackup {
  final String originalPath;
  final String backupPath;
  final String sha256Digest;
  final int length;

  const VerifiedProjectBackup._(
    this.originalPath,
    this.backupPath,
    this.sha256Digest,
    this.length,
  );

  static Future<VerifiedProjectBackup> create(
    File original, {
    Directory? backupDirectory,
  }) async {
    if (!await original.exists()) {
      throw const FileSystemException('Source project does not exist');
    }
    final originalStat = await original.stat();
    if (originalStat.type != FileSystemEntityType.file) {
      throw const FileSystemException('Expected a regular project file');
    }
    final sourcePath = p.normalize(original.absolute.path);
    final directory = backupDirectory ??
        Directory(p.join(p.dirname(sourcePath), '.project-repair-backups'));
    await directory.create(recursive: true);

    final sourceHash = await _digest(original);
    final sourceLength = await original.length();
    final originalName = p.basename(sourcePath);
    // createTemp generates a collision-safe directory without overwriting
    // an existing backup; FileMode.writeOnlyExclusive does not exist in Dart.
    final reserved = await directory.createTemp('backup-');
    final created = File(p.join(reserved.path, originalName));
    try {
      final sink = created.openWrite(mode: FileMode.writeOnly);
      await sink.addStream(original.openRead());
      await sink.flush();
      await sink.close();
      final verifiedLength = await created.length();
      final verifiedHash = await _digest(created);
      final unchangedHash = await _digest(original);
      if (verifiedLength != sourceLength ||
          verifiedHash != sourceHash ||
          unchangedHash != sourceHash) {
        throw const FileSystemException('Backup verification failed');
      }
      return VerifiedProjectBackup._(sourcePath, created.path, sourceHash, sourceLength);
    } catch (_) {
      // An incomplete copy is deliberately retained for forensic inspection.
      rethrow;
    }
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
