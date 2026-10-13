import 'package:path/path.dart' as p;

import '../../models/sample_reference.dart';

/// The folder a sample goes in, in the pack.
enum SampleCategory {
  kick('Kick'),
  snare('Snare'),
  clap('Clap'),
  hiHat('Hi-Hat'),
  cymbal('Cymbal'),
  percussion('Percussion'),
  drumLoop('Drum Loop'),
  bass('Bass'),
  synth('Synth'),
  pad('Pad'),
  keys('Keys'),
  guitar('Guitar'),
  vocal('Vocal'),
  fx('FX'),
  atmosphere('Atmosphere'),
  loop('Loop'),
  oneShot('One-Shot'),
  other('Other');

  const SampleCategory(this.folder);

  /// The folder name, and the word a file name is given when it doesn't
  /// already say what it is. English on purpose: the pack is files, read in
  /// a DAW's browser, like the MIDI exports' "4 bars".
  final String folder;

  /// Whether the category says what the sound is. Loop, One-Shot and Other
  /// only say what it isn't, so no file is renamed after them.
  bool get isSpecific =>
      this != SampleCategory.loop &&
      this != SampleCategory.oneShot &&
      this != SampleCategory.other;
}

/// Where a sample came from, which decides whether it is in the pack by
/// default.
enum SampleOrigin {
  /// Outside the project's folder: a sample library.
  library,

  /// Inside the project's folder but not made there: imported and copied in.
  project,

  /// Recorded in the project.
  recorded,

  /// A bounce, freeze, render, consolidation or processed copy.
  processed,

  /// Long enough to be a stem or a full recording rather than a sample.
  long;

  /// Audio the user made, or a whole track — only in the pack when asked.
  bool get isOwnAudio =>
      this == SampleOrigin.recorded ||
      this == SampleOrigin.processed ||
      this == SampleOrigin.long;
}

/// From this length on, a file is a stem or a full take, not a sample.
const kLongAudio = Duration(seconds: 90);

/// Folders DAWs record into.
const _recordedFolders = {'recorded', 'recordings', 'recording'};

/// Folders DAWs put audio they make into: Cubase's Edits and Freeze,
/// Ableton's Processed (Consolidate, Crop, Reverse, Freeze), FL's Rendered,
/// and where mixdowns, bounces and stems are written.
const _processedFolders = {
  'edits',
  'freeze',
  'freezes',
  'frozen',
  'processed',
  'consolidate',
  'crop',
  'reverse',
  'rendered',
  'renders',
  'render',
  'bounces',
  'bounce',
  'bounced files',
  'mixdown',
  'mixdowns',
  'stems',
};

/// What REAPER, Studio One and others append to a file they render from
/// other audio.
final _processedName = RegExp(
  r'([-_ ](glued|render|rendered|bounce|bounced|reversed|consolidated))$|\((rendered|bounce|bounced)\)$',
  caseSensitive: false,
);

/// Where the sample at [path] came from, as one of a project's references.
///
/// What the DAW said ([kind]) wins; then a [duration] of [kLongAudio] or
/// more; then the folders between [projectDir] and the file; then whether
/// the file is inside the project's folder at all.
SampleOrigin sampleOriginOf({
  required String path,
  required String projectDir,
  SampleKind? kind,
  Duration? duration,
}) {
  if (kind == SampleKind.recorded) return SampleOrigin.recorded;
  if (kind == SampleKind.processed) return SampleOrigin.processed;
  if (duration != null && duration >= kLongAudio) return SampleOrigin.long;
  final within = p.isWithin(p.normalize(projectDir), p.normalize(path));
  if (!within) return SampleOrigin.library;
  if (kind == SampleKind.imported) return SampleOrigin.project;
  final folders = p
      .split(p.relative(p.dirname(p.normalize(path)), from: p.normalize(projectDir)))
      .map((s) => s.toLowerCase());
  if (folders.any(_recordedFolders.contains)) return SampleOrigin.recorded;
  if (folders.any(_processedFolders.contains)) return SampleOrigin.processed;
  if (_processedName.hasMatch(p.basenameWithoutExtension(path))) {
    return SampleOrigin.processed;
  }
  return SampleOrigin.project;
}

/// One sample's origin across every project that uses it: its own audio if
/// any project says so (a recording copied into a second project is still a
/// recording), else from a library if any project took it from one.
SampleOrigin combinedOrigin(Iterable<SampleOrigin> origins) {
  final all = origins.toSet();
  for (final own in [
    SampleOrigin.recorded,
    SampleOrigin.processed,
    SampleOrigin.long,
  ]) {
    if (all.contains(own)) return own;
  }
  return all.contains(SampleOrigin.library)
      ? SampleOrigin.library
      : SampleOrigin.project;
}

