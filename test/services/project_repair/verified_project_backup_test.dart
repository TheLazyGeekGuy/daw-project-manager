import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/verified_project_backup.dart';

void main() {
  test('backup is verified and source bytes remain unchanged', () async {
    final folder = await Directory.systemTemp.createTemp('repair-backup-test-');
    try {
      final original = File('${folder.path}/project.cpr');
      final content = List<int>.generate(4096, (i) => i % 251);
      await original.writeAsBytes(content);
      final result = await VerifiedProjectBackup.create(original);
      expect(result.length, content.length);
      expect(await original.readAsBytes(), content);
      expect(await File(result.backupPath).readAsBytes(), content);
      expect(result.backupPath, contains('.project-repair-backups'));
      expect(result.sha256Digest.length, 64);
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('missing source fails without manufacturing a backup', () async {
    final folder = await Directory.systemTemp.createTemp('repair-backup-missing-');
    try {
      expect(
        () => VerifiedProjectBackup.create(File('${folder.path}/absent.cpr')),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
