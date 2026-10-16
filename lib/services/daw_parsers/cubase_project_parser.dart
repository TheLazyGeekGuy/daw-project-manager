import 'dart:convert';
import 'dart:typed_data';

import '../../models/midi_clip.dart';
import '../../models/project_stats.dart';
import '../../models/sample_reference.dart';
import 'embedded_audio_paths.dart';

/// Reads tracks, plug-ins and MIDI parts out of a Cubase/Nuendo `.cpr`/`.npr`.
///
/// ## The format, as far as we need it
///
/// A `.cpr` is a RIFF-like container (`RIFF` + size + `NUND`, then big-endian
/// chunks with no padding). The project lives in `ARCH` chunks, each one a
/// Steinberg object archive:
///
/// * An object is written as a class tag, a version, a size and a body. The
///   first time a class appears the tag is `FF FF FF FF` followed by the
///   class name (u32 length incl. NUL, then the name), a u16 version, a u32
///   body size. `FF FF FF FE` + name + u16 declares a base class without an
///   instance.
/// * Every later object of an already-named class is written as
///   `0x80000000 | (offset of that class's definition − ARCH body start)`
///   followed by a u32 body size — no name and no version. So counting class
///   *names* undercounts wildly; the back-references have to be followed.
/// * Strings are a u32 length (counting a trailing NUL, and on newer versions
///   a UTF-8 BOM after it) then the bytes.
///
/// Every track object (`MAudioTrackEvent`, `MInstrumentTrackEvent`, …) has
/// the same prefix: 26 bytes of position/flags, then a node object whose body
/// starts with the track name — which is what lets each candidate be
/// validated, rather than trusting a 4-byte tag match on its own.
///
/// MIDI notes are not objects: an `MMidiPart` body packs them as fixed
/// records — status byte (`0x9n`), start as a big-endian double in 480-PPQ
/// ticks, channel, pitch, velocity, five zero bytes, an attribute count, the
/// attributes (4-char tag, u16 type, 8-byte value), then the length as a
/// double. Parts keep notes from outside their visible window when trimmed,
/// so notes are clipped to `[0, part length)` from the enclosing
/// `MMidiPartEvent` (start/length doubles at body+2 / body+10).
///
/// Reverse-engineered against Cubase 13 projects; tolerant of anything it
/// doesn't recognise (unknown classes are just never counted).
class CubaseProjectParser {
  CubaseProjectParser(this.bytes) : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;

  /// Cubase's internal resolution.
  static const int ppq = 480;

  static const _audio = 'MAudioTrackEvent';
  static const _midi = 'MMidiTrackEvent';
  static const _instrument = 'MInstrumentTrackEvent';
  static const _sampler = 'MSamplerTrackEvent';
  static const _device = 'MDeviceTrackEvent';
  static const _folder = 'MFolderTrack';
  static const _trackClasses = {
    _audio,
    _midi,
    _instrument,
    _sampler,
    _device,
    _folder,
  };

  /// Plug-in "names" that are really parts of every channel strip, or the
  /// sampler track's own engine. Only ever matched exactly.
  static const _internalPlugins = {
    'Standard Panner',
    'Stereo Combined Panner',
    'Stereo Panner',
    'Mono Panner',
    'VST MultiPanner',
    'Input Filter',
    'EQ',
    'Channel Strip',
    'Sampler Track',
  };

  bool get isCubaseFile =>
      bytes.length > 12 &&
      _ascii(0, 4) == 'RIFF' &&
      _ascii(8, 4) == 'NUND';

