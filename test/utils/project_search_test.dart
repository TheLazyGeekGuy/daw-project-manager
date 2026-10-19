import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/project_marker.dart';
import 'package:daw_project_manager/models/project_part.dart';
import 'package:daw_project_manager/models/project_stats.dart';
import 'package:daw_project_manager/utils/project_search.dart';

import '../helpers/test_factories.dart';

void main() {
  bool matches(MusicProject project, String query, {bool tags = true}) =>
      projectMatchesSearch(project, query, includeTags: tags);

  test('finds a project by a plug-in it loads', () {
    final p = TestFactories.makeProject(
      fileName: 'Night Drive.cpr',
      stats: const ProjectStats(plugins: ['Pro-Q 3', 'Serum']),
    );
    expect(matches(p, 'serum'), isTrue);
    expect(matches(p, 'pro-q'), isTrue);
    expect(matches(p, 'omnisphere'), isFalse);
  });

  test('a project never deep-scanned simply has no plug-ins to match', () {
    final p = TestFactories.makeProject(fileName: 'Night Drive.cpr');
    expect(matches(p, 'serum'), isFalse);
    expect(matches(p, 'night'), isTrue);
  });

  test('words must hit the same plug-in, not two different ones', () {
    final p = TestFactories.makeProject(
      fileName: 'x.cpr',
      stats: const ProjectStats(plugins: ['Pro-Q 3', 'Serum']),
    );
    expect(matches(p, 'serum pro'), isFalse);
  });

  test('still covers the fields it always did', () {
    final p = TestFactories.makeProject(
      fileName: 'x.rpp',
      notes: 'needs vocals',
      markers: const [ProjectMarker(index: 1, name: 'Bridge', positionSeconds: 1)],
      tags: ['trap'],
    );
    expect(matches(p, 'vocals'), isTrue);
    expect(matches(p, 'bridge'), isTrue);
    expect(matches(p, 'trap'), isTrue);
    expect(matches(p, 'trap', tags: false), isFalse,
        reason: 'hidden tags must not make a project match');
  });

  group('names match fuzzily, long free text by word starts', () {
    test('a name still finds shorthand and the middle of a word', () {
      final p = TestFactories.makeProject(fileName: 'Chillout Vibes.als');
      expect(matches(p, 'chilvib'), isTrue);
      expect(matches(p, 'lout'), isTrue);
    });

    test('notes no longer match letters picked across their words', () {
      // fuzzyMatchAll found no|w … t|h|e and c-u-e inside Cubase.
      final p = TestFactories.makeProject(
        fileName: 'x.cpr',
        notes: 'Redo it now with the Cubase template',
      );
      expect(matches(p, 'note'), isFalse);
      expect(matches(p, 'cue'), isFalse);
      expect(matches(p, 'cub temp'), isTrue);
      expect(matches(p, 'plate'), isFalse, reason: 'inside "template"');
    });

    test('notes read from the project file follow the same rule', () {
      final p = TestFactories.makeProject(
        fileName: 'x.rpp',
        projectNotes: 'Now the bridge needs work',
      );
      expect(matches(p, 'note'), isFalse);
      expect(matches(p, 'bridge'), isTrue);
    });

    test('parts and performers follow the same rule', () {
      final p = TestFactories.makeProject(
        fileName: 'x.cpr',
        parts: const [
          ProjectPart(id: '1', name: 'Bass', performer: 'Joana'),
          ProjectPart(id: '2', name: 'Lead vocal', notes: 'double the hook'),
        ],
      );
      expect(matches(p, 'joana'), isTrue);
      expect(matches(p, 'bass jo'), isTrue);
      expect(matches(p, 'ana'), isFalse, reason: 'inside "Joana"');
      // ba|ss jo|ana as fuzzy chunks
      expect(matches(p, 'bajo'), isFalse);
    });
  });

  group('proseMatchesSearch', () {
    test('needs text, and every word starting a word of it', () {
      expect(proseMatchesSearch(null, 'x'), isFalse);
      expect(proseMatchesSearch('', 'x'), isFalse);
      expect(proseMatchesSearch('needs vocals', 'VOC'), isTrue);
      expect(proseMatchesSearch('now the', 'note'), isFalse);
    });
  });
}
