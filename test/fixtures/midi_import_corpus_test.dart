// .mid files from a real producer's library (test/fixtures/midi/), imported
// as the MIDI tab imports them and compared with what was recorded in
// midi.expected.json: each file's clips, their notes summarised by a hash,
// its tempo and key signature — and what its file name says about the key
// and tempo, as the sample pack reads names.
//
// UPDATE_FIXTURES=1 flutter test test/fixtures/midi_import_corpus_test.dart
// rewrites the record; read the diff before committing it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/services/midi/midi_file_import.dart';
import 'package:daw_project_manager/services/midi/midi_file_writer.dart';
import 'package:daw_project_manager/services/sample_pack/sample_naming.dart';

import 'fixture_collection.dart';

final _midiRoot = Directory(p.join('test', 'fixtures', 'midi'));
final _expected = File(p.join('test', 'fixtures', 'midi.expected.json'));
final _update = Platform.environment['UPDATE_FIXTURES'] == '1';

Map<String, Object?> _read(File f) {
  final name = p.basename(f.path);
  final imported = importMidiFile(f.readAsBytesSync(), name);
  final fromName = sampleTraitsOf(p.basenameWithoutExtension(name));
  return {
    'bpm': imported?.bpm,
    'key': imported?.musicalKey,
    'nameKey': fromName.key,
    'nameBpm': fromName.bpm,
    'clips': [
      for (final c in imported?.clips ?? const [])
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
  };
}

void main() {
  final files = _midiRoot.existsSync()
      ? (_midiRoot.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mid')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('the collection has .mid files', () => expect(files, isNotEmpty));

  test('every .mid imports as recorded', () async {
    final read = {for (final f in files) p.basename(f.path): _read(f)};
    final actual = '${const JsonEncoder.withIndent('  ').convert(read)}\n';
    if (_update) {
      await _expected.writeAsString(actual);
      return;
    }
    expect(jsonDecode(actual), jsonDecode(_expected.readAsStringSync()),
        reason: 'what importing them gives changed; if intended, rerun with UPDATE_FIXTURES=1');
  });

  test('every imported clip exports and imports again unchanged', () {
    // The round trip a collection makes: imported, exported to .mid, and
    // imported somewhere else — only same-pitch overlaps, which no .mid
    // holds, may differ (see notesForMidiFile).
    for (final f in files) {
      final imported = importMidiFile(f.readAsBytesSync(), p.basename(f.path))!;
      for (final clip in imported.clips) {
        final again = importMidiFile(
          MidiExport(clip, bpm: imported.bpm, musicalKey: imported.musicalKey).encode(),
          'again.mid',
        )!;
        expect(again.clips.single.contentKey,
            clip.copyWith(notes: notesForMidiFile(clip.notes)).contentKey,
            reason: '${p.basename(f.path)} / ${clip.name}');
        if (imported.bpm != null) expect(again.bpm, closeTo(imported.bpm!, 0.01));
      }
    }
  });
}