  ProjectStats readStats({bool countMidiClips = true}) {
    final counts = <String, int>{};
    for (final index in _indices) {
      final tracks = <String, List<_Instance>>{};
      for (final cls in _trackClasses) {
        tracks[cls] = index
            .instancesOf(cls)
            .where((i) => _trackName(i) != null)
            .toList();
      }

      // The first folder holding output channels is Cubase's own hidden
      // "Input/Output Channels" folder, not one the user made, and the
      // devices inside it are outputs rather than groups/FX.
      final folders = tracks[_folder]!..sort((a, b) => a.start.compareTo(b.start));
      final devices = tracks[_device]!;
      _Instance? ioFolder;
      for (final f in folders) {
        if (devices.any((d) => f.contains(d.start))) {
          ioFolder = f;
          break;
        }
      }

      void add(String key, int n) => counts[key] = (counts[key] ?? 0) + n;
      add(_audio, tracks[_audio]!.length);
      add(_midi, tracks[_midi]!.length);
      add(_instrument, tracks[_instrument]!.length);
      add(_sampler, tracks[_sampler]!.length);
      add(_folder, folders.length - (ioFolder == null ? 0 : 1));
      add(
        _device,
        devices.where((d) => ioFolder == null || !ioFolder.contains(d.start)).length,
      );
    }

    return ProjectStats(
      audioTracks: counts[_audio] ?? 0,
      midiTracks: counts[_midi] ?? 0,
      instrumentTracks: counts[_instrument] ?? 0,
      samplerTracks: counts[_sampler] ?? 0,
      busTracks: counts[_device] ?? 0,
      folderTracks: counts[_folder] ?? 0,
      plugins: normalizePluginNames(readPluginNames()),
      midiClipCount: countMidiClips ? readMidiClips().length : null,
    );
  }

  /// Every track in project order, with the folder it sits in.
  ///
  /// Cubase's hidden "Input/Output Channels" folder and the output devices in
  /// it are left out, as in [readStats]. Routing, inserts and colours are not
  /// read: the format keeps those as references by id, which are not decoded.
  List<CubaseTrack> readTracks() {
    final tracks = <CubaseTrack>[];
    final busNames = _busOwnerNames();
    for (final index in _indices) {
      final found = <(_Instance, String, CubaseTrackType)>[];
      for (final (cls, type) in _trackTypes) {
        for (final i in index.instancesOf(cls)) {
          final name = _trackName(i);
          if (name != null) found.add((i, name, type));
        }
      }
      found.sort((a, b) => a.$1.start.compareTo(b.$1.start));

      final folders = [
        for (final t in found)
          if (t.$3 == CubaseTrackType.folder) t.$1,
      ];
      final devices = [
        for (final t in found)
          if (t.$3 == CubaseTrackType.group) t.$1,
      ];
      _Instance? ioFolder;
      for (final f in folders) {
        if (devices.any((d) => f.contains(d.start))) {
          ioFolder = f;
          break;
        }
      }

      // A channel's own input bus is what other channels' outputs name, so
      // a track's output is the track that owns the bus it points at.
      final channels = <_Instance, _Channel>{};
      final byBus = <int, String>{...busNames};
      for (final (instance, name, type) in found) {
        // A folder has no channel of its own; the first one inside it
        // belongs to a track within.
        if (type == CubaseTrackType.folder) continue;
        final channel = _readChannel(instance);
        if (channel == null) continue;
        channels[instance] = channel;
        if (channel.ownBus != null) byBus[channel.ownBus!] = name;
      }

      for (final (instance, name, type) in found) {
        if (identical(instance, ioFolder)) continue;
        if (ioFolder != null && ioFolder.contains(instance.start)) continue;
        final channel = channels[instance];
        final parent = _innermost(folders, instance.start);
        String? parentName;
        if (parent != null && !identical(parent, ioFolder)) {
          parentName = [
            for (final t in found)
              if (identical(t.$1, parent)) t.$2,
          ].firstOrNull;
        }
        tracks.add(CubaseTrack(
          index: tracks.length,
          name: name,
          type: type,
          parent: parentName,
          output: channel?.outBus == null ? null : byBus[channel!.outBus],
          inserts: channel?.inserts ?? const [],
        ));
      }
    }
    return tracks;
  }

  static const _trackTypes = [
    (_audio, CubaseTrackType.audio),
    (_midi, CubaseTrackType.midi),
    (_instrument, CubaseTrackType.instrument),
    (_sampler, CubaseTrackType.sampler),
    (_device, CubaseTrackType.group),
    (_folder, CubaseTrackType.folder),
  ];

