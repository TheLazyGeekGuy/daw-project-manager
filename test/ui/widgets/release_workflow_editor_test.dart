import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/ui/widgets/release_workflow_editor.dart';

void main() {
  testWidgets('edits release type and stable artist identifiers',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp('dpm-workflow-ui-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ReleaseWorkspaceStore(directory);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReleaseWorkflowEditor(releaseId: 'release-1', store: store),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Release type'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'artist-1, artist-2');
    await tester.tap(find.text('Validate and save'));
    await tester.pumpAndSettle();
    final saved = await store.read('release-1');
    expect(saved['artist_ids'], ['artist-1', 'artist-2']);
    expect(saved['collection_type'], 'album');
  });
}
