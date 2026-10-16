// The DAW project collection: real projects, one folder each under
// test/fixtures/projects/<daw>/<name>/ (a project, or one song's versions),
// read with the app's own readers and compared with what was recorded for
// them in <name>.expected.json, by project file.
//
// Adding one:
//   1. scripts/add_test_fixture.ps1 -Daw cubase -Project "D:\...\Song\Song.cpr"
//      (copies the project's folder, leaving out backups, bounces and big audio)
//   2. UPDATE_FIXTURES=1 flutter test test/fixtures/project_corpus_test.dart
//      writes its .expected.json
//   3. Read the .expected.json — tempo, key, clips, samples — and commit both.
// From then on any change to a reader that alters what it reads fails here,
// on every platform CI runs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/services/metadata_extractor.dart';
import 'package:daw_project_manager/services/sample_pack/project_sample_reader.dart';

import 'fixture_collection.dart';

final _update = Platform.environment['UPDATE_FIXTURES'] == '1';

/// What the readers make of [project], in a form that is the same on every
/// machine: no absolute paths, notes and events summarised by a hash.
Future<Map<String, Object?>> readFixture(File project) async {
  final meta = await MetadataExtractor.extractMetadata(project.path);
  final refs = await readProjectSampleReferences(project.path);
  final clips = meta.midiClips ?? const <MidiClip>[];
  return {
    'dawType': meta.dawType,
    'dawVersion': meta.dawVersion,
    'bpm': meta.bpm,
    'key': meta.key,
    'markers': [for (final m in meta.markers ?? const []) m.name],
    'stats': meta.stats?.toMap(),
    'midiClips': [
      for (final c in clips)
        {
          'name': c.name,
          'track': c.trackName,
          'ppq': c.ppq,
          'lengthTicks': c.lengthTicks,
          'notes': c.notes.length,
          'events': c.events.length,
          'content': clipContentHash(c),
        },
    ],
    'sampleReferences': [
      for (final r in refs)
        {
          'file': r.fileName,
          'use': r.use.name,
          if (r.kind != null) 'kind': r.kind!.name,
        },
    ],
  };
}

const _json = JsonEncoder.withIndent('  ');

void main() {
  final fixtures = allFixtures();

  test('the collection has projects in it', () {
    expect(fixtures, isNotEmpty, reason: 'nothing under ${fixtureRoot.path}');
  });

  for (final f in fixtures) {
    test('${f.daw} / ${f.name} reads as recorded', () async {
      final projects = f.projectFiles;
      expect(projects, isNotEmpty, reason: '${f.folder} holds no project file');

      final read = {
        for (final project in projects) p.basename(project.path): await readFixture(project),
      };
      final expectedFile = f.expectedFile;
      final actual = '${_json.convert(read)}\n';
      if (_update) {
        await expectedFile.writeAsString(actual);
        return;
      }
      expect(
        expectedFile.existsSync(),
        isTrue,
        reason: 'no ${expectedFile.path} — run with UPDATE_FIXTURES=1 and review it',
      );
      final expected = await expectedFile.readAsString();
      expect(
        jsonDecode(actual),
        jsonDecode(expected),
        reason: 'what the readers make of $f changed; if that is intended, '
            'rerun with UPDATE_FIXTURES=1 and review the diff',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