  /// Raw plug-in names, one per inserted instance, internals removed.
  List<String> readPluginNames() {
    final key = _keyBytes('Plugin Name');
    final original = _keyBytes('Original Plugin Name');
    final names = <String>[];
    var from = 0;
    while (true) {
      final at = _indexOf(key, from);
      if (at < 0) break;
      from = at + key.length;
      // Type 0x0008 = string.
      if (!_has(from, 6) || _data.getUint16(from) != 8) continue;
      final value = _readValueString(from + 2);
      if (value == null) continue;
      var name = value.text;
      // A renamed instrument stores the user's label here and the real
      // plug-in in the very next attribute.
      if (_matchesAt(original, value.end) &&
          _has(value.end + original.length, 6) &&
          _data.getUint16(value.end + original.length) == 8) {
        final orig = _readValueString(value.end + original.length + 2);
        if (orig != null && orig.text.isNotEmpty) name = orig.text;
      }
      if (_internalPlugins.contains(name.trim())) continue;
      names.add(name);
    }
    return names.isEmpty ? _devicePathPlugins() : names;
  }

  /// An attribute's string value: as [_readString] reads it, or as Cubase 4
  /// writes it — the length, then exactly that many bytes, no NUL. Read the
  /// other way, every Cubase 4 plug-in was rejected.
  ({String text, int end})? _readValueString(int offset) {
    final terminated = _readString(offset);
    if (terminated != null) return terminated;
    if (!_has(offset, 4)) return null;
    final len = _data.getUint32(offset);
    if (len < 1 || len > 256 || !_has(offset + 4, len)) return null;
    final raw = bytes.sublist(offset + 4, offset + 4 + len);
    if (raw.any((b) => b < 0x20)) return null;
    return (text: utf8.decode(raw, allowMalformed: true), end: offset + 4 + len);
  }

  /// Plug-ins as Cubase SX 3 names them, with no `Plugin Name` attributes:
  /// the devices' paths, a `CONT` string per step — "VST Instruments",
  /// "Slot 3", "Vanguard 2"; "Inserts", "Slot 2", "Sonalksis TBK Stereo 4".
  /// The step after a slot is the plug-in, numbered after its first
  /// instance; the number is dropped when the name also appears without it
  /// or with another — "Pro-Q 3" alone keeps its 3.
  List<String> _devicePathPlugins() {
    final steps = <String>[];
    final tag = ascii.encode('CONT');
    var from = 0;
    while (true) {
      final at = _indexOf(tag, from);
      if (at < 0) break;
      from = at + tag.length;
      final step = _readString(from);
      if (step != null && step.text.isNotEmpty) steps.add(step.text);
    }
    final raw = <String>[];
    for (var i = 1; i + 1 < steps.length; i++) {
      if (_slot.hasMatch(steps[i]) &&
          (steps[i - 1] == 'VST Instruments' || steps[i - 1] == 'Inserts')) {
        raw.add(steps[i + 1]);
      }
    }
    final numbers = <String, Set<String>>{};
    for (final name in raw) {
      final m = _instance.firstMatch(name);
      (numbers[m == null ? name : m[1]!] ??= {}).add(m == null ? '' : m[2]!);
    }
    return [
      for (final name in raw)
        switch (_instance.firstMatch(name)) {
          final m? when numbers[m[1]!]!.length > 1 => m[1]!,
          _ => name,
        },
    ].where((n) => !_internalPlugins.contains(n.trim())).toList();
  }

  static final _slot = RegExp(r'^Slot( \d+)?$');
  static final _instance = RegExp(r'^(.+?) (\d+)$');

  /// Every distinct MIDI part in the project, trimmed to what it plays.
  List<MidiClip> readMidiClips() {
    final clips = <MidiClip>[];
    for (final index in _indices) {
      final parts = index.instancesOf('MMidiPart');
      if (parts.isEmpty) continue;
      final events = index.instancesOf('MMidiPartEvent')
        ..sort((a, b) => a.start.compareTo(b.start));
      final noteTracks = [
        for (final cls in [_instrument, _midi, _sampler])
          ...index.instancesOf(cls).where((i) => _trackName(i) != null),
      ]..sort((a, b) => a.start.compareTo(b.start));

      for (final part in parts) {
        final name = _readString(part.body);
        if (name == null) continue;
        final event = _innermost(events, part.start);
        // A part outside any part event can't be windowed — skip it rather
        // than guess at its length.
        if (event == null) continue;
        final length = _f64(event.body + 10);
        if (length == null || !(length > 0) || length > 1e9) continue;
        final lengthTicks = length.round();

        final raw = _readNotes(part.body, part.end);
        final notes = windowMidiNotes(raw,
            windowStart: 0, windowLength: lengthTicks);
        final track = _innermost(noteTracks, part.start);
        clips.add(MidiClip(
          name: name.text,
          trackName: track == null ? null : _trackName(track),
          ppq: ppq,
          lengthTicks: lengthTicks,
          notes: notes,
        ));
      }
    }
    return dedupeMidiClips(clips);
  }

