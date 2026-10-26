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
  test('repeated backups never overwrite earlier copies', () async {
    final folder = await Directory.systemTemp.createTemp('repair-repeat-');
    try {
      final original = File('${folder.path}/song.cpr');
      await original.writeAsString('first state');
      final first = await VerifiedProjectBackup.create(original);
      await original.writeAsString('second state');
      final second = await VerifiedProjectBackup.create(original);

      expect(first.backupPath, isNot(second.backupPath));
      expect(await File(first.backupPath).readAsString(), 'first state');
      expect(await File(second.backupPath).readAsString(), 'second state');
      expect(first.sha256Digest, isNot(second.sha256Digest));
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('refuses symlinked source paths', () async {
    if (Platform.isWindows) return;
    final folder = await Directory.systemTemp.createTemp('repair-link-test-');
    try {
      final original = File('${folder.path}/original.cpr');
      await original.writeAsString('immutable');
      final link = Link('${folder.path}/linked.cpr');
      await link.create(original.path);
      expect(
        () => VerifiedProjectBackup.create(File(link.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await original.readAsString(), 'immutable');
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('does not copy an existing managed backup into another backup', () async {
    final folder = await Directory.systemTemp.createTemp('repair-nesting-test-');
    try {
      final source = File('${folder.path}/song.cpr');
      await source.writeAsString('initial');
      final first = await VerifiedProjectBackup.create(source);
      expect(
        () => VerifiedProjectBackup.create(File(first.backupPath)),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await folder.delete(recursive: true);
    }
  });

}
