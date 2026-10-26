import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/release_catalog_store.dart';
import 'package:daw_project_manager/services/release_workspace_store.dart';
import 'package:daw_project_manager/ui/widgets/release_workflow_editor.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

Future<void> _io(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(
    find.byType(LinearProgressIndicator),
    findsNothing,
    reason: 'Release operation must complete rather than leaving the form busy',
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

Future<void> _open(WidgetTester tester, String section) async {
  final tile = find.byKey(ValueKey('section-$section'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _button(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.runAsync(() => tester.tap(button));
  await _io(tester);
}

Future<void> _mount(
  WidgetTester tester,
  ReleaseWorkspaceStore store, {
  List<Map<String, dynamic>> tracks = const [],
  Locale locale = const Locale('en'),
  bool syncNativeRelease = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReleaseWorkflowEditor(
            releaseId: 'release-1',
            store: store,
            initialTracks: tracks,
            syncNativeRelease: syncNativeRelease,
            initialTitle: syncNativeRelease ? 'Native title' : null,
            initialReleaseDate: syncNativeRelease ? '2026-11-02' : null,
            availableProjects: const [
              {'id': 'project-1', 'title': 'First project'},
            ],
          ),
        ),
      ),
    ),
  );
  await _io(tester);
}

void main() {
  late Directory directory;
  late ReleaseWorkspaceStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dpm-workflow-ui-');
    store = ReleaseWorkspaceStore(directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  testWidgets(
    'native artist form persists a profile artist and a release credit',
    (tester) async {
      await _mount(tester, store);
      expect(find.text('Release type'), findsOneWidget);
      expect(find.text('Advanced JSON editor'), findsNothing);
      await _open(tester, 'artists');
      await _button(tester, 'add-artists');
      await tester.enterText(
        find.byKey(const ValueKey('field-name')),
        'North Window',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-aliases')),
        'NW, Northern Window',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-roles')),
        'producer, composer',
      );
      await _button(tester, 'apply-record');
      await _button(tester, 'edit-release-summary');
      await tester.tap(find.widgetWithText(FilterChip, 'North Window'));
      await _button(tester, 'apply-record');
      await _button(tester, 'save-workspace');
      await _io(tester);
      expect(find.byKey(const ValueKey('release-error')), findsNothing);
      final catalog = await tester.runAsync(
        () => ReleaseCatalogStore(directory).read(),
      );
      final workspace = await tester.runAsync(() => store.read('release-1'));
      final artist = (catalog!['artists'] as List).single as Map;
      expect(artist['name'], 'North Window');
      expect(artist['aliases'], ['NW', 'Northern Window']);
      expect(artist['updated_at'], endsWith('Z'));
      expect(workspace!['artist_ids'], [artist['id']]);
      expect(workspace['schema_version'], 2);
    },
  );

  testWidgets(
    'ordered linked tracks survive save and invalid ISRC is rejected',
    (tester) async {
      await _mount(
        tester,
        store,
        tracks: const [
          {'id': 'track-1', 'title': 'First', 'project_id': 'project-1'},
          {'id': 'track-2', 'title': 'Second'},
        ],
      );
      await _open(tester, 'tracks');
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();
      await _button(tester, 'add-tracks');
      await tester.enterText(
        find.byKey(const ValueKey('field-title')),
        'Bad ISRC',
      );
      await tester.enterText(
        find.byKey(const ValueKey('field-isrc')),
        'invalid',
      );
      await _button(tester, 'apply-record');
      expect(find.byKey(const ValueKey('release-error')), findsOneWidget);
      await _button(tester, 'save-workspace');
      await _io(tester);
      final workspace = await tester.runAsync(() => store.read('release-1'));
      final tracks = workspace!['tracks'] as List;
      expect(tracks.map((e) => e['id']), ['track-2', 'track-1']);
      expect(tracks.last['project_id'], 'project-1');
    },
  );

  testWidgets('file form verifies an asset without changing its bytes', (
    tester,
  ) async {
    final source = File(p.join(directory.path, 'master.wav'));
    await tester.runAsync(() => source.writeAsBytes([1, 2, 3, 4]));
    await _mount(tester, store);
    await _open(tester, 'assets');
    await _button(tester, 'add-assets');
    await tester.enterText(
      find.byKey(const ValueKey('field-title')),
      'Master v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-path')),
      source.path,
    );
    await _button(tester, 'apply-record');
    await tester.ensureVisible(find.text('Verify file'));
    await tester.tap(find.text('Verify file'));
    await _io(tester);
    await _button(tester, 'save-workspace');
    await _io(tester);
    final workspace = await tester.runAsync(() => store.read('release-1'));
    final asset = (workspace!['assets'] as List).single as Map;
    expect(asset['validation'], 'verified');
    expect(asset['sha256'], hasLength(64));
    expect(await tester.runAsync(source.readAsBytes), [1, 2, 3, 4]);
  });

  testWidgets(
    'French controls and save conflict retain the other writer data',
    (tester) async {
      await tester.runAsync(
        () async => store.save('release-1', await store.read('release-1')),
      );
      await _mount(tester, store, locale: const Locale('fr'));
      expect(find.text('Type de publication'), findsOneWidget);
      await tester.runAsync(() async {
        final other = await store.read('release-1');
        await store.save('release-1', {
          ...other,
          'title': 'Saved elsewhere',
        }, expectedRevision: other['revision'] as int);
      });
      await _button(tester, 'save-workspace');
      await _io(tester);
      expect(find.byKey(const ValueKey('release-error')), findsOneWidget);
      final saved = await tester.runAsync(() => store.read('release-1'));
      expect(saved!['title'], 'Saved elsewhere');
    },
  );

  testWidgets('artist used by another release cannot be removed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final catalog = ReleaseCatalogStore(directory);
      await catalog.save({
        ...await catalog.read(),
        'artists': [
          {'id': 'artist-1', 'name': 'Shared artist'},
        ],
      });
      await store.save('release-other', {
        ...await store.read('release-other'),
        'artist_ids': ['artist-1'],
      });
    });
    await _mount(tester, store);
    await _open(tester, 'artists');
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Remove')),
    );
    await _io(tester);
    expect(find.byKey(const ValueKey('release-error')), findsOneWidget);
    expect(find.textContaining('release-other'), findsOneWidget);
    final saved = await tester.runAsync(
      () => ReleaseCatalogStore(directory).read(),
    );
    expect((saved!['artists'] as List).single['id'], 'artist-1');
  });

  testWidgets(
    'deletion records a tombstone and freezes untouched legacy clocks',
    (tester) async {
      const prior = '2026-01-01T12:00:00.000Z';
      await tester.runAsync(() async {
        final catalog = ReleaseCatalogStore(directory);
        await catalog.save({
          ...await catalog.read(),
          'updated_at': prior,
          'artists': [
            {'id': 'remove-me', 'name': 'Unused artist'},
            {'id': 'keep-me', 'name': 'Retained artist'},
          ],
        }, preserveTimestamps: true);
      });
      await _mount(tester, store);
      await _open(tester, 'artists');
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Remove')),
      );
      await _io(tester);
      await _button(tester, 'save-workspace');
      final saved = await tester.runAsync(
        () => ReleaseCatalogStore(directory).read(),
      );
      expect((saved!['artists'] as List).single['id'], 'keep-me');
      expect((saved['artists'] as List).single['updated_at'], prior);
      expect(saved['deleted_records']['artists']['remove-me'], endsWith('Z'));
    },
  );

  testWidgets(
    'native bridge preserves legacy project links and clears summary',
    (tester) async {
      await tester.runAsync(() async {
        await store.save('release-1', {
          ...await store.read('release-1'),
          'title': 'Old title',
          'description': 'Description removed in the native release',
          'release_date': '2025-01-01',
          'tracks': [
            {'id': 'project-1', 'title': 'Legacy recording'},
          ],
        });
      });
      await _mount(
        tester,
        store,
        syncNativeRelease: true,
        tracks: const [
          {
            'id': 'project-1',
            'project_id': 'project-1',
            'title': 'Native project',
          },
        ],
      );
      await _button(tester, 'save-workspace');
      final saved = await tester.runAsync(() => store.read('release-1'));
      expect(saved!['title'], 'Native title');
      expect(saved['description'], isNull);
      expect(saved['release_date'], '2026-11-02');
      expect((saved['tracks'] as List).single['project_id'], 'project-1');
      expect((saved['tracks'] as List).single['title'], 'Legacy recording');
    },
  );
}
