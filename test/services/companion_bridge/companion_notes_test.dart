import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/profile.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_bridge_service.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/test_factories.dart';

class _Library implements CompanionLibrary {
  _Library(this.profile, this.projects);
  final Profile profile;
  final List<MusicProject> projects;

  @override
  Future<List<CompanionProfileProjects>> load() async => [CompanionProfileProjects(profile, List.of(projects))];

  @override
  Future<void> saveProject(String profileId, MusicProject project) async {
    projects[projects.indexWhere((x) => x.id == project.id)] = project;
  }

  MusicProject byId(String id) => projects.firstWhere((x) => x.id == id);
}

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);
  CompanionNotesSet edit(String text, String base) =>
      CompanionNotesSet('m1', now, const CompanionProjectRef('solo', 'p1'), text: text, baseText: base);

  group('applying a notes edit', () {
    test('an edit of what the app has replaces it', () {
      final project = TestFactories.makeProject(notes: 'Kick too loud');
      expect(applyCompanionNotesSet(project, edit('Kick fixed', 'Kick too loud'))!.notes, 'Kick fixed');
    });

    test('the same text again changes nothing — a replay is harmless', () {
      final project = TestFactories.makeProject(notes: 'Kick fixed');
      expect(applyCompanionNotesSet(project, edit('Kick fixed', 'Kick too loud')), isNull);
    });

    test('changed in both places: both are kept, the app\'s first', () {
      final project = TestFactories.makeProject(notes: 'Kick too loud\nBass: more sub');
      final merged = applyCompanionNotesSet(project, edit('Kick fixed', 'Kick too loud'))!.notes;
      expect(merged, 'Kick too loud\nBass: more sub${companionNotesSeparator}Kick fixed');
    });

    test('empty notes in the app take the plugin\'s text as is', () {
      expect(applyCompanionNotesSet(TestFactories.makeProject(), edit('First note', 'stale base'))!.notes, 'First note');
    });

    test('clearing the notes in the plugin clears them in the app', () {
      final project = TestFactories.makeProject(notes: 'Old');
      expect(applyCompanionNotesSet(project, edit('', 'Old'))!.notes, isNull);
    });
  });

  test('notes.set is read, its text capped', () {
    final m = parseCompanionMessage(jsonEncode({
      'id': 'op-1',
      'type': 'notes.set',
      'createdAt': '2026-10-19T12:00:00.000Z',
      'project': {'id': 'p1', 'profileId': 'solo'},
      'payload': {'text': 'a' * 30000, 'baseText': 'b'},
    })) as CompanionNotesSet;
    expect(m.id, 'op-1');
    expect(m.text.length, companionMaxNotesLength);
    expect(m.baseText, 'b');
    expect(parseCompanionMessage(jsonEncode({'id': 'x', 'type': 'notes.set', 'payload': {'text': 1}})), isNull);
  });

  test('the index carries each project\'s notes (a member\'s: its stack\'s) and the applied ids', () {
    final solo = Profile(id: 'solo', name: 'Solo', createdAt: DateTime(2025));
    final index = buildCompanionIndex([
      CompanionProfileProjects(solo, [
        TestFactories.makeProject(id: 'p1', notes: 'Own notes'),
        TestFactories.makeProject(id: 'stack', isVirtual: true, memberProjectIds: ['v1'], notes: 'Shared notes'),
        TestFactories.makeProject(id: 'v1', stackId: 'stack', notes: 'Dormant'),
        TestFactories.makeProject(id: 'p2'),
      ]),
    ], generatedAt: now, appVersion: '1', appliedMessageIds: ['op-1', 'op-2']);

    final notes = {for (final p in index['projects'] as List) p['id']: p['notes']};
    expect(notes, {'p1': 'Own notes', 'v1': 'Shared notes', 'p2': ''});
    expect(index['applied'], ['op-1', 'op-2']);
  });

  group('through the bridge', () {
    late Directory tmp;
    late _Library library;
    late CompanionBridgeService bridge;
    var clock = now;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('companion_notes_test');
      clock = now;
      library = _Library(Profile(id: 'solo', name: 'Solo', createdAt: DateTime(2025)), [
        TestFactories.makeProject(id: 'p1', notes: 'Vocals: comp verse 2'),
        TestFactories.makeProject(id: 'stack', isVirtual: true, memberProjectIds: ['v1'], notes: 'Shared'),
        TestFactories.makeProject(id: 'v1', stackId: 'stack'),
      ]);
      bridge = CompanionBridgeService(
        library: library,
        bridgeDir: p.join(tmp.path, 'plugin_bridge'),
        previewSongsDir: p.join(tmp.path, 'preview'),
        appVersion: '1',
        clock: () => clock,
      );
    });

    tearDown(() async => tmp.delete(recursive: true));

    Future<void> drop(String id, String projectId, String text, String base) async {
      final f = File(p.join(tmp.path, 'plugin_bridge', 'outbox', '20261019T120000000Z-000000-$id.json'));
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'id': id,
        'type': 'notes.set',
        'createdAt': '2026-10-19T12:00:00.000Z',
        'project': {'id': projectId, 'profileId': 'solo'},
        'payload': {'text': text, 'baseText': base},
      }));
    }

    Future<Map<String, dynamic>> index() async =>
        jsonDecode(await bridge.indexFile.readAsString()) as Map<String, dynamic>;

    test('an edit lands on the project and its id is listed as applied', () async {
      await drop('op-1', 'p1', 'Vocals: comp verse 2\nBass: sidechain', 'Vocals: comp verse 2');
      await bridge.tick();

      expect(library.byId('p1').notes, 'Vocals: comp verse 2\nBass: sidechain');
      final i = await index();
      expect(i['applied'], ['op-1']);
      expect((i['projects'] as List).firstWhere((x) => x['id'] == 'p1')['notes'], 'Vocals: comp verse 2\nBass: sidechain');
    });

    test('a member\'s notes are its stack\'s', () async {
      await drop('op-2', 'v1', 'Shared + new', 'Shared');
      await bridge.tick();
      expect(library.byId('stack').notes, 'Shared + new');
      expect(library.byId('v1').notes, isNull);
    });

    test('an edit that changes nothing is still listed, so the plugin stops waiting', () async {
      await drop('op-3', 'p1', 'Vocals: comp verse 2', 'Vocals: comp verse 2');
      await bridge.tick();
      expect((await index())['applied'], ['op-3']);
    });

    test('applied ids are forgotten after half an hour', () async {
      await drop('op-4', 'p1', 'x', 'Vocals: comp verse 2');
      await bridge.tick();
      clock = clock.add(const Duration(minutes: 31));
      await bridge.writeIndex(force: true);
      expect((await index())['applied'], isEmpty);
    });
  });
}
