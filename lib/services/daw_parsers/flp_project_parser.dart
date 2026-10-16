import 'dart:convert';
import 'dart:typed_data';

import '../../models/midi_clip.dart';
import '../../models/project_stats.dart';
import '../../models/sample_reference.dart';
import 'embedded_audio_paths.dart';

/// Reads channel counts, plug-ins and patterns out of an FL Studio `.flp`.
///
/// An `.flp` is an `FLhd` header (format, channel count, PPQ as little-endian
/// u16s) followed by an `FLdt` chunk holding a flat stream of TLV events whose
/// id range sets the payload size (see `MetadataExtractor._extractFromFlpFile`).
/// The events used here, from the PyFLP / FLPFiles event catalogues:
///
/// * 64 (word) starts a new channel; 21 (byte) is that channel's type —
///   0 sampler, 1 native generator, 2 plug-in generator, 4 audio clip
///   (3 layer and 5 automation aren't tracks).
/// * 201 (text) is a plug-in's internal name; 203 (text) its display name —
///   192 (text) before FL 12 (FL 7 and 10 write it after the plug-in's
///   state). Wrapped VST/VST3s report `Fruity Wrapper` as their internal
///   name; the wrapper's state (213) names the plug-in it hosts, and the
///   display name — often a preset's — stands in when it doesn't.
/// * 65 (word) starts a pattern, 193 (text) names it, and 224 (data) holds
///   its notes: position u32, flags u16, channel u16, length u32, then the
///   key. Since FL 9 a record is 24 bytes — key u16, group u16, fine pitch,
///   a byte, release, MIDI channel (+19), pan, velocity (+21), mod X/Y. FL 7
///   wrote 20 — key, fine pitch, release, MIDI channel (+15), pan, velocity
///   (+17), mod X/Y, a byte each (see [_noteRecordSize]).
///
/// Text payloads are UTF-16LE since FL 11.5 and ASCII before it.
class FlpProjectParser {
  FlpProjectParser(this.bytes) : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;

  static const _wrapper = 'Fruity Wrapper';
  static final _instanceNumber = RegExp(r'\s+#\d+$');

  ProjectStats readStats({bool countMidiClips = true}) {
    final events = _events().toList();
    var sampler = 0, instrument = 0, audio = 0;
    final plugins = <String>[];
    // One plug-in slot at a time — a channel's generator or a mixer effect:
    // its internal name (201), display name (203, or 192 before FL 12) and,
    // for a wrapped VST, the name in its state (213). They come in either
    // order, so the slot is named when the next one starts.
    String? internal, display, wrapped;
    void endSlot() {
      final name = internal == _wrapper ? (wrapped ?? display) : internal;
      if (name != null && name.isNotEmpty) plugins.add(name);
      internal = display = wrapped = null;
    }

    for (final e in events) {
      switch (e.id) {
        case 64:
          endSlot();
        case 21:
          switch (e.value) {
            case 0:
              sampler++;
            case 1:
            case 2:
              instrument++;
            case 4:
              audio++;
          }
        case 201:
          endSlot();
          final name = _text(e);
          // FL 7 spells it "Fruity wrapper".
          internal = name.isEmpty
              ? null
              : name.toLowerCase() == _wrapper.toLowerCase()
                  ? _wrapper
                  : name;
        case 203 || 192:
          // FL numbers a second instance "Sylenth1 #2": the same plug-in.
          if (internal != null) display ??= _text(e).replaceFirst(_instanceNumber, '');
        case 213:
          if (internal == _wrapper) wrapped ??= _wrappedPluginName(e);
      }
    }
    endSlot();

    return ProjectStats(
      samplerTracks: sampler,
      instrumentTracks: instrument,
      audioTracks: audio,
      plugins: normalizePluginNames(plugins),
      midiClipCount: countMidiClips ? readMidiClips().length : null,
    );
  }

