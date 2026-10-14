import '../../models/midi_clip_naming.dart';
import '../../models/midi_collection.dart';
import '../../utils/time_signature.dart';
import 'midi_file_writer.dart';
import 'synth_voice.dart';

/// The voice an item plays with: the one chosen for it, else what its notes
/// sound like.
SynthVoice midiCollectionItemVoice(MidiCollectionItem item) =>
    SynthVoice.values.where((v) => v.name == item.voice).firstOrNull ??
    inferSynthVoice(item.clip);

/// Where each of [collection]'s clips goes in an export and what it is
/// called, by the collection's folders and naming template. [bpm], when
/// set, is the one tempo every clip is named and written at.
List<PlannedMidiFile> planMidiCollectionFiles(
  MidiCollection collection, {
  required MidiNamingLabels labels,
  double? bpm,
}) =>
    planCollectionExport(
      collection,
      fileNameOf: (item, number, width) => midiItemFileName(
        collection,
        item,
        labels: labels,
        voice: midiCollectionItemVoice(item),
        number: number,
        width: width,
        bpm: bpm ?? item.bpm,
      ),
    );

/// [collection]'s clips as `.mid` files to write: each at its own project's
/// tempo and key unless [bpm] sets one for all, in the collection's folders,
/// named by its template. The MIDI tab and the sample pack both export
/// through this, so the two can't name a clip differently.
List<MidiExport> midiCollectionExports(
  MidiCollection collection, {
  required MidiNamingLabels labels,
  double? bpm,
}) => [
  for (final f in planMidiCollectionFiles(collection, labels: labels, bpm: bpm))
    MidiExport(
      f.item.clip,
      bpm: bpm ?? f.item.bpm,
      musicalKey: f.item.musicalKey,
      timeSignature:
          TimeSignature.tryParse(f.item.timeSignature) ?? TimeSignature.common,
      name: f.fileName,
      folders: f.folders,
    ),
];
