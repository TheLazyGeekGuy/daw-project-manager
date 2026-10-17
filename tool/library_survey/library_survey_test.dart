// Reads every project under a folder with the app's own readers — read
// only, nothing is written next to the projects — and writes one JSON line
// per project file: what was read, how long it took, and any error. The
// summary at the end flags what deserves a look: crashes, slow reads,
// absurd clip lengths, projects with no tempo, references that resolve to
// nothing.
//
//   SURVEY_ROOT="D:\Music\Projects" SURVEY_OUT=survey.jsonl \
//     flutter test tool/library_survey/library_survey_test.dart
//
// Not part of the suite: it needs a real library. Run it before and after
// a reader change and compare the two files. On a cloud drive every read
// downloads the file — point it at local folders.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/services/metadata_extractor.dart';
import 'package:daw_project_manager/services/sample_pack/project_sample_reader.dart';

const _extensions = {'.cpr', '.npr', '.als', '.flp', '.rpp', '.song', '.bwproject', '.dawproject'};

void main() {
  test('survey', () async {
    final root = Platform.environment['SURVEY_ROOT'];
    final outPath = Platform.environment['SURVEY_OUT'] ?? 'survey.jsonl';
    if (root == null) fail('Set SURVEY_ROOT to the folder to read.');

    final files = Directory(root).listSync(recursive: true, followLinks: false).whereType<File>().where((f) {
      final path = f.path.toLowerCase();
      return _extensions.contains(p.extension(path)) &&
          !path.contains('backup') &&
          !path.contains('autosave') &&
          !path.contains('auto-save');
    }).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final out = File(outPath).openWrite();
    final flags = <String>[];
    for (final f in files) {
      final row = <String, Object?>{'path': f.path, 'mb': (f.lengthSync() / 1048576).toStringAsFixed(1)};
      final watch = Stopwatch()..start();
      try {
        final m = await MetadataExtractor.extractMetadata(f.path);
        row['ms'] = watch.elapsedMilliseconds;
        final clips = m.midiClips ?? const [];
        final maxBars = clips.isEmpty
            ? 0
            : clips.map((c) => c.lengthTicks / (c.ppq * 4)).reduce((a, b) => a > b ? a : b).round();
        row.addAll({
          'daw': m.dawType,
          'ver': m.dawVersion,
          'bpm': m.bpm,
          'key': m.key,
          'markers': m.markers?.length,
          'clips': clips.length,
          'notes': clips.fold<int>(0, (n, c) => n + c.notes.length),
          'maxBars': maxBars,
          'tracks': m.stats?.totalTracks,
          'plugins': m.stats?.plugins,
        });
        watch.reset();
        final refs = await readProjectSampleReferences(f.path);
        row['refsMs'] = watch.elapsedMilliseconds;
        row['refs'] = refs.length;
        row['refsFound'] = refs
            .where((r) => r.candidates.any((c) => File(p.isAbsolute(c) ? c : p.join(f.parent.path, c)).existsSync()))
            .length;

        if ((row['ms'] as int) > 2000) flags.add('slow (${row['ms']} ms): ${f.path}');
        if (maxBars > 256) flags.add('clip $maxBars bars long: ${f.path}');
        if (m.bpm == null) flags.add('no tempo: ${f.path}');
        if (m.stats == null) flags.add('no stats: ${f.path}');
      } catch (e, st) {
        row['error'] = '$e'.split('\n').first;
        row['at'] = '$st'.split('\n').take(3).join(' | ');
        flags.add('ERROR ${row['error']}: ${f.path}');
      }
      out.writeln(jsonEncode(row));
    }
    await out.close();
    // ignore: avoid_print
    print('Read ${files.length} projects into $outPath.\n${flags.isEmpty ? 'Nothing flagged.' : flags.join('\n')}');
  }, timeout: const Timeout(Duration(hours: 1)));
}