/// Words that say what a sound is, checked in this order: a sample called
/// "Bass Drum" is a kick, "Vocal FX" a vocal, "Sweep Con Crash" an effect.
/// Portuguese and Spanish drum names are in too ("Prato 01", "Platillos").
const _categoryWords = <(SampleCategory, Set<String>)>[
  (
    SampleCategory.vocal,
    {
      'vox', 'vocal', 'vocals', 'voc', 'acapella', 'acappella', 'voice',
      'voices', 'speech', 'dialog', 'dialogue', 'spoken', 'chant', 'chants',
      'shout', 'phrase', 'phrases', 'rap', 'sing', 'singer', 'talk',
      'scream', 'adlib', 'adlibs', 'voz',
    },
  ),
  (
    SampleCategory.kick,
    {'kick', 'kicks', 'kik', 'kck', 'bd', 'bassdrum', 'kickdrum', 'bumbo'},
  ),
  (
    SampleCategory.snare,
    {'snare', 'snares', 'snr', 'sd', 'rim', 'rims', 'rimshot', 'caixa'},
  ),
  (SampleCategory.clap, {'clap', 'claps', 'clp', 'snap', 'snaps', 'palma'}),
  (
    SampleCategory.hiHat,
    {
      'hat', 'hats', 'hihat', 'hihats', 'hh', 'hhc', 'hho', 'chh', 'ohh',
      'closedhat', 'openhat', 'chimbal',
    },
  ),
  (
    SampleCategory.fx,
    {
      'fx', 'sfx', 'efx', 'riser', 'risers', 'uplifter', 'uplifters',
      'downlifter', 'downer', 'sweep', 'sweeps', 'swoosh', 'whoosh',
      'impact', 'impacts', 'noise', 'laser', 'lazer', 'zap', 'zaps', 'boom',
      'transition', 'reverse', 'reversed', 'scratch', 'scratching',
      'glitch', 'stutter', 'siren', 'upfilter', 'downfilter', 'buildup',
    },
  ),
  (
    SampleCategory.cymbal,
    {
      'crash', 'crashes', 'ride', 'rides', 'cymbal', 'cymbals', 'cym',
      'china', 'splash', 'prato', 'pratos', 'platillo', 'platillos',
      'prataria',
    },
  ),
  (
    SampleCategory.percussion,
    {
      'perc', 'percs', 'percussion', 'percussions', 'percus', 'shaker',
      'shakers', 'shak', 'tom', 'toms', 'conga', 'congas', 'bongo', 'bongos',
      'tamb', 'tambourine', 'cowbell', 'clave', 'claves', 'woodblock',
      'triangle', 'guiro', 'cabasa', 'timbale', 'timbales', 'tabla',
      'djembe', 'agogo', 'cuica',
    },
  ),
  (
    SampleCategory.atmosphere,
    {
      'atmo', 'atmos', 'atmosphere', 'atmospheres', 'ambience', 'ambient',
      'texture', 'textures', 'drone', 'drones', 'soundscape', 'nature',
      'rain', 'birds',
    },
  ),
  (
    SampleCategory.bass,
    {'bass', 'basses', 'bassline', 'sub', 'subbass', '808', 'reese', 'baixo'},
  ),
  (
    SampleCategory.keys,
    {
      'piano', 'keys', 'rhodes', 'organ', 'harpsichord', 'epiano', 'wurli',
      'clav', 'bell', 'bells', 'mallet', 'marimba', 'hamond', 'hammond',
    },
  ),
  (SampleCategory.guitar, {'guitar', 'guitars', 'gtr', 'violao', 'guitarra'}),
  (
    SampleCategory.pad,
    {'pad', 'pads', 'strings', 'string', 'choir', 'chord', 'chords', 'swell'},
  ),
  (
    SampleCategory.synth,
    {
      'lead', 'leads', 'synth', 'synths', 'stab', 'stabs', 'pluck', 'plucks',
      'arp', 'arps', 'seq', 'sequence', 'acid', '303', 'hoover', 'saw',
    },
  ),
];

const _drumCategories = {
  SampleCategory.kick,
  SampleCategory.snare,
  SampleCategory.clap,
  SampleCategory.hiHat,
  SampleCategory.percussion,
};

