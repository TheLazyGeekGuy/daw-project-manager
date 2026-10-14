final _masterWord =
    RegExp(r'\b(master|mastering|mastered)\)?(\s*[-_]\d+)?$', caseSensitive: false);

/// A capital "M" on its own at the end: "Song (M)", "Song M", "Song M-1",
/// "(AC RMX 2025 M)". Case-sensitive: a lower-case "m" ends many words.
final _masterLetter = RegExp(r'(^|[\s(_-])M\)?(\s*[-_]\d+)?$');

final _masterFolder = RegExp(
  r'^(master|mastering)( ?projects?| ?sessions?)?\s*(new|copy|\d+|\(\d+\))?$'
  r'|[ _-](master|mastering)$',
  caseSensitive: false,
);

/// Whether the project at [filePath] is a song's master project — the one
/// its stems are mixed down and mastered in, which holds those stems and
/// mixdowns rather than samples.
///
/// Its name ends in "master"/"mastering" or a lone capital "M", optionally
/// in brackets and before a version number ("Song (Master).cpr",
/// "Song (M)-1.cpr", "Song (AC RMX 2025 M).cpr"), or it sits in a folder
/// named for it ("Master Project", "Master project New", "Song - Master").
/// Only the end of a name counts, so "Master of Puppets (Remix)" isn't one.
bool isMasterProject(String filePath) {
  final segments = filePath.split(RegExp(r'[\\/]'));
  final file = segments.last;
  final dot = file.lastIndexOf('.');
  final stem = (dot <= 0 ? file : file.substring(0, dot)).trim();
  if (_masterWord.hasMatch(stem) || _masterLetter.hasMatch(stem)) return true;
  final folder = segments.length > 1 ? segments[segments.length - 2].trim() : '';
  return _masterFolder.hasMatch(folder);
}
