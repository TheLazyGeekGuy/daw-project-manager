import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';

void main() {
  test('supports independent release metadata and previous-version snapshots',
      () async {
    final root = await Directory.systemTemp.createTemp('dpm-release-');
    try {
      final store = ReleaseWorkspaceStore(root);
      final initial = await store.read('album-1');
      expect(initial['collection_type'], 'album');
      await store.save('album-1', {...initial, 'collection_type': 'ep'});
      expect((await store.read('album-1'))['collection_type'], 'ep');
      await store.save('album-1', {...initial, 'collection_type': 'single'});
      expect((await store.read('album-1'))['collection_type'], 'single');
      expect(root.listSync().where((e) => e.path.endsWith('.previous.json')),
          hasLength(1));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('rejects path traversal and conflicting release IDs', () async {
    final root = await Directory.systemTemp.createTemp('dpm-release-safe-');
    try {
      final store = ReleaseWorkspaceStore(root);
      expect(() => store.read('../private'), throwsFormatException);
      expect(() => store.save('a', {
        'release_id': 'b', 'schema_version': 1,
      }), throwsFormatException);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
