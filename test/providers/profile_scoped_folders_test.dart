import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/repository/profile_repository.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/ui/widgets/folders_profile_picker.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

/// Settings > Project folders can edit a profile other than the active one.
void main() {
  group('per-profile providers', () {
    late Directory tempDir;
    late ProfileRepository profileRepo;
    late Profile solo;
    late Profile atlas;
    late ProjectRepository soloRepo;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await HiveTestHelper.setUp();
      final profilesBox = await Hive.openBox<Profile>('profiles');
      final settingsBox = await Hive.openBox<String>('settings');
      profileRepo = ProfileRepository(profilesBox: profilesBox, settingsBox: settingsBox);
      solo = await profileRepo.createProfile('Audio Crawler');
      atlas = await profileRepo.createProfile('ATLAS');
      await profileRepo.setCurrentProfileId(solo.id);
      soloRepo = await HiveTestHelper.createRepository(profileId: solo.id);
      container = ProviderContainer(overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profileRepo),
        repositoryProvider.overrideWith((ref) async => soloRepo),
      ]);
    });

    // Riverpod 3 pauses a provider nothing listens to; the settings page
    // watches these, so the test listens as it would.
    Future<T> read<T>(ProviderListenable<Future<T>> provider) {
      container.listen(provider, (_, _) {});
      return container.read(provider);
    }

    tearDown(() async {
      container.dispose();
      await HiveTestHelper.tearDown(tempDir);
    });

    test("the active profile's repository is the very one the app uses", () async {
      final repo = await read(repositoryForProfileProvider(solo.id).future);
      expect(repo, same(soloRepo));
    });

    test("another profile's folders are its own, and edits land there", () async {
      final atlasRepo = await read(repositoryForProfileProvider(atlas.id).future);
      expect(atlasRepo.profileId, atlas.id);

      await atlasRepo.addRoot(p.join(tempDir.path, 'Collabs', 'ATLAS'));

      expect(soloRepo.getRoots(), isEmpty, reason: 'the active profile is untouched');
      expect(
        (await read(scanRootsForProfileProvider(atlas.id).future)).single.path,
        p.join(tempDir.path, 'Collabs', 'ATLAS'),
      );
    });

    test('folder lists follow changes as they happen', () async {
      final seen = <int>[];
      container.listen(
        scanRootsForProfileProvider(atlas.id),
        (_, next) => seen.add(next.value?.length ?? -1),
        fireImmediately: true,
      );
      final atlasRepo = await read(repositoryForProfileProvider(atlas.id).future);
      await read(scanRootsForProfileProvider(atlas.id).future);
      // Let the stream start watching, as it has long before anyone clicks.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await atlasRepo.addRoot(p.join(tempDir.path, 'a'));
      await atlasRepo.addIgnoredPath(p.join(tempDir.path, 'a', 'old'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen.last, 1);
      final ignored =
          await read(ignoredPathsForProfileProvider(atlas.id).future);
      expect(ignored.single.path, p.join(tempDir.path, 'a', 'old'));
    });

    test("Recently deleted is each profile's own", () async {
      final atlasRepo = await read(repositoryForProfileProvider(atlas.id).future);
      await atlasRepo.projectsBox.put('x', TestFactories.makeProject(id: 'x'));
      await atlasRepo.deleteProjects(['x']);

      expect(
        (await read(recentlyDeletedProvider(atlas.id).future)).single.project.id,
        'x',
      );
      expect(await read(recentlyDeletedProvider(solo.id).future), isEmpty);
    });
  });

  group('FoldersProfilePicker', () {
    Future<List<String>> pump(WidgetTester tester, String selectedId) async {
      final picked = <String>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FoldersProfilePicker(
            profiles: const [
              (id: 'solo', name: 'Audio Crawler', active: true),
              (id: 'atlas', name: 'ATLAS', active: false),
            ],
            selectedId: selectedId,
            onChanged: picked.add,
          ),
        ),
      ));
      return picked;
    }

    testWidgets('shows the active profile as such, with no warning', (tester) async {
      await pump(tester, 'solo');
      expect(find.text('Audio Crawler (active)'), findsOneWidget);
      expect(find.byKey(const ValueKey('editing-other-profile')), findsNothing);
    });

    testWidgets('says so when editing another profile', (tester) async {
      await pump(tester, 'atlas');
      expect(find.byKey(const ValueKey('editing-other-profile')), findsOneWidget);
      expect(find.textContaining("editing ATLAS's folders"), findsOneWidget);
    });

    testWidgets('picking another profile reports it; the same one does nothing',
        (tester) async {
      final picked = await pump(tester, 'solo');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio Crawler (active)').last);
      await tester.pumpAndSettle();
      expect(picked, isEmpty);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ATLAS').last);
      await tester.pumpAndSettle();
      expect(picked, ['atlas']);
    });
  });
}
