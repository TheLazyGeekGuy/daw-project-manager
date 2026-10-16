// The DAW project collection: real projects, one folder each under
// test/fixtures/projects/<daw>/<name>/, read with the app's own readers and
// compared with what was recorded for them in <name>.expected.json.
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

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/services/metadata_extractor.dart';
import 'package:daw_project_manager/services/sample_pack/project_sample_reader.dart';

final _root = p.join('test', 'fixtures', 'projects');
final _update = Platform.environment['UPDATE_FIXTURES'] == '1';

/// The project file of a fixture folder: the one file there with a DAW
/// extension the scanner knows (bundles aside, a fixture is one project).
File? _projectFileIn(Directory folder) {
  const exts = {'.cpr', '.npr', '.als', '.flp', '.rpp', '.song', '.bwproject', '.dawproject', '.ptx'};
  final files = folder
      .listSync()
      .whereType<File>()
      .where((f) => exts.contains(p.extension(f.path).toLowerCase()))
      .toList();
  return files.length == 1 ? files.single : null;
}

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
          'content': _hash([
            for (final n in c.notes) '${n.startTick}:${n.lengthTicks}:${n.pitch}:${n.velocity}',
            for (final e in c.events) '$e',
          ]),
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

String _hash(List<String> parts) =>
    sha1.convert(utf8.encode(parts.join('\n'))).toString().substring(0, 12);

const _json = JsonEncoder.withIndent('  ');

void main() {
  final root = Directory(_root);
  final fixtures = <(String daw, Directory folder)>[
    if (root.existsSync())
      for (final daw in root.listSync().whereType<Directory>())
        for (final folder in daw.listSync().whereType<Directory>())
          (p.basename(daw.path), folder),
  ]..sort((a, b) => a.$2.path.compareTo(b.$2.path));

  test('the collection has projects in it', () {
    expect(fixtures, isNotEmpty, reason: 'nothing under $_root');
  });

  for (final (daw, folder) in fixtures) {
    final name = p.basename(folder.path);
    test('$daw / $name reads as recorded', () async {
      final project = _projectFileIn(folder);
      expect(project, isNotNull, reason: '$folder needs exactly one project file');

      final read = await readFixture(project!);
      final expectedFile = File('${folder.path}.expected.json');
      final actual = '${_json.convert(read)}\n';
      if (_update) {
        await expectedFile.writeAsString(actual);
        return;
      }
      expect(
        expectedFile.existsSync(),
        isTrue,
        reason: 'no ${p.basename(expectedFile.path)} — run with UPDATE_FIXTURES=1 and review it',
      );
      final expected = await expectedFile.readAsString();
      expect(
        jsonDecode(actual),
        jsonDecode(expected),
        reason: 'what the readers make of $daw/$name changed; if that is intended, '
            'rerun with UPDATE_FIXTURES=1 and review the diff',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
