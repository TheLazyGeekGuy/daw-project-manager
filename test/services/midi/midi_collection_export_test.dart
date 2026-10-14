import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/models/midi_clip_naming.dart';
import 'package:daw_project_manager/models/midi_collection.dart';
import 'package:daw_project_manager/services/midi/midi_collection_export.dart';
import 'package:daw_project_manager/services/midi/synth_voice.dart';
import 'package:daw_project_manager/utils/time_signature.dart';

const _clip = MidiClip(
  name: 'Line',
  ppq: 480,
  lengthTicks: 1920,
  notes: [MidiNote(startTick: 0, lengthTicks: 240, pitch: 36, velocity: 100)],
);

final _labels = MidiNamingLabels(
  roleName: (r) => r.name,
  instrumentName: (v) => v.name,
  bars: (n) => '$n bars',
  free: 'free',
);

void main() {
  final collection = MidiCollection(
    id: 'c',
    name: 'Ideas',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    folders: const [MidiCollectionFolder(id: 'f', name: 'Basses')],
    items: [
      MidiCollectionItem(
        id: 'a',
        clip: _clip,
        addedAt: DateTime.utc(2026),
        bpm: 140,
        musicalKey: 'Am',
        folderId: 'f',
        voice: 'bass',
        timeSignature: '7/8',
      ),
      MidiCollectionItem(
        id: 'b',
        clip: _clip,
        addedAt: DateTime.utc(2026),
        bpm: 128,
      ),
    ],
  );

  test("each clip keeps its own tempo, key, time signature and folder", () {
    final exports = midiCollectionExports(collection, labels: _labels);
    expect(exports, hasLength(2));
    expect(exports[0].bpm, 140);
    expect(exports[0].musicalKey, 'Am');
    expect(exports[0].timeSignature, TimeSignature.tryParse('7/8'));
    expect(exports[0].folders, ['Basses']);
    expect(exports[1].bpm, 128);
    expect(exports[1].timeSignature, TimeSignature.common);
    expect(exports[1].folders, isEmpty);
  });

  test('names are the plan\'s names, by the collection\'s template', () {
    final plan = planMidiCollectionFiles(collection, labels: _labels);
    final exports = midiCollectionExports(collection, labels: _labels);
    expect([for (final e in exports) e.fileName],
        [for (final f in plan) f.fileName]);
    expect(
      plan.first.fileName,
      midiItemFileName(
        collection,
        collection.items.first,
        labels: _labels,
        voice: SynthVoice.bass,
        number: 1,
        width: 2,
        bpm: 140,
      ),
    );
  });

  test('one tempo set for all overrides every clip\'s own', () {
    final exports =
        midiCollectionExports(collection, labels: _labels, bpm: 100);
    expect({for (final e in exports) e.bpm}, {100});
  });

  test('an item without a chosen voice is played by what its notes sound like',
      () {
    expect(midiCollectionItemVoice(collection.items.first), SynthVoice.bass);
    expect(midiCollectionItemVoice(collection.items.last),
        inferSynthVoice(_clip));
  });
}