  /// Every audio file the project references.
  ///
  /// * The pool: each file is an `FNPath` object whose body starts with the
  ///   file name as a string, then the type ("WAVE", the extension twice, a
  ///   description) and the folder it is in, absolute and ending in a
  ///   separator.
  /// * The Sampler Track's sample: a `PSamplerTrackAudioClip` holding an
  ///   `FNPath` of its own, read the same way and marked [SampleUse.sampler].
  /// * Plug-in state, inline in the archive, searched for absolute paths.
  ///
  /// A pool file named after a track and a take number ("Vocals_03.wav") is
  /// a recording; "kick-01.wav" beside "kick.wav" is what Cubase writes when
  /// it processes or bounces a file.
  List<SampleReference> readSampleReferences() {
    final pool = <({String name, String dir, bool sampler})>[];
    for (final index in _indices) {
      final samplerClips = index.instancesOf('PSamplerTrackAudioClip');
      for (final fn in index.instancesOf('FNPath')) {
        final name = _readString(fn.body);
        if (name == null || name.end > fn.end) continue;
        if (!isSampleAudioFile(name.text)) continue;
        String? dir;
        for (var o = name.end; o + 4 < fn.end; o++) {
          final s = _readString(o);
          if (s == null || s.end > fn.end || s.text.length < 2) continue;
          if (s.text.endsWith(r'\') || s.text.endsWith('/')) {
            dir = s.text;
            break;
          }
        }
        if (dir == null) continue;
        pool.add((
          name: name.text,
          dir: dir,
          sampler: samplerClips.any((c) => c.contains(fn.start)),
        ));
      }
    }

    final names = {for (final f in pool) _stem(f.name).toLowerCase()};
    final trackNames = [for (final t in readTracks()) t.name];
    // A file the Sampler Track plays is listed once, as a sampler sample,
    // even when the pool lists it too.
    final inSampler = {
      for (final f in pool)
        if (f.sampler) '${f.dir}${f.name}'.toLowerCase(),
    };
    final refs = <SampleReference>[];
    final seen = <String>{};
    for (final f in pool) {
      final path = '${f.dir}${f.name}';
      if (!seen.add(path.toLowerCase())) continue;
      if (inSampler.contains(path.toLowerCase())) {
        // Loaded into a sampler to be played: a sample, whatever its name
        // says ("kick-01.wav" beside "kick.wav" is a trimmed or tuned copy
        // of a sample, not a bounce of the song).
        refs.add(SampleReference(
          fileName: f.name,
          candidates: [path, 'Audio/${f.name}'],
          use: SampleUse.sampler,
        ));
        continue;
      }
      final copyOf = _processedCopy.firstMatch(_stem(f.name));
      final SampleKind? kind =
          looksLikeRecording(f.name, trackNames, r'_\d{2,3}(-\d{2})?')
              ? SampleKind.recorded
              : copyOf != null && names.contains(copyOf[1]!.toLowerCase())
                  ? SampleKind.processed
                  : null;
      refs.add(SampleReference(
        fileName: f.name,
        candidates: [path, 'Audio/${f.name}'],
        kind: kind,
      ));
    }
    for (final path in findEmbeddedAudioPaths(bytes)) {
      if (!seen.add(path.toLowerCase())) continue;
      refs.add(SampleReference(
        fileName: sampleFileNameOf(path),
        candidates: [path],
        use: SampleUse.plugin,
      ));
    }
    return refs;
  }

  static final _processedCopy = RegExp(r'^(.+)-\d{2}$');

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  // --- notes ---------------------------------------------------------------

  /// The version of Cubase/Nuendo that saved [bytes] ("11.0.41"), from the
  /// `PAppVersion` record: a big-endian u32 length, "Version 11.0.41" and a
  /// NUL. Cubase 6 and later write it first, SX, 4 and 5 last. Null when
  /// there is none.
  static String? appVersion(Uint8List bytes) {
    const tag = [0x56, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E, 0x20]; // "Version "
    final data = ByteData.sublistView(bytes);
    outer:
    for (var i = 4; i + tag.length < bytes.length; i++) {
      for (var j = 0; j < tag.length; j++) {
        if (bytes[i + j] != tag[j]) continue outer;
      }
      final length = data.getUint32(i - 4, Endian.big);
      final end = i + length - 1; // the NUL
      if (length < tag.length + 2 || length > 32 || end >= bytes.length || bytes[end] != 0) {
        continue;
      }
      final text = String.fromCharCodes(bytes.sublist(i + tag.length, end));
      if (_versionText.hasMatch(text)) return text;
    }
    return null;
  }

  static final _versionText = RegExp(r'^\d+(\.\d+)*$');

  /// Whether Cubase SX, 4 or 5 saved this — they write notes as
  /// [_legacyNote]s.
  late final bool _legacy = switch (appVersion(bytes)) {
    final v? => (int.tryParse(v.split('.').first) ?? 99) <= 5,
    null => false,
  };

  /// A note as Cubase SX, 4 and 5 write it, at [o]: status, start (f64),
  /// channel, pitch, velocity, a flags byte (2 on nearly every note), four
  /// zero bytes, no attributes, the length (f64), 16 zero bytes and the
  /// note-off velocity — 43 bytes. Measured across 115,000 notes of 51 real
  /// projects; null where [o] holds no such record.
  MidiNote? _legacyNote(int o, int end) {
    if (o + 43 > end) return null;
    final status = bytes[o];
    if (status < 0x90 || status > 0x9F) return null;
    if (bytes[o + 9] > 0x0F || bytes[o + 10] > 0x7F || bytes[o + 11] > 0x7F) return null;
    for (var i = 13; i <= 17; i++) {
      if (bytes[o + i] != 0) return null;
    }
    for (var i = 26; i < 42; i++) {
      if (bytes[o + i] != 0) return null;
    }
    final startTick = _f64(o + 1), length = _f64(o + 18);
    if (startTick == null ||
        length == null ||
        !(length >= 0 && length < 1e8) ||
        !(startTick > -1e9 && startTick < 1e9)) {
      return null;
    }
    final velocity = bytes[o + 11];
    return MidiNote(
      startTick: startTick.round(),
      lengthTicks: length.round() < 1 ? 1 : length.round(),
      pitch: bytes[o + 10],
      velocity: velocity == 0 ? 1 : velocity,
      channel: status & 0x0F,
    );
  }

  List<MidiNote> _readNotes(int start, int end) {
    final notes = <MidiNote>[];
    var o = start;
    while (o + 18 < end) {
      if (_legacy) {
        final note = _legacyNote(o, end);
        if (note != null) {
          notes.add(note);
          o += 43;
        } else {
          o++;
        }
        continue;
      }
      final status = bytes[o];
      if (status < 0x90 ||
          status > 0x9F ||
          bytes[o + 9] > 0x0F ||
          bytes[o + 10] > 0x7F ||
          bytes[o + 11] > 0x7F ||
          bytes[o + 12] != 0 ||
          bytes[o + 13] != 0 ||
          bytes[o + 14] != 0 ||
          bytes[o + 15] != 0 ||
          bytes[o + 16] != 0) {
        o++;
        continue;
      }
      final attrCount = bytes[o + 17];
      if (attrCount < 1 || attrCount > 16) {
        o++;
        continue;
      }
      var q = o + 18;
      var ok = true;
      for (var i = 0; i < attrCount; i++) {
        if (q + 14 > end) {
          ok = false;
          break;
        }
        final type = _data.getUint16(q + 4);
        if (type != 1 && type != 4) {
          ok = false;
          break;
        }
        q += 14; // tag(4) + type(2) + 8-byte value
      }
      if (!ok || q + 24 > end) {
        o++;
        continue;
      }
      final startTick = _f64(o + 1);
      final length = _f64(q);
      if (startTick == null ||
          length == null ||
          !(length >= 0 && length < 1e8) ||
          !(startTick > -1e9 && startTick < 1e9)) {
        o++;
        continue;
      }
      final velocity = bytes[o + 11];
      notes.add(MidiNote(
        startTick: startTick.round(),
        lengthTicks: length.round() < 1 ? 1 : length.round(),
        pitch: bytes[o + 10],
        velocity: velocity == 0 ? 1 : velocity,
        channel: status & 0x0F,
      ));
      o = q + 24;
    }
    return notes;
  }

  // --- mixer channel ---------------------------------------------------

  static final _channelKey = _keyBytes('VST Multitrack');
  static final _insertFolderKey = _keyBytes('InsertFolder');
  static final _slotTypeKey = _keyBytes('SlotType');
  static final _slotStateKey = _keyBytes('State');
  static final _pluginNameKey = _keyBytes('Plugin Name');
  static final _ownInputBusKey = _keyBytes('OwnInputBus');
  static final _busUidKey = _keyBytes('Bus UID');
  static final _outputBusKey = _keyBytes('OutputBusValue');
  static final _valueKey = _keyBytes('Value');
  static final _nameKey = _keyBytes('Name');
  // What follows the insert slots: the strip, then the send slots.
  static final _afterInsertKeys = [
    _keyBytes('hasAudioStrips'),
    _keyBytes('StripFolder'),
    _keyBytes('SendFolder'),
  ];

  /// A track's mixer channel, which sits inside the track's own object:
  /// its insert slots, and the buses it takes sound from and sends it to.
  /// Null when the track holds no channel.
  _Channel? _readChannel(_Instance track) {
    final start = _indexOfIn(_channelKey, track.body, track.end);
    if (start < 0) return null;
    final end = track.end;

    final ownAt = _indexOfIn(_ownInputBusKey, start, end);
    final ownBus =
        ownAt < 0 ? null : _intAfterKey(_busUidKey, ownAt, end)?.value;
    final outAt = _indexOfIn(_outputBusKey, start, end);
    final outBus = outAt < 0
        ? null
        : _intAfterKey(_valueKey, outAt + _outputBusKey.length,
                outAt + _outputBusKey.length + 80)
            ?.value;

    final inserts = <CubaseInsert>[];
    final folder = _indexOfIn(_insertFolderKey, start, end);
    if (folder >= 0) {
      var folderEnd = end;
      for (final key in _afterInsertKeys) {
        final at = _indexOfIn(key, folder, end);
        if (at >= 0 && at < folderEnd) folderEnd = at;
      }
      var slot = -1;
      bool? bypassed;
      var at = folder;
      while (true) {
        final nextSlot = _indexOfIn(_slotTypeKey, at, folderEnd);
        final nextPlugin = _indexOfIn(_pluginNameKey, at, folderEnd);
        if (nextPlugin < 0) break;
        if (nextSlot >= 0 && nextSlot < nextPlugin) {
          slot++;
          // A slot's State, written just before its SlotType, is 1 while the
          // plug-in is on and 0 once it is bypassed.
          final state =
              _intAfterKey(_slotStateKey, nextSlot - 30, nextSlot)?.value;
          bypassed = state == null ? null : state == 0;
          at = nextSlot + _slotTypeKey.length;
          continue;
        }
        final after = nextPlugin + _pluginNameKey.length;
        at = after;
        if (slot < 0 || !_has(after, 6) || _data.getUint16(after) != 8) continue;
        final name = _readString(after + 2)?.text;
        if (name != null && name.isNotEmpty) {
          inserts.add(CubaseInsert(slot: slot, plugin: name, bypassed: bypassed));
        }
      }
    }
    return _Channel(ownBus: ownBus, outBus: outBus, inserts: inserts);
  }

  /// Bus UID → bus name for every channel's own input bus. Output devices
  /// ("Stereo Out") are only named here; tracks are named by their track.
  Map<int, String> _busOwnerNames() {
    final names = <int, String>{};
    var from = 0;
    while (true) {
      final at = _indexOf(_ownInputBusKey, from);
      if (at < 0) break;
      from = at + _ownInputBusKey.length;
      final limit = from + 300;
      final uid = _intAfterKey(_busUidKey, from, limit)?.value;
      final nameAt = _indexOfIn(_nameKey, from, limit);
      if (uid == null || nameAt < 0) continue;
      final value = nameAt + _nameKey.length;
      if (!_has(value, 6) || _data.getUint16(value) != 8) continue;
      final name = _readString(value + 2)?.text;
      if (name != null) names[uid] = name;
    }
    return names;
  }

  /// The integer stored under [key] when it appears in `[from, to)`.
  ({int value, int end})? _intAfterKey(List<int> key, int from, int to) {
    final at = _indexOfIn(key, from, to);
    if (at < 0) return null;
    final value = at + key.length;
    // Type 0x0001 = integer, stored as 8 bytes.
    if (!_has(value, 10) || _data.getUint16(value) != 1) return null;
    return (value: _data.getInt64(value + 2), end: value + 10);
  }

  int _indexOfIn(List<int> pattern, int from, int to) {
    final first = pattern[0];
    final last = (to < bytes.length ? to : bytes.length) - pattern.length;
    outer:
    for (var i = from; i <= last; i++) {
      if (bytes[i] != first) continue;
      for (var j = 1; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  // --- archive helpers -----------------------------------------------------

  /// Built once per parser: indexing walks the whole file twice.
  late final List<_ArchiveIndex> _indices = [
    for (final chunk in _archChunks()) _ArchiveIndex.build(this, chunk),
  ];

  List<(int, int)> _archChunks() {
    final chunks = <(int, int)>[];
    var off = 12;
    while (off + 8 <= bytes.length) {
      final id = _ascii(off, 4);
      final size = _data.getUint32(off + 4);
      final start = off + 8;
      final end = start + size;
      if (end > bytes.length) break;
      if (id == 'ARCH') chunks.add((start, end));
      off = end;
    }
    return chunks;
  }

  /// The name every track object carries in its node, or null when the
  /// candidate isn't really a track (a stray 4-byte match).
  String? _trackName(_Instance track) {
    final node = track.body + 26;
    if (!_has(node, 12)) return null;
    int namePos;
    if (_data.getUint32(node) == 0xFFFFFFFF) {
      final len = _data.getUint32(node + 4);
      if (len > 128) return null;
      namePos = node + 8 + len + 2 + 4;
    } else if (bytes[node] == 0x80) {
      namePos = node + 8;
    } else {
      return null;
    }
    if (namePos >= track.end) return null;
    return _readString(namePos)?.text;
  }

  _Instance? _innermost(List<_Instance> sorted, int offset) {
    // Instances are nested, never partially overlapping, so the last one
    // starting before [offset] that also contains it is the innermost.
    _Instance? found;
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].start < offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo - 1; i >= 0; i--) {
      if (sorted[i].contains(offset)) {
        found = sorted[i];
        break;
      }
    }
    return found;
  }

  ({String text, int end})? _readString(int offset) {
    if (!_has(offset, 4)) return null;
    final len = _data.getUint32(offset);
    if (len < 1 || len > 4096 || !_has(offset + 4, len)) return null;
    var stop = offset + 4 + len;
    // Newer versions append a UTF-8 BOM after the NUL.
    if (len >= 4 &&
        bytes[stop - 3] == 0xEF &&
        bytes[stop - 2] == 0xBB &&
        bytes[stop - 1] == 0xBF) {
      stop -= 3;
    }
    if (bytes[stop - 1] != 0) return null;
    final text = utf8.decode(
      bytes.sublist(offset + 4, stop - 1),
      allowMalformed: true,
    );
    return (text: text, end: offset + 4 + len);
  }

  double? _f64(int offset) {
    if (!_has(offset, 8)) return null;
    final v = _data.getFloat64(offset);
    return v.isFinite ? v : null;
  }

  bool _has(int offset, int length) =>
      offset >= 0 && offset + length <= bytes.length;

  String _ascii(int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));

  /// `u32 length` + name + NUL, the way attribute keys are written.
  static List<int> _keyBytes(String key) {
    final n = key.length + 1;
    return [
      (n >> 24) & 0xFF,
      (n >> 16) & 0xFF,
      (n >> 8) & 0xFF,
      n & 0xFF,
      ...ascii.encode(key),
      0,
    ];
  }

  bool _matchesAt(List<int> pattern, int offset) {
    if (!_has(offset, pattern.length)) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[offset + i] != pattern[i]) return false;
    }
    return true;
  }

  int _indexOf(List<int> pattern, int from) {
    final first = pattern[0];
    final last = bytes.length - pattern.length;
    outer:
    for (var i = from; i <= last; i++) {
      if (bytes[i] != first) continue;
      for (var j = 1; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

/// What a Cubase track is, in the words the template export uses.
/// [group] covers every device track that is not an output: group and FX
/// channels are not told apart.
enum CubaseTrackType { audio, instrument, midi, sampler, group, folder }

/// One track as [CubaseProjectParser.readTracks] finds it.
class CubaseTrack {
  const CubaseTrack({
    required this.index,
    required this.name,
    required this.type,
    this.parent,
    this.output,
    this.inserts = const [],
  });

  final int index;
  final String name;
  final CubaseTrackType type;

  /// Name of the folder holding the track, or null at the top level.
  final String? parent;

  /// Where the channel's output goes: the name of the group or bus channel,
  /// or of an output such as "Stereo Out". Null when it could not be read.
  final String? output;

  /// Plug-ins in the channel's insert slots, in slot order.
  final List<CubaseInsert> inserts;
}

/// One plug-in in an insert slot, counted from 0 as Cubase lists them.
class CubaseInsert {
  const CubaseInsert({required this.slot, required this.plugin, this.bypassed});
  final int slot;
  final String plugin;

  /// Whether the slot was bypassed when saved; null when not read.
  final bool? bypassed;
}

/// What a track's mixer channel says: the bus it owns for others to send to,
/// the bus its output goes to, and its insert plug-ins.
class _Channel {
  const _Channel({this.ownBus, this.outBus, this.inserts = const []});
  final int? ownBus;
  final int? outBus;
  final List<CubaseInsert> inserts;
}

/// One object in an archive: its body spans `[body, end)`. [start] is where
/// its size field sits, used for ordering and containment.
class _Instance {
  const _Instance(this.start, this.body, this.end);
  final int start;
  final int body;
  final int end;
  bool contains(int offset) => offset > start && offset < end;
}

/// Class definitions of one ARCH chunk and every instance of each.
class _ArchiveIndex {
  _ArchiveIndex._(this._instances);

  final Map<String, List<_Instance>> _instances;

  List<_Instance> instancesOf(String cls) =>
      List.of(_instances[cls] ?? const <_Instance>[]);

  static final _validName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static _ArchiveIndex build(CubaseProjectParser p, (int, int) chunk) {
    final (start, end) = chunk;
    final bytes = p.bytes;
    final data = p._data;
    final instances = <String, List<_Instance>>{};
    // ref tag -> class name, for every class defined in this chunk.
    final refs = <int, String>{};

    void addInstance(String cls, int sizePos) {
      if (sizePos + 4 > end) return;
      final size = data.getUint32(sizePos);
      final body = sizePos + 4;
      if (size == 0 || body + size > end) return;
      (instances[cls] ??= []).add(_Instance(sizePos, body, body + size));
    }

    // Pass 1: class definitions.
    for (var o = start; o + 8 <= end; o++) {
      if (bytes[o] != 0xFF ||
          bytes[o + 1] != 0xFF ||
          bytes[o + 2] != 0xFF ||
          (bytes[o + 3] != 0xFF && bytes[o + 3] != 0xFE)) {
        continue;
      }
      final n = data.getUint32(o + 4);
      if (n < 2 || n > 64 || o + 8 + n + 2 > end) continue;
      if (bytes[o + 8 + n - 1] != 0) continue;
      final name = String.fromCharCodes(bytes.sublist(o + 8, o + 8 + n - 1));
      if (!_validName.hasMatch(name)) continue;
      refs[0x80000000 | (o - start)] = name;
      // FF..FF defines a class *and* an instance of it; FF..FE only a class.
      if (bytes[o + 3] == 0xFF) addInstance(name, o + 8 + n + 2);
    }

    // Pass 2: back-references. Only classes we were asked about matter, but
    // filtering here would cost more than it saves.
    final maxTop = 0x80 + ((end - start) >> 24);
    for (var o = start; o + 8 <= end; o++) {
      final b0 = bytes[o];
      if (b0 < 0x80 || b0 > maxTop) continue;
      final cls = refs[data.getUint32(o)];
      if (cls == null) continue;
      addInstance(cls, o + 4);
    }
    return _ArchiveIndex._(instances);
  }
}
