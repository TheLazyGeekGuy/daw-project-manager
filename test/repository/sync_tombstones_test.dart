import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/release.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/repository/sync_tombstones.dart';

import '../helpers/hive_test_helper.dart';
import '../helpers/test_factories.dart';

void main() {
  group('SyncTombstone', () {
    final t = SyncTombstone(
      id: 'a',
      kind: TombstoneKind.project,
      deletedAt: DateTime.utc(2026, 2, 1),
    );

    test('round-trips through JSON', () {
      final back = SyncTombstone.fromJson(t.toJson())!;
      expect(back.id, 'a');
      expect(back.kind, TombstoneKind.project);
      expect(back.deletedAt, t.deletedAt);
    });

    test('beats a copy changed before it, not one changed after', () {
      expect(t.beats(DateTime.utc(2026, 1, 1)), isTrue);
      expect(t.beats(DateTime.utc(2026, 3, 1)), isFalse);
      expect(t.beats(null), isTrue, reason: 'a release has no updatedAt');
    });

    test('skips malformed entries from a backup', () {
      final read = tombstonesFromJson([
        t.toJson(),
        {'id': 'b'},
        {'id': 'c', 'kind': 'planet', 'deletedAt': '2026-01-01'},
        'nonsense',
      ]);
      expect(read.map((e) => e.id), ['a']);
      expect(tombstonesFromJson(null), isEmpty);
    });

    test('one per profile: the same id deleted from two profiles is two', () {
      final inA = SyncTombstone(
        id: 'a',
        kind: TombstoneKind.project,
        deletedAt: DateTime.utc(2026, 2, 1),
        profileId: 'A',
      );
      final inB = SyncTombstone(
        id: 'a',
        kind: TombstoneKind.project,
        deletedAt: DateTime.utc(2026, 3, 1),
        profileId: 'B',
      );
      final merged = mergeTombstones({}, [inA, inB]);
      expect(merged.length, 2);
      expect(tombstoneFor(merged, 'a', 'A'), same(inA));
      expect(tombstoneFor(merged, 'a', 'C'), isNull);
      expect(SyncTombstone.fromJson(inA.toJson())!.profileId, 'A');
    });

    test('one naming no profile applies to every profile', () {
      expect(tombstoneFor({'a': t}, 'a', 'any-profile'), same(t));
    });

    test('merging keeps the later deletion of the same row', () {
      final later = SyncTombstone(
        id: 'a',
        kind: TombstoneKind.project,
        deletedAt: DateTime.utc(2026, 4, 1),
      );
      expect(mergeTombstones({'a': t}, [later])['a']!.deletedAt,
          later.deletedAt);
      expect(mergeTombstones({'a': later}, [t])['a']!.deletedAt,
          later.deletedAt);
    });
  });

  group('SyncTombstoneStore and the repository', () {
    late Directory tempDir;
    late ProjectRepository repo;

    setUp(() async {
      tempDir = await HiveTestHelper.setUp();
      repo = await HiveTestHelper.createRepository();
    });

    tearDown(() async {
      await HiveTestHelper.tearDown(tempDir);
    });

    test('drops tombstones older than a year', () async {
      final now = DateTime.utc(2027, 1, 1);
      await SyncTombstoneStore.putAll([
        SyncTombstone(
          id: 'ancient',
          kind: TombstoneKind.project,
          deletedAt: now.subtract(const Duration(days: 400)),
        ),
        SyncTombstone(
          id: 'recent',
          kind: TombstoneKind.project,
          deletedAt: now.subtract(const Duration(days: 10)),
        ),
      ], now: now);
      expect((await SyncTombstoneStore.all()).values.map((t) => t.id), ['recent']);
    });

    test('deleting projects permanently records them', () async {
      await repo.projectsBox.put('p', TestFactories.makeProject(id: 'p'));
      await repo.deleteProjectsPermanently(['p']);
      final t = (await SyncTombstoneStore.all()).values.single;
      expect(t.id, 'p');
      expect(t.kind, TombstoneKind.project);
      expect(t.profileId, repo.profileId, reason: 'names the profile it left');
    });

    test('deleting a release records it', () async {
      await repo.releasesBox.put(
        'r',
        Release(id: 'r', title: 'EP', trackIds: const []),
      );
      await repo.deleteRelease('r');
      final t = (await SyncTombstoneStore.all()).values.single;
      expect(t.id, 'r');
      expect(t.kind, TombstoneKind.release);
      expect(t.profileId, repo.profileId);
    });

    test('unstacking records the stack row it deletes', () async {
      final a = TestFactories.makeProject(id: 'a', filePath: '/songs/x/a.als');
      final b = TestFactories.makeProject(id: 'b', filePath: '/songs/x/b.als');
      await repo.projectsBox.putAll({'a': a, 'b': b});
      final stack = await repo.stackProjects(memberIds: ['a', 'b']);
      await repo.unstack(stack.id);
      final ids = (await SyncTombstoneStore.all()).values.map((t) => t.id);
      expect(ids, contains(stack.id));
      expect(ids, isNot(contains('a')),
          reason: 'members are kept, not deleted');
    });

    test('saving a project records nothing', () async {
      await repo.projectsBox.put('p', TestFactories.makeProject(id: 'p'));
      expect(await SyncTombstoneStore.all(), isEmpty);
    });
  });
}
