import 'dart:convert';

import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_factories.dart';

void main() {
  final solo = Profile(id: 'solo', name: 'Audio Crawler', createdAt: DateTime(2025));
  final duo = Profile(id: 'duo', name: 'Crawler & Friends', createdAt: DateTime(2025));
  final now = DateTime.utc(2026, 10, 18, 12);

  group('buildCompanionIndex', () {
    test('lists every profile\'s projects with their to-dos', () {
      final index = buildCompanionIndex([
        CompanionProfileProjects(solo, [
          TestFactories.makeProject(
            id: 'p1',
            filePath: p.join('music', 'Teardrop.cpr'),
            fileName: 'Teardrop.cpr',
            dawType: 'Cubase',
            todos: [TestFactories.makeTodo(id: 't1', text: 'Fix kick')],
          ),
        ]),
        CompanionProfileProjects(duo, [
          TestFactories.makeProject(id: 'p2', fileName: 'Bounce.flp', dawType: null),
        ]),
      ], generatedAt: now, appVersion: '2.10.0');

      expect(index['schema'], 1);
      expect(index['generatedAt'], '2026-10-18T12:00:00.000Z');
      expect(index['app'], {'version': '2.10.0'});

      final projects = index['projects'] as List;
      expect(projects, hasLength(2));
      expect(projects[0]['id'], 'p1');
      expect(projects[0]['profileId'], 'solo');
      expect(projects[0]['profileName'], 'Audio Crawler');
      expect(projects[0]['name'], 'Teardrop');
      expect(projects[0]['filePath'], p.join('music', 'Teardrop.cpr'));
      expect(projects[0]['dawType'], 'Cubase');
      expect(projects[0]['todos'], [
        {'id': 't1', 'text': 'Fix kick', 'completed': false, 'createdAt': DateTime(2025, 1, 10).toUtc().toIso8601String()},
      ]);
      expect(projects[1]['profileId'], 'duo');
      expect(projects[1]['dawType'], '');
    });

    test('leaves out stacks and archived projects; members carry the stack\'s to-dos', () {
      final stack = TestFactories.makeProject(
        id: 'stack',
        isVirtual: true,
        memberProjectIds: ['v1', 'v2'],
        todos: [TestFactories.makeTodo(id: 'shared', text: 'Shared to-do')],
      );
      final v1 = TestFactories.makeProject(id: 'v1', fileName: 'Song v1.als', stackId: 'stack',
          todos: [TestFactories.makeTodo(id: 'dormant', text: 'Dormant own to-do')]);
      final v2 = TestFactories.makeProject(id: 'v2', fileName: 'Song v2.als', stackId: 'stack');
      final archived = TestFactories.makeProject(id: 'old', archivePath: p.join('archive', 'old.zip'));

      final projects = buildCompanionIndex([
        CompanionProfileProjects(solo, [stack, v1, v2, archived]),
      ], generatedAt: now, appVersion: '1')['projects'] as List;

      expect(projects.map((e) => e['id']), ['v1', 'v2']);
      for (final member in projects) {
        expect((member['todos'] as List).map((t) => t['id']), ['shared']);
      }
    });

    test('the fingerprint ignores the time, so an unchanged library is not rewritten', () {
      final library = [CompanionProfileProjects(solo, [TestFactories.makeProject(id: 'p1')])];
      final a = buildCompanionIndex(library, generatedAt: now, appVersion: '1');
      final b = buildCompanionIndex(library, generatedAt: now.add(const Duration(minutes: 5)), appVersion: '1');
      expect(companionIndexFingerprint(a), companionIndexFingerprint(b));

      final c = buildCompanionIndex([
        CompanionProfileProjects(solo, [TestFactories.makeProject(id: 'p1', todos: [TestFactories.makeTodo()])]),
      ], generatedAt: now, appVersion: '1');
      expect(companionIndexFingerprint(c), isNot(companionIndexFingerprint(a)));
    });
  });

  group('plugin releases', () {
    test('the index names the newest release when one is known', () {
      final library = [CompanionProfileProjects(solo, [])];
      final withRelease = buildCompanionIndex(library,
          generatedAt: now,
          appVersion: '1',
          latestRelease: const CompanionRelease('0.2.0', 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0'));
      expect(withRelease['companion'], {
        'latestVersion': '0.2.0',
        'releaseUrl': 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0',
      });
      expect(buildCompanionIndex(library, generatedAt: now, appVersion: '1').containsKey('companion'), isFalse);
    });

    test('a new release changes the fingerprint, so the index is rewritten', () {
      final library = [CompanionProfileProjects(solo, [])];
      final before = buildCompanionIndex(library, generatedAt: now, appVersion: '1');
      final after = buildCompanionIndex(library,
          generatedAt: now, appVersion: '1', latestRelease: const CompanionRelease('0.2.0', 'u'));
      expect(companionIndexFingerprint(after), isNot(companionIndexFingerprint(before)));
    });

    test('GitHub\'s latest-release answer is read', () {
      final release = parseCompanionRelease({
        'tag_name': 'v0.2.0',
        'html_url': 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0',
      })!;
      expect(release.version, '0.2.0');
      expect(release.url, 'https://github.com/bandpassrecords/dpm-companion/releases/tag/v0.2.0');

      expect(parseCompanionRelease({'tag_name': 'nightly', 'html_url': 'u'}), isNull);
      expect(parseCompanionRelease({'tag_name': 'v1.2', 'html_url': 'u'}), isNull);
      expect(parseCompanionRelease({'html_url': 'u'}), isNull);
    });
  });

  test('the launch hint names the project, its profile and when it opened', () {
    final hint = buildCompanionLaunchHint(
      profileId: 'solo',
      project: TestFactories.makeProject(id: 'p1', filePath: p.join('music', 'a.cpr')),
      launchedAt: now,
    );
    expect(hint, {
      'projectId': 'p1',
      'profileId': 'solo',
      'filePath': p.join('music', 'a.cpr'),
      'launchedAt': '2026-10-18T12:00:00.000Z',
    });
  });

  group('parseCompanionMessage', () {
    String message(String type, Map<String, dynamic> payload, {Object? project = const {'id': 'p1', 'profileId': 'solo'}}) =>
        jsonEncode({
          'schema': 1,
          'id': 'm1',
          'type': type,
          'createdAt': '2026-10-18T12:00:05.000Z',
          'plugin': {'version': '0.1.0', 'instanceId': 'i'},
          'host': {'name': 'Cubase', 'windowTitle': 'x'},
          'project': project,
          'payload': payload,
        });

    test('reads a new to-do, as one trimmed line', () {
      final m = parseCompanionMessage(message('todo.add', {
        'todoId': 't9',
        'text': '  [01:23]  Vocal\ttoo loud \n',
        'createdAt': '2026-10-18T12:00:04.000Z',
      }));
      expect(m, isA<CompanionTodoAdd>());
      final add = m as CompanionTodoAdd;
      expect(add.project!.profileId, 'solo');
      expect(add.project!.projectId, 'p1');
      expect(add.todoId, 't9');
      expect(add.text, '[01:23] Vocal too loud');
      expect(add.todoCreatedAt, DateTime.utc(2026, 10, 18, 12, 0, 4));
    });

    test('reads a tick, a capture and a hello', () {
      final tick = parseCompanionMessage(message('todo.setCompleted', {'todoId': 't1', 'completed': true}));
      expect((tick as CompanionTodoSetCompleted).completed, isTrue);

      final capture = parseCompanionMessage(message('capture.ready', {
        'file': 'captures/Song_1.flac',
        'durationSeconds': 60,
        'capturedAt': '2026-10-18T12:00:00.000Z',
      }));
      expect((capture as CompanionCaptureReady).file, 'captures/Song_1.flac');
      expect(capture.durationSeconds, 60.0);

      expect(parseCompanionMessage(message('session.hello', {'linkedByUser': true})), isA<CompanionHello>());
    });

    test('an unlinked message has no project', () {
      final m = parseCompanionMessage(message('capture.ready', {'file': 'captures/x.flac'}, project: null));
      expect(m!.project, isNull);
    });

    test('an unknown type is kept as unknown, to be dropped', () {
      final m = parseCompanionMessage(message('marker.add', {}));
      expect((m as CompanionUnknownMessage).type, 'marker.add');
    });

    test('garbage and incomplete messages are not messages', () {
      expect(parseCompanionMessage('not json'), isNull);
      expect(parseCompanionMessage('[1,2]'), isNull);
      expect(parseCompanionMessage(jsonEncode({'type': 'todo.add'})), isNull);
      expect(parseCompanionMessage(message('todo.add', {'todoId': 't1', 'text': '   '})), isNull);
      expect(parseCompanionMessage(message('todo.add', {'text': 'no id'})), isNull);
      expect(parseCompanionMessage(message('todo.setCompleted', {'todoId': 't1', 'completed': 'yes'})), isNull);
    });

    test('an over-long to-do is cut', () {
      final m = parseCompanionMessage(message('todo.add', {'todoId': 't1', 'text': 'a' * 900})) as CompanionTodoAdd;
      expect(m.text.length, companionMaxTodoLength);
    });
  });

  group('applying to-do messages', () {
    final add = CompanionTodoAdd('m1', now, const CompanionProjectRef('solo', 'p1'),
        todoId: 't9', text: 'Automate the filter', todoCreatedAt: now);

    test('a new to-do keeps the plugin\'s id, so the plugin can see it arrived', () {
      final project = TestFactories.makeProject(todos: [TestFactories.makeTodo(id: 't1')]);
      final updated = applyCompanionTodoAdd(project, add)!;
      expect(updated.todos.map((t) => t.id), ['t1', 't9']);
      expect(updated.todos.last.text, 'Automate the filter');
      expect(updated.todos.last.completed, isFalse);
      expect(updated.todos.last.createdAt, now);
    });

    test('applying the same add twice changes nothing', () {
      final once = applyCompanionTodoAdd(TestFactories.makeProject(todos: []), add)!;
      expect(applyCompanionTodoAdd(once, add), isNull);
    });

    test('a tick sets completed; a repeat or a deleted to-do changes nothing', () {
      final project = TestFactories.makeProject(todos: [TestFactories.makeTodo(id: 't1')]);
      final tick = CompanionTodoSetCompleted('m2', now, null, todoId: 't1', completed: true);

      final ticked = applyCompanionTodoSetCompleted(project, tick)!;
      expect(ticked.todos.single.completed, isTrue);
      expect(applyCompanionTodoSetCompleted(ticked, tick), isNull);

      final gone = CompanionTodoSetCompleted('m3', now, null, todoId: 'deleted', completed: true);
      expect(applyCompanionTodoSetCompleted(project, gone), isNull);
    });

    test('a stack member\'s to-dos are its stack\'s', () {
      final stack = TestFactories.makeProject(id: 'stack', isVirtual: true);
      final member = TestFactories.makeProject(id: 'v1', stackId: 'stack');
      final loose = TestFactories.makeProject(id: 'p1');
      final orphan = TestFactories.makeProject(id: 'v9', stackId: 'gone');

      expect(companionOwnerOf(member, [stack, member, loose]).id, 'stack');
      expect(companionOwnerOf(loose, [stack, member, loose]).id, 'p1');
      expect(companionOwnerOf(orphan, [stack, orphan]).id, 'v9');
    });
  });

  group('companionMayReplacePreview', () {
    final dir = p.join('data', 'preview_songs', 'companion');
    final captured = DateTime(2026, 10, 18, 12);

    test('fills an empty preview, and replaces an earlier capture', () {
      expect(companionMayReplacePreview(TestFactories.makeProject(), companionPreviewDir: dir, capturedAt: captured), isTrue);
      expect(
        companionMayReplacePreview(
          TestFactories.makeProject(previewSongPath: p.join(dir, 'p1', 'old.flac')),
          companionPreviewDir: dir,
          capturedAt: captured,
        ),
        isTrue,
      );
    });

    test('never replaces a preview the user picked', () {
      final picked = TestFactories.makeProject(previewSongPath: p.join('music', 'Final Master.wav'));
      expect(
        companionMayReplacePreview(picked,
            companionPreviewDir: dir, capturedAt: captured, currentPreviewModifiedAt: DateTime(2020)),
        isFalse,
      );
    });

    test('replaces an auto-detected mixdown only when the capture is newer', () {
      final mixdown = p.join('music', 'Song Mixdown.wav');
      final project = TestFactories.makeProject(previewSongPath: mixdown, previewSongAutoPath: mixdown);

      expect(
        companionMayReplacePreview(project,
            companionPreviewDir: dir, capturedAt: captured, currentPreviewModifiedAt: DateTime(2026, 3, 1)),
        isTrue,
      );
      expect(
        companionMayReplacePreview(project,
            companionPreviewDir: dir, capturedAt: captured, currentPreviewModifiedAt: DateTime(2026, 10, 18, 13)),
        isFalse,
      );
      expect(companionMayReplacePreview(project, companionPreviewDir: dir, capturedAt: captured), isFalse);
    });
  });
}
