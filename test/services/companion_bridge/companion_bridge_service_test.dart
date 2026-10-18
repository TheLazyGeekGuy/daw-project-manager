import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_bridge_service.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_factories.dart';

/// An in-memory library: the bridge's whole conversation with the plugin is
/// tested against a temp folder and plain lists, no Hive.
class FakeLibrary implements CompanionLibrary {
  FakeLibrary(this.profiles);

  final Map<Profile, List<MusicProject>> profiles;
  final saves = <(String, MusicProject)>[];

  @override
  Future<List<CompanionProfileProjects>> load() async =>
      [for (final e in profiles.entries) CompanionProfileProjects(e.key, List.of(e.value))];

  @override
  Future<void> saveProject(String profileId, MusicProject project) async {
    saves.add((profileId, project));
    final list = profiles.entries.firstWhere((e) => e.key.id == profileId).value;
    final i = list.indexWhere((x) => x.id == project.id);
    list[i] = project;
  }

  MusicProject project(String profileId, String id) =>
      profiles.entries.firstWhere((e) => e.key.id == profileId).value.firstWhere((x) => x.id == id);
}

void main() {
  late Directory tmp;
  late String bridgeDir;
  late String previewDir;
  late FakeLibrary library;
  late CompanionBridgeService bridge;
  var clock = DateTime.utc(2026, 10, 18, 12);

  final solo = Profile(id: 'solo', name: 'Solo', createdAt: DateTime(2025));
  final duo = Profile(id: 'duo', name: 'Duo', createdAt: DateTime(2025));

  var sequence = 0;
  Future<File> drop(String type, Map<String, dynamic> payload, {String profileId = 'solo', String projectId = 'p1'}) async {
    final file = File(p.join(bridgeDir, 'outbox',
        '20261018T120000000Z-${(sequence++).toString().padLeft(6, '0')}-abcd1234.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'schema': 1,
      'id': 'm$sequence',
      'type': type,
      'createdAt': '2026-10-18T12:00:00.000Z',
      'project': {'id': projectId, 'profileId': profileId},
      'payload': payload,
    }));
    return file;
  }

  Future<File> capture(String name, {String content = 'flac'}) async {
    final file = File(p.join(bridgeDir, 'captures', name));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('companion_bridge_test');
    bridgeDir = p.join(tmp.path, 'plugin_bridge');
    previewDir = p.join(tmp.path, 'preview_songs');
    sequence = 0;
    clock = DateTime.utc(2026, 10, 18, 12);
    library = FakeLibrary({
      solo: [
        TestFactories.makeProject(id: 'p1', fileName: 'Teardrop.cpr', todos: [TestFactories.makeTodo(id: 't1')]),
        TestFactories.makeProject(id: 'stack', isVirtual: true, memberProjectIds: ['v1']),
        TestFactories.makeProject(id: 'v1', fileName: 'Song v1.als', stackId: 'stack'),
      ],
      // The same id in another profile: must never be touched by solo's messages.
      duo: [TestFactories.makeProject(id: 'p1', fileName: 'Duo copy.cpr')],
    });
    bridge = CompanionBridgeService(
      library: library,
      bridgeDir: bridgeDir,
      previewSongsDir: previewDir,
      appVersion: '2.10.0',
      clock: () => clock,
    );
  });

  tearDown(() async {
    bridge.stop();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('index.json', () {
    test('is written whole, and rewritten only when the library changes', () async {
      expect(await bridge.writeIndex(), isTrue);
      final index = jsonDecode(await bridge.indexFile.readAsString()) as Map<String, dynamic>;
      expect(index['schema'], 1);
      expect((index['projects'] as List).map((e) => '${e['profileId']}/${e['id']}'), ['solo/p1', 'solo/v1', 'duo/p1']);
      expect(File('${bridge.indexFile.path}.tmp').existsSync(), isFalse);

      clock = clock.add(const Duration(seconds: 3));
      expect(await bridge.writeIndex(), isFalse);

      await library.saveProject('solo', library.project('solo', 'p1').copyWith(todos: []));
      expect(await bridge.writeIndex(), isTrue);
    });

    test('is rewritten if someone deleted it', () async {
      await bridge.writeIndex();
      await bridge.indexFile.delete();
      expect(await bridge.writeIndex(), isTrue);
    });
  });

  group('outbox', () {
    test('a new to-do lands on the right profile\'s project, and the message is deleted', () async {
      final file = await drop('todo.add', {'todoId': 't9', 'text': 'Automate the filter'});
      expect(await bridge.processOutbox(), 1);

      expect(library.project('solo', 'p1').todos.map((t) => t.id), ['t1', 't9']);
      expect(library.project('duo', 'p1').todos, isEmpty);
      expect(await file.exists(), isFalse);
    });

    test('messages are applied in file-name order', () async {
      await drop('todo.add', {'todoId': 't9', 'text': 'New'});
      await drop('todo.setCompleted', {'todoId': 't9', 'completed': true});
      await drop('todo.setCompleted', {'todoId': 't9', 'completed': false});
      await drop('todo.setCompleted', {'todoId': 't9', 'completed': true});

      await bridge.processOutbox();
      expect(library.project('solo', 'p1').todos.last.completed, isTrue);
    });

    test('a stack member\'s to-do goes to its stack', () async {
      await drop('todo.add', {'todoId': 't5', 'text': 'Shared'}, projectId: 'v1');
      await bridge.processOutbox();
      expect(library.project('solo', 'stack').todos.single.id, 't5');
      expect(library.project('solo', 'v1').todos, isEmpty);
    });

    test('replays, unknown projects, unknown types and garbage change nothing but are cleared', () async {
      await drop('todo.add', {'todoId': 't1', 'text': 'Already there'});
      await drop('todo.add', {'todoId': 'x', 'text': 'Nowhere'}, projectId: 'gone');
      await drop('marker.add', {});
      final garbage = File(p.join(bridgeDir, 'outbox', '20261018T130000000Z-000000-ffffffff.json'));
      await garbage.writeAsString('{ not json');
      final partial = File(p.join(bridgeDir, 'outbox', 'still-writing.tmp'));
      await partial.writeAsString('{');

      expect(await bridge.processOutbox(), 0);
      expect(library.saves, isEmpty);
      final left = Directory(p.join(bridgeDir, 'outbox')).listSync().map((e) => p.basename(e.path));
      expect(left, ['still-writing.tmp']);
    });

    test('a tick forces a fresh index so the plugin sees it arrived', () async {
      await bridge.writeIndex();
      final before = jsonDecode(await bridge.indexFile.readAsString())['generatedAt'];

      clock = clock.add(const Duration(seconds: 5));
      await drop('todo.setCompleted', {'todoId': 't1', 'completed': true});
      await bridge.tick();

      final index = jsonDecode(await bridge.indexFile.readAsString()) as Map<String, dynamic>;
      expect(index['generatedAt'], isNot(before));
      final p1 = (index['projects'] as List).firstWhere((e) => e['profileId'] == 'solo' && e['id'] == 'p1');
      expect(p1['todos'].single['completed'], isTrue);
    });
  });

  group('captures', () {
    test('a capture becomes the preview of a project without one', () async {
      final source = await capture('Teardrop_20261018-120000.flac');
      await drop('capture.ready', {'file': 'captures/Teardrop_20261018-120000.flac', 'durationSeconds': 60});

      expect(await bridge.processOutbox(), 1);
      final preview = library.project('solo', 'p1').previewSongPath!;
      expect(p.isWithin(bridge.companionPreviewDir, preview), isTrue);
      expect(await File(preview).readAsString(), 'flac');
      expect(library.project('solo', 'p1').previewSongFileName, 'Teardrop_20261018-120000.flac');
      expect(await source.exists(), isFalse);
    });

    test('a newer capture replaces the earlier one and its file', () async {
      await capture('a.flac');
      await drop('capture.ready', {'file': 'captures/a.flac'});
      await bridge.processOutbox();
      final first = library.project('solo', 'p1').previewSongPath!;

      await capture('b.flac', content: 'newer');
      await drop('capture.ready', {'file': 'captures/b.flac', 'supersedes': 'captures/a.flac'});
      await bridge.processOutbox();

      final second = library.project('solo', 'p1').previewSongPath!;
      expect(second, isNot(first));
      expect(await File(second).readAsString(), 'newer');
      expect(await File(first).exists(), isFalse);
    });

    test('a preview the user picked is kept; the capture is cleared anyway', () async {
      final picked = p.join(tmp.path, 'Final Master.wav');
      await File(picked).writeAsString('master');
      await library.saveProject('solo', library.project('solo', 'p1').copyWith(previewSongPath: picked));
      library.saves.clear();

      final source = await capture('c.flac');
      await drop('capture.ready', {'file': 'captures/c.flac'});
      expect(await bridge.processOutbox(), 0);

      expect(library.project('solo', 'p1').previewSongPath, picked);
      expect(library.saves, isEmpty);
      expect(await source.exists(), isFalse);
    });

    test('a superseded capture whose file is gone is skipped', () async {
      await drop('capture.ready', {'file': 'captures/gone.flac'});
      expect(await bridge.processOutbox(), 0);
      expect(library.project('solo', 'p1').previewSongPath, isNull);
    });

    test('a message can\'t point the app outside the captures folder', () async {
      final outside = File(p.join(tmp.path, 'secret.txt'));
      await outside.writeAsString('keep me');
      await drop('capture.ready', {'file': '../secret.txt'});
      await drop('capture.ready', {'file': 'captures/../../secret.txt'});

      expect(await bridge.processOutbox(), 0);
      expect(await outside.exists(), isTrue);
      expect(library.project('solo', 'p1').previewSongPath, isNull);
    });
  });

  test('the launch hint is written whole', () async {
    await writeCompanionLaunchHint('solo', library.project('solo', 'p1'), bridgeDir: bridgeDir);
    final hint = jsonDecode(await File(p.join(bridgeDir, 'launch.json')).readAsString());
    expect(hint['projectId'], 'p1');
    expect(hint['profileId'], 'solo');
    expect(DateTime.tryParse(hint['launchedAt']), isNotNull);
  });
}