  /// One clip per pattern per channel: an FL pattern holds notes for many
  /// channels at once, and a drum pattern's kick line is what you'd reuse.
  List<MidiClip> readMidiClips() {
    final ppq = _ppq;
    final clips = <MidiClip>[];
    final channelNames = <int, String>{};
    var channel = -1;
    var pattern = 0;
    final patternNames = <int, String>{};
    final patternNotes = <int, List<(int, MidiNote)>>{};

    for (final e in _events()) {
      switch (e.id) {
        case 64:
          channel = e.value;
        case 203 || 192:
          if (channel >= 0) channelNames.putIfAbsent(channel, () => _text(e));
        case 65:
          pattern = e.value;
        case 193:
          patternNames[pattern] = _text(e);
        case 224:
          final list = patternNotes.putIfAbsent(pattern, () => []);
          final size = _noteRecordSize(e);
          for (var o = e.offset; o + size <= e.offset + e.length; o += size) {
            final position = _data.getUint32(o, Endian.little);
            final rackChannel = _data.getUint16(o + 6, Endian.little);
            final length = _data.getUint32(o + 8, Endian.little);
            final key = size == 20 ? bytes[o + 12] : _data.getUint16(o + 12, Endian.little);
            final velocity = bytes[o + (size == 20 ? 17 : 21)];
            // A note's own MIDI channel: a pattern imported from a MIDI file
            // keeps each of its parts on one, and two parts can double a
            // note — dropped, they collide on one channel in a .mid.
            final midiChannel = bytes[o + (size == 20 ? 15 : 19)];
            if (key > 127) continue;
            list.add((
              rackChannel,
              MidiNote(
                startTick: position,
                lengthTicks: length < 1 ? 1 : length,
                pitch: key,
                velocity: velocity.clamp(1, 127),
                channel: midiChannel & 0x0F,
              ),
            ));
          }
      }
    }

    final barTicks = ppq * 4;
    for (final entry in patternNotes.entries) {
      final byChannel = <int, List<MidiNote>>{};
      for (final (ch, note) in entry.value) {
        (byChannel[ch] ??= []).add(note);
      }
      for (final ch in byChannel.keys.toList()..sort()) {
        final notes = byChannel[ch]!
          ..sort((a, b) => a.startTick.compareTo(b.startTick));
        final end = notes.map((n) => n.endTick).reduce((a, b) => a > b ? a : b);
        // Patterns have no stored length; round up to whole bars.
        final length = ((end + barTicks - 1) ~/ barTicks) * barTicks;
        clips.add(MidiClip(
          name: patternNames[entry.key] ?? 'Pattern ${entry.key}',
          trackName: channelNames[ch],
          ppq: ppq,
          lengthTicks: length,
          notes: notes,
        ));
      }
    }
    return dedupeMidiClips(clips);
  }

  /// Every audio file the project references.
  ///
  /// * 196 (text) is a channel's sample: a Sampler channel's (type 0) or an
  ///   audio clip's (type 4). FL writes it absolute since FL 12 (or with a
  ///   `%FLStudioFactoryData%`-style placeholder for its own content) and
  ///   relative to its install's `Data` folder before (`\Patches\…`).
  /// * Plug-in state (data events 212/213 and the rest above 207) is
  ///   searched for absolute paths, which finds Fruity Slicer, Slicex,
  ///   DirectWave and any third-party sampler that keeps its path as text.
  List<SampleReference> readSampleReferences() {
    final refs = <SampleReference>[];
    var channelType = -1;
    for (final e in _events()) {
      switch (e.id) {
        case 64:
          channelType = -1;
        case 21:
          channelType = e.value;
        case 196:
          final path = _text(e);
          if (path.isEmpty || !isSampleAudioFile(path)) continue;
          refs.add(SampleReference(
            fileName: sampleFileNameOf(path),
            candidates: [path],
            use: channelType == 4 ? SampleUse.audio : SampleUse.sampler,
          ));
        default:
          if (e.id < 208) continue;
          final payload =
              Uint8List.sublistView(bytes, e.offset, e.offset + e.length);
          for (final path in findEmbeddedAudioPaths(payload)) {
            refs.add(SampleReference(
              fileName: sampleFileNameOf(path),
              candidates: [path],
              use: SampleUse.plugin,
            ));
          }
      }
    }
    return refs;
  }

  /// How long [notes]' records are: 24 bytes since FL 9, 20 in FL 7's
  /// files. A payload only one of them divides says which; one both divide
  /// (every multiple of 120 bytes) goes by which reads as notes — read with
  /// the wrong size, every record after the first starts mid-note, and
  /// positions, lengths and keys come out as flag bytes.
  int _noteRecordSize(_FlpEvent notes) {
    final fits = [
      for (final size in const [24, 20])
        if (notes.length % size == 0) size,
    ];
    if (fits.length == 1) return fits.single;
    if (fits.isEmpty) return 24;
    var best = 24, bestScore = -1.0;
    for (final size in fits) {
      final score = _plausibleNotes(notes, size);
      if (score > bestScore) (best, bestScore) = (size, score);
    }
    return best;
  }