/// Words that make a drum sound a drum loop, and generic drum words.
const _drumLoopWords = {
  'groove', 'grooves', 'beat', 'beats', 'break', 'breaks', 'breakbeat',
  'fill', 'fills', 'top', 'tops', 'drumloop', 'drumloops',
};
/// The drum-loop words that mean a drum loop with no other drum word —
/// "Fill 140 BPM", "Breakbeat 03". "top", "beat" and "break" alone don't.
const _unambiguousDrumLoopWords = {
  'fill', 'fills', 'groove', 'grooves', 'breakbeat', 'drumloop', 'drumloops',
};
const _drumWords = {'drum', 'drums', 'kit', 'bateria'};
const _loopWords = {'loop', 'loops', 'bpm'};

/// Folder names that say nothing about the sounds in them.
const _genericFolders = {
  'audio', 'samples', 'sample', 'imported', 'media', 'sounds', 'sound',
  'wav', 'wavs', 'one shots', 'oneshots', 'files', 'patches', 'data',
};

/// "HIHAT233(CLSD)" → hihat, 233, clsd; "eeth_drm_kick7" → eeth, drm, kick,
/// 7; "BassDrum" → bass, drum, and the pair "bassdrum".
List<String> _words(String text) {
  final words = text
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'(\d)([A-Za-z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return [
    ...words,
    for (var i = 0; i + 1 < words.length; i++) '${words[i]}${words[i + 1]}',
  ];
}

SampleCategory? _categoryOfWords(List<String> words) {
  final set = words.toSet();
  for (final (category, hints) in _categoryWords) {
    if (hints.any(set.contains)) return category;
  }
  return null;
}

bool _saysLoop(List<String> words) =>
    words.any(_loopWords.contains) ||
    words.any((w) => RegExp(r'^\d{2,3}bpm$').hasMatch(w));

/// The category of the sample at [path], from its name, then from the
/// folders it is in (closest first; below [projectDir] only, when it is in
/// that project), then from its [duration].
///
/// A drum sound that says it is a loop, or is a drum hit over 4 seconds
/// long, is a drum loop; a cymbal can ring that long on its own.
SampleCategory sampleCategoryOf(
  String path, {
  Duration? duration,
  String? projectDir,
}) {
  final nameWords = _words(p.basenameWithoutExtension(path));
  // Inside a project only its own subfolders count: the project's folder is
  // named after the song, and "Save the Bass" says nothing about a clap.
  final folders = projectDir != null && p.isWithin(projectDir, path)
      ? p.split(p.relative(p.dirname(path), from: projectDir))
          .where((f) => f != '.')
      : p.split(p.dirname(path)).skip(1);
  final folderWords = [
    for (final folder in folders.toList().reversed.take(4))
      if (!_genericFolders.contains(folder.toLowerCase())) _words(folder),
  ];

  var category = _categoryOfWords(nameWords);
  for (final words in folderWords) {
    if (category != null) break;
    category = _categoryOfWords(words);
  }
  final allWords = [...nameWords, for (final w in folderWords) ...w];
  final seconds = (duration?.inMilliseconds ?? 0) / 1000;
  // "VDE2 128BPM Progressive Kick" is a hit from a 128 BPM kit: a sound
  // this short is no loop, whatever its name says.
  final tooShortToLoop = duration != null && seconds <= 1.5;
  final loop = !tooShortToLoop &&
      (_saysLoop(nameWords) ||
          (folderWords.isNotEmpty && _saysLoop(folderWords.first)));

  if (category == null &&
      !tooShortToLoop &&
      nameWords.any(_unambiguousDrumLoopWords.contains)) {
    return SampleCategory.drumLoop;
  }
  if (category == null && allWords.any(_drumWords.contains)) {
    category = loop || seconds > 4
        ? SampleCategory.drumLoop
        : SampleCategory.percussion;
  }
  if (category != null && _drumCategories.contains(category)) {
    if (loop ||
        (!tooShortToLoop && nameWords.any(_drumLoopWords.contains)) ||
        seconds > 4) {
      return SampleCategory.drumLoop;
    }
  }
  if (category != null) return category;
  if (loop) return SampleCategory.loop;
  if (duration != null && seconds <= 2) return SampleCategory.oneShot;
  return SampleCategory.other;
}

/// What [originalName] is called in the pack under [category]: unchanged
/// when it already says what it is, otherwise "Kick - RIM15.wav"-style.
/// Characters a file name can't hold become `_`.
String packFileName(String originalName, SampleCategory category) {
  final safe = originalName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();
  if (!category.isSpecific) return safe;
  final hints = {
    for (final (c, words) in _categoryWords)
      if (c == category) ...words,
    ..._words(category.folder),
  };
  final words = _words(p.basenameWithoutExtension(safe));
  if (words.any(hints.contains)) return safe;
  return '${category.folder} - $safe';
}
