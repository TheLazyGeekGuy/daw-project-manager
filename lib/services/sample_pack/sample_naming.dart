import 'sample_classifier.dart';

/// How copied samples are renamed, when they are: `Kick 001`, then whichever
/// of the original name, tempo and key are on, joined by " - ", with an
/// optional [prefix] in front ("AC Kick 001 - …").
///
/// The category and number are always there: they keep names unique and in
/// order within a folder. Numbers carry on from the highest already in the
/// folder, so exporting more never renumbers what is there.
class SampleNaming {
  const SampleNaming({
    this.includeName = true,
    this.includeBpm = true,
    this.includeKey = true,
    this.prefix = '',
  });

  final bool includeName;
  final bool includeBpm;
  final bool includeKey;
  final String prefix;

  static const numberWidth = 3;

  Map<String, dynamic> toJson() => {
    'name': includeName,
    'bpm': includeBpm,
    'key': includeKey,
    'prefix': prefix,
  };

  static SampleNaming fromJson(Object? json) {
    if (json is! Map) return const SampleNaming();
    return SampleNaming(
      includeName: json['name'] != false,
      includeBpm: json['bpm'] != false,
      includeKey: json['key'] != false,
      prefix: json['prefix'] is String ? json['prefix'] as String : '',
    );
  }

  /// What the file names in a category folder start with, before the number.
  String lead(SampleCategory category) {
    final p = _safe(prefix);
    return p.isEmpty ? category.folder : '$p ${category.folder}';
  }

  /// The file name for the [number]th sample of [category], from its
  /// original file name [original] and what was found out about it.
  String fileName({
    required SampleCategory category,
    required int number,
    required String original,
    double? bpm,
    String? key,
  }) {
    final dot = original.lastIndexOf('.');
    final ext = dot <= 0 ? '' : original.substring(dot);
    final stem = dot <= 0 ? original : original.substring(0, dot);
    final parts = [
      '${lead(category)} ${number.toString().padLeft(numberWidth, '0')}',
      if (includeName) ?_nonEmpty(cleanSampleName(stem)),
      if (includeBpm && bpm != null) '${formatBpm(bpm)} BPM',
      if (includeKey && key != null) key,
    ];
    return '${_safe(parts.join(' - '))}$ext';
  }

  /// The number after the highest one already used by [names] (file names
  /// in one folder) for [category]; 1 when there is none.
  int nextNumber(SampleCategory category, Iterable<String> names) {
    final lead = RegExp(
      '^${RegExp.escape(this.lead(category))} (\\d+)(?=\$|[ .])',
      caseSensitive: false,
    );
    var highest = 0;
    for (final name in names) {
      final m = lead.firstMatch(name);
      if (m == null) continue;
      final n = int.parse(m[1]!);
      if (n > highest) highest = n;
    }
    return highest + 1;
  }
}

String? _nonEmpty(String s) => s.isEmpty ? null : s;

String _safe(String s) => s
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// "140", "128.5".
String formatBpm(double bpm) {
  final rounded = (bpm * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
}

/// "140 BPM", "128bpm", "BPM 174", "140BPM_" — a plausible tempo.
final _bpm = RegExp(
  r'(?<![0-9.])(\d{2,3}(?:\.\d+)?)\s*[-_ ]?\s*bpm(?![a-z])|(?<![a-z])bpm\s*[-_ ]?\s*(\d{2,3}(?:\.\d+)?)(?![0-9])',
  caseSensitive: false,
);

/// A note with what kind of key it is: "F#m", "A minor", "Ebmaj", "G
/// Phrygian". The note letter must be upper case and nothing word-like may
/// touch it, so "am" in "Hamond" or the "a" of a word never reads as a key;
/// a lone "m" (minor) must be lower case, as "AM" is a word.
final _keyWithQuality = RegExp(
  r'(?<![A-Za-z0-9])([A-G])(#|♯|b|♭)?\s?([Mm]inor|[Mm]in|[Mm]ajor|[Mm]aj|[Dd]orian|[Pp]hrygian|[Ll]ydian|[Mm]ixolydian|[Aa]eolian|[Ll]ocrian|m)(?![A-Za-z])',
);

/// A sharp or flat note on its own: "F#", "Eb", "(C#)".
final _bareAccidental = RegExp(
  r'(?<![A-Za-z0-9])([A-G])(#|♯|b|♭)(?![A-Za-z0-9#♯])',
);

/// What a sample's name says about it, and where it said it (so the name
/// can be given without it, once it has a field of its own).
class SampleTraits {
  const SampleTraits({this.bpm, this.key, this.spans = const []});
  final double? bpm;
  final String? key;
  final List<(int, int)> spans;
}

/// The tempo and key [text] (a file or folder name) mentions, if any. A key
/// reads as "F#m", "Am", "Eb", "C", "G Phrygian"; a bare letter like "A" is
/// never taken for one — it is a word as often as a key.
SampleTraits sampleTraitsOf(String text) {
  double? bpm;
  String? key;
  final spans = <(int, int)>[];

  final b = _bpm.firstMatch(text);
  if (b != null) {
    final v = double.tryParse(b[1] ?? b[2] ?? '');
    if (v != null && v >= 50 && v <= 250) {
      bpm = v;
      spans.add((b.start, b.end));
    }
  }

  final k = _keyWithQuality.firstMatch(text);
  if (k != null) {
    final note = '${k[1]}${_accidental(k[2])}';
    final quality = k[3]!;
    final lower = quality.toLowerCase();
    if (quality == 'm' || lower == 'min' || lower == 'minor') {
      key = '${note}m';
    } else if (lower == 'maj' || lower == 'major') {
      key = note;
    } else if (quality.length > 1) {
      key = '$note ${lower[0].toUpperCase()}${lower.substring(1)}';
    }
    if (key != null) spans.add((k.start, k.end));
  }
  if (key == null) {
    final a = _bareAccidental.firstMatch(text);
    if (a != null) {
      key = '${a[1]}${_accidental(a[2])}';
      spans.add((a.start, a.end));
    }
  }
  return SampleTraits(bpm: bpm, key: key, spans: spans);
}

String _accidental(String? a) => switch (a) {
      '#' || '♯' => '#',
      'b' || '♭' => 'b',
      _ => '',
    };

/// A file name as words for the name part: "_" and runs of spaces become
/// one space, and the tempo and key are taken out (they have fields of
/// their own) along with the brackets and separators they leave behind.
String cleanSampleName(String stem) {
  var text = stem;
  final traits = sampleTraitsOf(text);
  for (final (start, end) in [...traits.spans]
    ..sort((a, b) => b.$1.compareTo(a.$1))) {
    text = '${text.substring(0, start)} ${text.substring(end)}';
  }
  text = text
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[-–,.\s]+|[-–,.\s]+$'), '')
      .trim();
  return text.length > 60 ? text.substring(0, 60).trim() : text;
}

/// The tempo a loop of [length] was made at, if [projectBpm] fits it: the
/// length is a whole number of 4/4 bars (1, 2, 4, 8, 16 or 32) at that
/// tempo, to within 1%. A loop stretched to the project's tempo fits; a
/// one-shot or a loop at another tempo doesn't, and gets none.
double? bpmFromLoopLength(Duration length, double projectBpm) {
  if (projectBpm <= 0) return null;
  final seconds = length.inMicroseconds / 1e6;
  if (seconds < 1.5) return null;
  final bars = seconds * projectBpm / 240;
  for (final whole in const [1, 2, 4, 8, 16, 32]) {
    if ((bars - whole).abs() / whole <= 0.01) return projectBpm;
  }
  return null;
}
