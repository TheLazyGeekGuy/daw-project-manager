import 'package:path/path.dart' as p;

/// [path] carried from under [from] to under [to]: [to] itself when [path] is
/// [from], [to] with the same tail when [path] is inside it, and null when it
/// is neither — a sibling that only starts with the same text (`Music2` next
/// to `Music`) included.
///
/// Compared the way the platform compares paths (case-insensitively on
/// Windows), so a drive letter typed in another case still matches. A Drive
/// fallback reference (`drive://…`) is not a filesystem path and never
/// matches.
///
/// The one rule behind moving a project (`repathProject`) and relocating a
/// whole scan folder (`ProjectRepository.relocateRoot`), so the two cannot
/// drift apart.
String? rebasePath(String path, {required String from, required String to}) {
  if (path.isEmpty || path.startsWith('drive://')) return null;
  final source = p.normalize(path);
  final fromNorm = p.normalize(from);
  final toNorm = p.normalize(to);
  if (p.equals(source, fromNorm)) return toNorm;
  if (!p.isWithin(fromNorm, source)) return null;
  return p.join(toNorm, p.relative(source, from: fromNorm));
}
