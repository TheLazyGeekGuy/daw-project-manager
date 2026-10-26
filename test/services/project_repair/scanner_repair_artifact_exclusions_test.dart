import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/scanner_service.dart';

void main() {
  test('never indexes managed backups or unverified conversion exports',
      () async {
    final root = await Directory.systemTemp.createTemp('dpm-scan-repair-');
    try {
      final real = File('${root.path}/Album/song.cpr');
      await real.parent.create(recursive: true);
      await real.writeAsString('original user session');
      final backup = File(
        '${root.path}/.project-repair-backups/backup-000/song.cpr',
      );
      await backup.parent.create(recursive: true);
      await backup.writeAsString('protected backup');
      final export = File(
        '${root.path}/.project-repair-exports/dpm-dawvert-000/converted.rpp',
      );
      await export.parent.create(recursive: true);
      await export.writeAsString('unverified conversion');

      final scanner = ScannerService();
      final paths = await scanner.scanDirectory(root.path)
          .map((entity) => entity.path).toList();
      expect(paths, [real.path]);
      final shallow = await scanner.scanDirectoryShallow(root.path)
          .map((result) => result.file.path).toList();
      expect(shallow, [real.path]);

      expect(await backup.readAsString(), 'protected backup');
      expect(await export.readAsString(), 'unverified conversion');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