  /// The share of [notes]' records that, read [size] bytes at a time, look
  /// like notes: a key in range, a position and length under a day of ticks.
  double _plausibleNotes(_FlpEvent notes, int size) {
    const sane = 1 << 24;
    var good = 0, all = 0;
    for (var o = notes.offset; o + size <= notes.offset + notes.length; o += size) {
      all++;
      final key = size == 20 ? bytes[o + 12] : _data.getUint16(o + 12, Endian.little);
      if (key <= 127 &&
          _data.getUint32(o, Endian.little) < sane &&
          _data.getUint32(o + 8, Endian.little) < sane) {
        good++;
      }
    }
    return all == 0 ? 0 : good / all;
  }

  /// The plug-in a Fruity Wrapper hosts, from its state (213): a u32, then
  /// records of id u32, size u64 and data, record 54 being the plug-in's own
  /// name — "Sylenth1" on a channel renamed after its preset. Null when the
  /// state is laid out otherwise.
  String? _wrappedPluginName(_FlpEvent state) {
    var pos = state.offset + 4;
    final end = state.offset + state.length;
    while (pos + 12 <= end) {
      final id = _data.getUint32(pos, Endian.little);
      final size = _data.getUint64(pos + 4, Endian.little);
      pos += 12;
      // A u64 past 2^63 reads negative: FL 7's state is laid out otherwise.
      if (size < 0 || size > end - pos) return null;
      if (id == 54) {
        final name = utf8.decode(bytes.sublist(pos, pos + size), allowMalformed: true)
            .replaceAll('\u0000', '')
            .trim();
        return name.isEmpty ? null : name;
      }
      pos += size;
    }
    return null;
  }

  int get _ppq {
    if (bytes.length >= 14 && _ascii(0, 4) == 'FLhd') {
      final ppq = _data.getUint16(12, Endian.little);
      if (ppq > 0) return ppq;
    }
    return 96;
  }

  Iterable<_FlpEvent> _events() sync* {
    if (bytes.length < 8 || _ascii(0, 4) != 'FLhd') return;
    final headerLength = _data.getUint32(4, Endian.little);
    var pos = 8 + headerLength;
    if (pos + 8 > bytes.length || _ascii(pos, 4) != 'FLdt') return;
    final dataLength = _data.getUint32(pos + 4, Endian.little);
    pos += 8;
    final end = pos + dataLength > bytes.length ? bytes.length : pos + dataLength;

    while (pos < end) {
      final id = bytes[pos++];
      if (id < 64) {
        if (pos + 1 > end) return;
        yield _FlpEvent(id, bytes[pos], pos, 1);
        pos += 1;
      } else if (id < 128) {
        if (pos + 2 > end) return;
        yield _FlpEvent(id, _data.getUint16(pos, Endian.little), pos, 2);
        pos += 2;
      } else if (id < 192) {
        if (pos + 4 > end) return;
        yield _FlpEvent(id, _data.getUint32(pos, Endian.little), pos, 4);
        pos += 4;
      } else {
        var length = 0, shift = 0;
        while (true) {
          if (pos >= end) return;
          final b = bytes[pos++];
          length |= (b & 0x7F) << shift;
          if (b & 0x80 == 0) break;
          shift += 7;
        }
        if (pos + length > end) return;
        yield _FlpEvent(id, 0, pos, length);
        pos += length;
      }
    }
  }

  String _text(_FlpEvent e) {
    final raw = bytes.sublist(e.offset, e.offset + e.length);
    // UTF-16LE when every odd byte of the (even-length) payload is zero —
    // true of every name FL writes in Latin script, which is all ASCII-era
    // files could hold anyway.
    final looksUtf16 = raw.length >= 2 &&
        raw.length.isEven &&
        Iterable.generate(raw.length ~/ 2, (i) => raw[i * 2 + 1])
                .where((b) => b == 0)
                .length >=
            raw.length ~/ 4;
    String text;
    if (looksUtf16) {
      final units = <int>[];
      for (var i = 0; i + 1 < raw.length; i += 2) {
        units.add(raw[i] | (raw[i + 1] << 8));
      }
      text = String.fromCharCodes(units);
    } else {
      text = utf8.decode(raw, allowMalformed: true);
    }
    final nul = text.indexOf('\u0000');
    return (nul >= 0 ? text.substring(0, nul) : text).trim();
  }

  String _ascii(int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
}

class _FlpEvent {
  const _FlpEvent(this.id, this.value, this.offset, this.length);
  final int id;

  /// The payload for fixed-size events; 0 for variable-length ones.
  final int value;
  final int offset;
  final int length;
}
