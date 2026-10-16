// MIDI, from a DAW project to a .mid file, over the real projects of the
// collection: a scan finds them, a deep scan stores the clips the readers
// find, the MIDI tab's library is built from what was stored, a collection
// keeps copies, and every clip exported to .mid reads back note for note.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/models/midi_clip_naming.dart';
import 'package:daw_project_manager/models/midi_library.dart';
import 'package:daw_project_manager/services/midi/midi_clip_service.dart';
import 'package:daw_project_manager/services/midi/midi_collection_export.dart';
import 'package:daw_project_manager/services/midi/midi_file_import.dart';
import 'package:daw_project_manager/services/midi/midi_file_writer.dart';
import 'package:daw_project_manager/ui/midi_collection_actions.dart' show collectionItemFor;
import 'package:daw_project_manager/utils/musical_key.dart';

import '../fixtures/fixture_collection.dart';
import 'flow_library.dart';

final _labels = MidiNamingLabels(
  roleName: (r) => r.name,
  instrumentName: (v) => v.name,
  bars: (n) => '$n bars',
  free: 'free',
);

/// What a clip recorded in an .expected.json says: name and content.
List<String> _recorded(Map<String, Object?> expected) => [
      for (final c in expected['midiClips']! as List)
        '${(c as Map)['name']} ${c['content']}',
    ];

List<String> _summary(List<MidiClip> clips) => [
      for (final c in clips) '${c.name} ${clipContentHash(c)}',
    ];

void main() {
  late FlowLibrary lib;

  setUp(() async => lib = await FlowLibrary.open());
  tearDown(() async => lib.close());

  test('a scan finds every project, a deep scan stores exactly what the readers read', () async {
    final found = await lib.scan();
    expect(found, lib.projectFiles.length);

    // A plain scan reads no contents: the first read is behind Deep Scan.
    for (final (_, file) in lib.projectFiles) {
      expect(await lib.clipsOf(file), isNull, reason: '${file.path} before a deep scan');
      expect(lib.projectOf(file).stats, isNull, reason: '${file.path} before a deep scan');
    }

    await lib.deepScan();
    Future<void> expectAsRecorded(String when) async {
      for (final (f, file) in lib.projectFiles) {
        final row = lib.projectOf(file);
        final expected = f.expectedFor(file);
        final what = '$f/${p.basename(file.path)}';
        expect(row.bpm, expected['bpm'], reason: '$what tempo, $when');
        expect(row.stats?.toMap(), expected['stats'], reason: '$what stats, $when');
        final stored = await lib.clipsOf(file);
        expect(_summary(stored?.clips ?? const []), _recorded(expected), reason: '$what clips, $when');
      }
    }

    await expectAsRecorded('after the deep scan');

    // Stored, not just held in memory: the same after a relaunch.
    await lib.reopen();
    await expectAsRecorded('after reopening the database');

    // A plain rescan keeps what the deep scan read; another deep scan
    // reads the same again — and neither makes a second row of anything.
    final ids = {for (final r in lib.projects) r.id};
    await lib.scan();
    await expectAsRecorded('after a plain rescan');
    await lib.deepScan();
    await expectAsRecorded('after a second deep scan');
    expect({for (final r in lib.projects) r.id}, ids);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('library, collection and .mid export keep every note', () async {
    await lib.scan();
    await lib.deepScan();

    // The MIDI tab's library: every stored clip, each unique one once.
    final stored = await lib.repo.midiClips.getAll();
    final rows = {for (final r in lib.projects) r.id: r};
    final library = buildMidiLibrary(stored, rows);
    final allClips = [for (final s in stored.values) ...s.clips];
    expect(allClips, isNotEmpty);
    expect(
      library.map((e) => e.clip.contentKey).toSet(),
      allClips.map((c) => c.contentKey).toSet(),
      reason: 'every clip read is in the library',
    );
    expect(library.length, library.map((e) => e.clip.contentKey).toSet().length,
        reason: 'and each only once');

    // All of it into one collection, as "Add to collection" does.
    final collections = lib.repo.midiCollections;
    final created = await collections.create('Everything');
    final added = await collections.addItems(created.id, [
      for (final e in library)
        collectionItemFor(e.clip,
            projectId: e.projectId,
            projectName: e.projectName,
            bpm: e.bpm,
            musicalKey: e.musicalKey),
    ]);
    expect(added, library.length);
    // Adding the same clips again adds nothing.
    expect(
      await collections.addItems(created.id, [
        for (final e in library) collectionItemFor(e.clip, projectId: e.projectId),
      ]),
      0,
    );

    await lib.reopen();
    final collection = (await lib.repo.midiCollections.get(created.id))!;
    expect(collection.items.map((i) => i.clip.contentKey).toList(),
        library.map((e) => e.clip.contentKey).toList());

    // A collection holds copies: deleting every project leaves it whole.
    await lib.repo.deleteProjects([for (final r in lib.projects) r.id]);
    expect(await lib.repo.midiClips.getAll(), isEmpty, reason: 'their clips go with them');
    final kept = (await lib.repo.midiCollections.get(created.id))!;
    expect(kept.items.length, collection.items.length);

    // Exported as the MIDI tab exports a collection, then read back as a
    // DAW — or the app's own import — reads a .mid.
    final exports = midiCollectionExports(kept, labels: _labels);
    final dir = Directory(p.join(lib.scratch.path, 'Export'));
    final files = await MidiClipService.exportAll(exports, dir);
    expect(files, hasLength(kept.items.length), reason: 'one file per clip, none overwritten');
    expect(files.map((f) => f.path).toSet(), hasLength(files.length));

    for (final (i, file) in files.indexed) {
      final item = kept.items[i];
      final back = importMidiFile(await file.readAsBytes(), p.basename(file.path));
      expect(back, isNotNull, reason: '${file.path} reads as MIDI');
      expect(back!.clips, hasLength(1),
          reason: '${p.basename(file.path)}: from "${item.clip.name}" of ${item.sourceProjectName}, '
              '${item.clip.notes.length} notes, ${item.clip.events.length} events, '
              '${item.clip.lengthTicks} ticks at ${item.clip.ppq} ppq');
      // Exactly the clip — save for same-pitch overlaps on one channel,
      // which no .mid can hold (see notesForMidiFile).
      final writable = item.clip.copyWith(notes: notesForMidiFile(item.clip.notes));
      expect(back.clips.single.contentKey, writable.contentKey,
          reason: '${p.basename(file.path)}: the notes, their timing and events');
      if (item.bpm != null) expect(back.bpm, closeTo(item.bpm!, 0.01));
      if (keySignatureOf(item.musicalKey) != null) {
        expect(keySignatureOf(back.musicalKey), keySignatureOf(item.musicalKey));
      }
    }

    // A single clip's own export says the same.
    final first = kept.items.first;
    final one = MidiExport(first.clip, bpm: first.bpm, musicalKey: first.musicalKey).encode();
    expect(importMidiFile(one, 'one.mid')!.clips.single.contentKey,
        first.clip.copyWith(notes: notesForMidiFile(first.clip.notes)).contentKey);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
