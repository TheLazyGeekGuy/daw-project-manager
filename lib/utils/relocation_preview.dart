import 'dart:io';

import '../models/music_project.dart';
import 'path_rebase.dart';

/// What relocating a scan folder would find at its new place, worked out
/// before anything is changed: how many of the folder's projects are already
/// there.
class RelocationPreview {
  const RelocationPreview({required this.projects, required this.found});

  /// Projects whose file or bundle lives in the folder. Archived projects
  /// (zipped away) and version stacks (no file of their own) are left out:
  /// neither is expected at the new place.
  final int projects;

  /// How many of [projects] are at the new place already.
  final int found;

  bool get allFound => found == projects;
  bool get noneFound => projects > 0 && found == 0;
}

/// Looks for each of [projects] in [from] at its place under [to].
///
/// [exists] defaults to asking the filesystem for the entry's type without
/// following links, which reads no file: a cloud drive's not-yet-downloaded
/// placeholder (Proton Drive, OneDrive) is found without being downloaded.
RelocationPreview previewRelocation(
  Iterable<MusicProject> projects, {
  required String from,
  required String to,
  bool Function(String path)? exists,
}) {
  final isThere = exists ??
      (path) => FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound;
  var total = 0;
  var found = 0;
  for (final project in projects) {
    if (project.isVirtual || project.isArchived) continue;
    final target = rebasePath(project.filePath, from: from, to: to);
    if (target == null) continue;
    total++;
    if (isThere(target)) found++;
  }
  return RelocationPreview(projects: total, found: found);
}
