/// How a project uses an audio file it references.
enum SampleUse {
  /// Placed on the timeline (an audio event, clip or item).
  audio,

  /// Loaded into the DAW's own sampler (Simpler, Sampler Track, FL's
  /// channel sampler, ReaSamplOmatic5000…).
  sampler,

  /// Found as a path inside a third-party plug-in's saved state.
  plugin,
}

/// What the DAW itself says a referenced file is, where it says anything.
enum SampleKind {
  /// Brought in from somewhere else — a sample.
  imported,

  /// Recorded in the project.
  recorded,

  /// Made by the DAW from other audio: a bounce, freeze, consolidation,
  /// render or offline-processed copy.
  processed,
}

/// One audio file a project references, as the project names it.
///
/// A project's paths are often stale — the project was moved, the drive
/// letter changed, the library was reorganised — so [candidates] lists every
/// place the project's own data says the file could be, most specific first,
/// and finding it is left to the sample locator, which also falls back to
/// searching by [fileName].
class SampleReference {
  const SampleReference({
    required this.fileName,
    required this.candidates,
    this.use = SampleUse.audio,
    this.kind,
    this.sizeBytes,
  });

  /// The file's name, which is what a search falls back to.
  final String fileName;

  /// Where the project says the file is: absolute paths, or paths relative
  /// to the project's folder. Never empty in practice; may name a path that
  /// no longer exists.
  final List<String> candidates;

  final SampleUse use;

  /// What the DAW says the file is; null when it says nothing.
  final SampleKind? kind;

  /// The file's size as the project recorded it, to tell same-named files
  /// apart when searching. Null when the format doesn't store it.
  final int? sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is SampleReference &&
      other.fileName == fileName &&
      other.use == use &&
      other.kind == kind &&
      other.sizeBytes == sizeBytes &&
      _listEquals(other.candidates, candidates);

  @override
  int get hashCode =>
      Object.hash(fileName, use, kind, sizeBytes, Object.hashAll(candidates));

  @override
  String toString() =>
      'SampleReference($fileName, $use, ${kind?.name}, $candidates)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Audio file extensions a sample pack collects, lower case with the dot.
const kSampleAudioExtensions = {
  '.wav',
  '.wave',
  '.aif',
  '.aiff',
  '.flac',
  '.mp3',
  '.ogg',
  '.m4a',
  '.rx2',
  '.rex',
};

/// Whether [name] (a file name or path) ends in one of
/// [kSampleAudioExtensions].
bool isSampleAudioFile(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return kSampleAudioExtensions.contains(name.substring(dot).toLowerCase());
}

/// Whether [fileName] is how a DAW names a recording on one of [trackNames]:
/// the track's name and then [takeSuffix], a regular expression for what
/// the DAW appends to a take (Cubase: `_\d{2}`, "Vocals_03.wav").
///
/// Only a track's own name followed by exactly that counts, so an imported
/// "Kick 2013.wav" on a track called "Kick" stays a sample.
bool looksLikeRecording(
  String fileName,
  Iterable<String> trackNames,
  String takeSuffix,
) {
  final dot = fileName.lastIndexOf('.');
  final stem = (dot < 0 ? fileName : fileName.substring(0, dot)).toLowerCase();
  for (final raw in trackNames) {
    final track = raw.trim().toLowerCase();
    if (track.isEmpty) continue;
    if (RegExp('^${RegExp.escape(track)}$takeSuffix\$').hasMatch(stem)) {
      return true;
    }
  }
  return false;
}

/// The last path segment of [path], whichever separator it uses — a Windows
/// path read on another platform must still give its file name.
String sampleFileNameOf(String path) {
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? path : path.substring(cut + 1);
}
