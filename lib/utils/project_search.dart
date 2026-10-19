import '../models/music_project.dart';
import '../models/project_part.dart';
import 'search_utils.dart';

/// Whether the projects search [query] finds [p].
///
/// Short fields ([projectSearchFields]) match fuzzily, so "chilvib" finds
/// "chillout vibes". Long free text ([projectProseFields]) only matches where
/// a query word starts a word ([proseMatchesSearch]): over a paragraph the
/// fuzzy fallback has so many words to build a query from that it found
/// "note" in "now … the" and "cue" in "Cubase".
bool projectMatchesSearch(
  MusicProject p,
  String query, {
  required bool includeTags,
  Iterable<String> customFieldIds = const [],
}) =>
    fuzzyMatchAny(
      projectSearchFields(
        p,
        includeTags: includeTags,
        customFieldIds: customFieldIds,
      ),
      query,
    ) ||
    projectProseFields(p).any((text) => proseMatchesSearch(text, query));

/// Whether [query] finds the free text [text] — every query word starting a
/// word of it (`wordStartMatchAll`). The dashboard's "matched in notes"
/// marker asks this too, so it never points at a match the list didn't make.
bool proseMatchesSearch(String? text, String query) =>
    text != null && text.isNotEmpty && wordStartMatchAll(text, query);

/// The short texts the projects search matches a project against, for
/// `fuzzyMatchAny`.
///
/// Multi-valued fields (markers, tags, plug-ins) go in one entry each rather
/// than joined: `fuzzyMatchAny` requires every query word to hit the *same*
/// entry, so a joined string would match words picked out of two unrelated
/// markers.
///
/// [includeTags] is false while tags are switched off: a hidden tag must not
/// make a project match, or the user sees a result with nothing on screen
/// explaining why. [customFieldIds] are the custom fields that still exist —
/// a deleted field's values stay on the project but nothing shows them, so
/// they mustn't make it match either.
Iterable<String?> projectSearchFields(
  MusicProject p, {
  required bool includeTags,
  Iterable<String> customFieldIds = const [],
}) sync* {
  yield p.displayName;
  yield* p.markers.map((m) => m.name);
  if (includeTags) yield* p.tags;
  // Custom field values, one entry each like tags.
  for (final id in customFieldIds) {
    yield p.customFields[id];
  }
  // So "serum" finds every song that loads it.
  final plugins = p.stats?.plugins;
  if (plugins != null) yield* plugins;
}

/// The long free texts the projects search matches with
/// [proseMatchesSearch] rather than fuzzily.
Iterable<String?> projectProseFields(MusicProject p) sync* {
  yield p.notes;
  // projectNotes are the read-only notes extracted from the DAW file itself —
  // real user content, so searchable too.
  yield p.projectNotes;
  // Instrumentation is searchable too, so "who played bass on which song" is
  // answerable from the projects list. Every part's name, performer and notes
  // in one string — prose, not a name. Guarded because this runs per project
  // per keystroke and searchableText builds a string.
  if (p.parts.isNotEmpty) yield ProjectPart.searchableText(p.parts);
}
