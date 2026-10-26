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
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final originalName = p.basename(sourcePath);
    File? created;
    try {
      for (var attempt = 0; attempt < 10; attempt++) {
        final path = p.join(directory.path, '${originalName}.${stamp}_${attempt}.backup');
        final target = File(path);
        try {
          final sink = target.openWrite(mode: FileMode.writeOnlyExclusive);
          created = target;
          await sink.addStream(original.openRead());
          await sink.flush();
          await sink.close();
          break;
        } on FileSystemException {
          if (await target.exists()) rethrow;
          rethrow;
        }
      }
      if (created == null) throw const FileSystemException('Backup name exhausted');
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
