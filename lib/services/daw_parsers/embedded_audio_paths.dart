import 'dart:convert';
import 'dart:typed_data';

import '../../models/sample_reference.dart';

/// Finds absolute paths to audio files written inside [bytes] as plain text,
/// in single-byte (ASCII/UTF-8) or UTF-16LE form, in the order they appear,
/// without duplicates.
///
/// For data no format reader understands — a third-party sampler's saved
/// state, mostly. A plug-in that keeps the path to the sample it plays as
/// text (TAL-Sampler, Sitala, ReaSamplOmatic5000, Fruity Slicer…) is found
/// this way; one that compresses its state or embeds the audio (Kontakt,
/// Serum) is not, and nothing can be done about that from outside.
///
/// A path counts when it is absolute — a drive letter (`C:\`, `D:/`), a UNC
/// share (`\\server\`) or a POSIX root a user's files live under (`/Users/`,
/// `/home/`, `/Volumes/`…) — and ends in one of [kSampleAudioExtensions]
/// with nothing name-like after it, so `kick.wav.asd` (Ableton's analysis
/// file) is not mistaken for `kick.wav`.
List<String> findEmbeddedAudioPaths(Uint8List bytes) {
  final found = <String>{};
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0x2E) continue; // '.'
    final single = _singleByteAt(bytes, i);
    if (single != null) found.add(single);
    final wide = _utf16At(bytes, i);
    if (wide != null) found.add(wide);
  }
  return found.toList();
}

/// Extensions without the dot, longest first so `.aiff` wins over `.aif`.
final List<String> _extensions = [
  for (final e in kSampleAudioExtensions) e.substring(1),
]..sort((a, b) => b.length.compareTo(a.length));

const _maxPathLength = 1024;

bool _isNameChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x2E ||
    c == 0x5F ||
    c == 0x2D;

/// Characters a path can't contain: controls and `"*<>?|`.
bool _isPathChar(int c) =>
    c >= 0x20 &&
    c != 0x7F &&
    c != 0x22 &&
    c != 0x2A &&
    c != 0x3C &&
    c != 0x3E &&
    c != 0x3F &&
    c != 0x7C;

int _lower(int c) => (c >= 0x41 && c <= 0x5A) ? c + 32 : c;

/// The extension spelled out at [at] (stride [stride], high bytes zero for
/// UTF-16), or -1. Returns where the extension ends.
int _matchExtension(Uint8List bytes, int at, int stride) {
  for (final ext in _extensions) {
    final end = at + ext.length * stride;
    if (end > bytes.length) continue;
    var ok = true;
    for (var k = 0; k < ext.length; k++) {
      final o = at + k * stride;
      if (_lower(bytes[o]) != ext.codeUnitAt(k) ||
          (stride == 2 && bytes[o + 1] != 0)) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    // Nothing name-like may follow: "kick.wav.asd", "x.wavex" aren't audio.
    if (end + stride <= bytes.length) {
      final next = bytes[end];
      final nextHigh = stride == 2 ? bytes[end + 1] : 0;
      if (nextHigh == 0 && _isNameChar(next)) continue;
    }
    return end;
  }
  return -1;
}

String? _singleByteAt(Uint8List bytes, int dot) {
  final end = _matchExtension(bytes, dot + 1, 1);
  if (end < 0) return null;
  var start = dot;
  while (start > 0 &&
      dot - start < _maxPathLength &&
      _isPathChar(bytes[start - 1])) {
    start--;
  }
  final text = utf8.decode(bytes.sublist(start, end), allowMalformed: true);
  return _absoluteTail(text);
}

String? _utf16At(Uint8List bytes, int dot) {
  if (dot + 1 >= bytes.length || bytes[dot + 1] != 0) return null;
  final end = _matchExtension(bytes, dot + 2, 2);
  if (end < 0) return null;
  var start = dot;
  while (start >= 2 && dot - start < _maxPathLength * 2) {
    final unit = bytes[start - 2] | (bytes[start - 1] << 8);
    if (unit < 0x20 ||
        (unit < 0x80 && !_isPathChar(unit)) ||
        (unit >= 0xD800 && unit <= 0xDFFF)) {
      break;
    }
    start -= 2;
  }
  final units = <int>[
    for (var o = start; o + 1 < end; o += 2) bytes[o] | (bytes[o + 1] << 8),
  ];
  return _absoluteTail(String.fromCharCodes(units));
}

final _drive = RegExp(r'[A-Za-z]:[\\/]');
final _posixRoots = RegExp(
  r'/(?:Users|Volumes|home|mnt|media|Library|opt|run|srv|data|tmp)/',
);

/// The absolute path at the end of [text] — whatever precedes the drive
/// letter, UNC prefix or POSIX root is a length byte or a neighbour's tail.
String? _absoluteTail(String text) {
  var cut = -1;
  final drive = _drive.firstMatch(text);
  if (drive != null) cut = drive.start;
  final unc = text.indexOf(r'\\');
  if (unc >= 0 && (cut < 0 || unc < cut)) cut = unc;
  if (cut < 0) {
    final posix = _posixRoots.firstMatch(text);
    if (posix != null) cut = posix.start;
  }
  if (cut < 0) return null;
  final path = text.substring(cut);
  // A bare "C:\.wav" or a root with no file name isn't a reference.
  final name = sampleFileNameOf(path);
  if (name.length < 5 || name.startsWith('.')) return null;
  return path;
}
