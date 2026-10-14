import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/project_stats.dart';
import '../../models/sample_reference.dart';
import 'embedded_audio_paths.dart';

/// What [StudioOneProjectParser] can read from a `.song`.
class StudioOneProjectInfo {
  const StudioOneProjectInfo({this.bpm, this.dawVersion, this.stats});
  final double? bpm;
  final String? dawVersion;
  final ProjectStats? stats;
}

/// Reads tempo, version and track counts out of a Studio One `.song`.
///
/// A `.song` is a zip of XML documents:
/// * `metainfo.xml` — `<Attribute id="Media:Tempo" value="…"/>` and
///   `id="Document:Generator"` (`"Studio One/6.5.1.96553"`).
/// * `Song/song.xml` — the track list: `MediaTrack` elements whose
///   `mediaType` is `Audio` or `Music` (instrument tracks), and
///   `FolderTrack`s.
/// * `Devices/audiomixer.xml` — bus and FX channels (`AudioBusChannel`,
///   `AudioEffectChannel`).
///
/// Implemented from the format's public descriptions, without a real file
/// to check against, so every read is defensive: a missing entry or an
/// unexpected shape costs that one value, never the others. Plug-ins and
/// MIDI clips aren't read yet.
class StudioOneProjectParser {
  StudioOneProjectParser(this.bytes);

  final Uint8List bytes;

  StudioOneProjectInfo read() {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const StudioOneProjectInfo();
    }

    XmlDocument? doc(String path) {
      final file = archive.findFile(path);
      if (file == null) return null;
      try {
        return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
      } catch (_) {
        return null;
      }
    }

    double? bpm;
    String? version;
    final meta = doc('metainfo.xml');
    if (meta != null) {
      for (final a in meta.findAllElements('Attribute')) {
        final id = a.getAttribute('id');
        final value = a.getAttribute('value');
        if (value == null) continue;
        if (id == 'Media:Tempo') {
          final v = double.tryParse(value);
          if (v != null && v > 0 && v < 1000) bpm = v;
        } else if (id == 'Document:Generator') {
          final m = RegExp(r'(\d+)\.(\d+)').firstMatch(value);
          if (m != null) version = '${m.group(1)}.${m.group(2)}';
        }
      }
    }

    ProjectStats? stats;
    final song = doc('Song/song.xml');
    if (song != null) {
      var audio = 0, instrument = 0, folder = 0, bus = 0;
      for (final e in song.descendantElements) {
        switch (e.name.local) {
          case 'MediaTrack':
            switch (e.getAttribute('mediaType')) {
              case 'Audio':
                audio++;
              case 'Music':
                instrument++;
            }
          case 'FolderTrack':
            folder++;
        }
      }
      final mixer = doc('Devices/audiomixer.xml');
      if (mixer != null) {
        for (final e in mixer.descendantElements) {
          final n = e.name.local;
          if (n == 'AudioBusChannel' || n == 'AudioEffectChannel') bus++;
        }
      }
      stats = ProjectStats(
        audioTracks: audio,
        instrumentTracks: instrument,
        folderTracks: folder,
        busTracks: bus,
      );
    }

    return StudioOneProjectInfo(bpm: bpm, dawVersion: version, stats: stats);
  }

  /// Every audio file the song references.
  ///
  /// * `Song/mediapool.xml` lists each one once as an `AudioClip` whose
  ///   `Url` is a `file:///` URL (absolute, percent-encoded). Studio One
  ///   keeps a song's own audio in its `Media` folder, which is tried too.
  /// * Instrument and effect state is stored as files under `Presets/`
  ///   (Sample One, Impact XT, third-party `.fxb`s) and searched for
  ///   absolute paths.
  List<SampleReference> readSampleReferences() {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const [];
    }
    final refs = <SampleReference>[];
    final pool = archive.findFile('Song/mediapool.xml');
    if (pool != null) {
      try {
        final doc = XmlDocument.parse(
          utf8.decode(pool.content, allowMalformed: true),
        );
        for (final clip in doc.findAllElements('AudioClip')) {
          for (final url in clip.findElements('Url')) {
            final path = _filePathOfUrl(url.getAttribute('url'));
            if (path == null || !isSampleAudioFile(path)) continue;
            final name = sampleFileNameOf(path);
            refs.add(SampleReference(
              fileName: name,
              candidates: [path, 'Media/$name'],
            ));
          }
        }
      } catch (_) {
        // An unreadable pool costs the pool, not the presets.
      }
    }
    for (final file in archive.files) {
      if (!file.isFile || !file.name.startsWith('Presets/')) continue;
      for (final path in findEmbeddedAudioPaths(file.content)) {
        refs.add(SampleReference(
          fileName: sampleFileNameOf(path),
          candidates: [path],
          use: file.name.startsWith('Presets/Synths/')
              ? SampleUse.sampler
              : SampleUse.plugin,
        ));
      }
    }
    return refs;
  }

  /// `file:///G:/Pack/Kick%20(1).wav` → `G:/Pack/Kick (1).wav`;
  /// `file:///Users/me/kick.wav` → `/Users/me/kick.wav`.
  static String? _filePathOfUrl(String? url) {
    if (url == null || !url.startsWith('file:')) return null;
    var rest = url.substring(5);
    while (rest.startsWith('//')) {
      rest = rest.substring(1);
    }
    String decoded;
    try {
      decoded = Uri.decodeFull(rest);
    } catch (_) {
      decoded = rest;
    }
    // "/G:/…" is a Windows path behind the URL's leading slash.
    if (RegExp(r'^/[A-Za-z]:[\\/]').hasMatch(decoded)) {
      decoded = decoded.substring(1);
    }
    return decoded;
  }
}
