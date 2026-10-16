import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/music_project.dart';
import '../models/project_event.dart';
import '../models/release.dart';
import '../repository/project_repository.dart';
import '../repository/sync_tombstones.dart';
import '../utils/project_folder_utils.dart';
import 'project_move_service.dart';

/// Why a project can't move to another profile as it is.
enum ProfileMoveBlock {
  /// Archived: its row is the one pointer to its zip; restore it first.
  archived,

  /// The target profile already holds this song with details of its own
  /// (notes, to-dos, work time…), at the same path or under the same id.
  targetHasOwnCopy,

  /// Moving the files: the source isn't on this machine.
  sourceMissing,

  /// Moving the files: something of that name is already at the destination.
  destinationOccupied,

  /// Moving the files: the destination is inside what is being moved.
  destinationInsideSource,

  /// Moving the files: the destination is where it already is.
  sameLocation,

  /// Moving the files of a stack put together by hand from versions in
  /// different folders: moving its folder would leave some behind.
  versionsInSeveralFolders,
}

class ProfileMoveException implements Exception {
  const ProfileMoveException(this.block, [this.path]);
  final ProfileMoveBlock block;
  final String? path;

  @override
  String toString() => 'ProfileMoveException($block, $path)';
}

/// Everything a move to another profile would carry, worked out before
/// anything changes, so the dialog can say it.
class ProfileMovePlan {
  const ProfileMovePlan({
    required this.rows,
    required this.song,
    required this.path,
    required this.pathIsFolder,
    required this.releasesUsing,
    this.outlyingFiles = const [],
  });

  /// What moves: a project, or a version stack with every version in it —
  /// a song moves to another artist whole, never one version of it.
  final List<MusicProject> rows;

  /// The row the user sees (the stack, for a stacked song).
  final MusicProject song;

  /// What lives on disk for it: the stack's folder, the project's own folder
  /// when nothing else lives there, else just its file.
  final String path;
  final bool pathIsFolder;

  /// The source profile's releases with one of [rows] on them. A release
  /// belongs to an artist, so they come off it — the dialog asks first.
  final List<Release> releasesUsing;

  /// Versions of a hand-made stack that live outside [path]. Their files
  /// can't move with the folder; staying, each is excluded on its own.
  final List<String> outlyingFiles;

  Set<String> get ids => {for (final r in rows) r.id};
}

/// What happened, for the message and for undo-by-moving-back.
class ProfileMoveResult {
  const ProfileMoveResult({required this.movedTo, required this.excludedPath});

  /// Where the files went, when they moved.
  final String? movedTo;

  /// The path excluded from the source profile's scanning, when the files
  /// stayed (so its scan doesn't add the song straight back).
  final String? excludedPath;
}

/// Works out what moving [project] out of [source] would take.
ProfileMovePlan planProfileMove(ProjectRepository source, MusicProject project) {
  // A version moves with its whole song.
  final MusicProject song = project.isVirtual
      ? project
      : (project.stackId != null ? source.getById(project.stackId!) : null) ?? project;
  if (song.isArchived) throw const ProfileMoveException(ProfileMoveBlock.archived);

  final rows = song.isVirtual ? [song, ...source.stackMembers(song)] : [song];
  if (rows.any((r) => r.isArchived)) {
    throw const ProfileMoveException(ProfileMoveBlock.archived);
  }

  final String path;
  final bool isFolder;
  if (song.isVirtual) {
    path = p.normalize(song.filePath);
    isFolder = true;
  } else {
    final others = source
        .getAllProjects()
        .where((r) => r.id != song.id)
        .map((r) => r.filePath);
    final folder = p.normalize(containingFolderOf(song.filePath));
    // Never a scan folder itself: alone in it or not, moving or excluding
    // the folder would take the whole scan folder along.
    final isRoot = source.getRoots().any((r) => p.equals(r.path, folder));
    if (!isRoot && folderIsDedicatedTo(song.filePath, [song.filePath, ...others])) {
      path = p.normalize(containingFolderOf(song.filePath));
      isFolder = true;
    } else {
      path = p.normalize(song.filePath);
      isFolder = false;
    }
  }

  final ids = {for (final r in rows) r.id};
  return ProfileMovePlan(
    rows: rows,
    song: song,
    path: path,
    pathIsFolder: isFolder,
    outlyingFiles: [
      for (final r in rows)
        if (!r.isVirtual &&
            !p.equals(path, r.filePath) &&
            !p.isWithin(path, p.normalize(r.filePath)))
          p.normalize(r.filePath),
    ],
    releasesUsing: [
      for (final release in source.getAllReleases())
        if (release.trackIds.any(ids.contains)) release,
    ],
  );
}

/// Moves a song from [source] to [target], keeping everything of it — notes,
/// to-dos, work sessions, MIDI clips, cover art — under the same ids.
///
/// With [destinationFolder] its files move there too (a copy checked before
/// the originals go, across drives); without, they stay, and their path is
/// excluded from [source]'s scanning so the song doesn't come straight back
/// there as a new, empty project. Either way it comes off [source]'s
/// releases, and the source side is tombstoned for that profile while the
/// target's rows are new changes — so other devices make the same move on
/// their next sync.
///
/// Every check runs before anything changes; the files move before any
/// row does, so a failed copy leaves the song where it was.
Future<ProfileMoveResult> moveSongToProfile({
  required ProjectRepository source,
  required ProjectRepository target,
  required ProfileMovePlan plan,
  String? destinationFolder,
}) async {
  // Where everything will live, so collisions can be checked first.
  String? movedTo;
  if (destinationFolder != null) {
    if (plan.outlyingFiles.isNotEmpty) {
      throw const ProfileMoveException(ProfileMoveBlock.versionsInSeveralFolders);
    }
    movedTo = p.join(p.normalize(destinationFolder), p.basename(plan.path));
    _checkDestination(plan, destinationFolder, movedTo);
  }
  final moved = [
    for (final row in plan.rows)
      movedTo == null ? row : repathProject(row, from: plan.path, to: movedTo),
  ];

  // The target may hold this song already: a copy a scan made of an
  // overlapping folder (no details of its own: it gives way), or one with
  // details (refused — merging two artists' notes is not a move).
  final replaced = <String>[];
  for (final row in moved) {
    final sameId = target.getById(row.id);
    if (sameId != null && sameId.hasUserMetadata) {
      throw const ProfileMoveException(ProfileMoveBlock.targetHasOwnCopy);
    }
    if (row.isVirtual) continue;
    for (final other in target.getAllProjects()) {
      if (other.id == row.id || other.isVirtual) continue;
      if (!p.equals(other.filePath, row.filePath)) continue;
      if (other.hasUserMetadata) {
        throw const ProfileMoveException(ProfileMoveBlock.targetHasOwnCopy);
      }
      replaced.add(other.id);
    }
  }

  // Files first: if the copy fails nothing else has changed.
  if (movedTo != null) {
    await Directory(p.normalize(destinationFolder!)).create(recursive: true);
    await moveEntity(plan.path, movedTo);
  }

  final ids = plan.ids;
  final now = DateTime.now();

  if (replaced.isNotEmpty) {
    await target.projectsBox.deleteAll(replaced);
    await target.midiClips.deleteAll(replaced);
    await SyncTombstoneStore.record(
      TombstoneKind.project,
      replaced,
      profileId: target.profileId,
    );
  }

  // Into the target, as new changes there.
  await target.projectsBox.putAll({
    for (final row in moved) row.id: row.copyWith(updatedAt: now),
  });
  for (final id in ids) {
    final clips = await source.midiClips.get(id);
    if (clips != null) await target.midiClips.put(id, clips);
  }
  // Copies: an event is a HiveObject, and one instance can't sit in two
  // boxes.
  final events = {
    for (final e in source.eventsBox.toMap().entries)
      if (ids.contains(e.value.projectId))
        e.key: ProjectEvent(
          id: e.value.id,
          projectId: e.value.projectId,
          eventType: e.value.eventType,
          occurredAt: e.value.occurredAt,
          payload: e.value.payload,
        ),
  };
  await target.eventsBox.putAll(events);
  await source.eventsBox.deleteAll(events.keys);

  // Off the source artist's releases.
  for (final release in plan.releasesUsing) {
    await source.updateRelease(
      release.copyWith(trackIds: trackIdsAfterRemoving(release, ids)),
    );
  }

  // Out of the source — a move, not a deletion, so not into its trash —
  // and recorded for that profile only.
  await source.projectsBox.deleteAll(ids);
  await source.midiClips.deleteAll(ids);
  await SyncTombstoneStore.record(
    TombstoneKind.project,
    ids,
    profileId: source.profileId,
  );

  String? excluded;
  if (movedTo == null) {
    for (final path in [plan.path, ...plan.outlyingFiles]) {
      if (!_scannedBy(source, path)) continue;
      await source.addIgnoredPath(path);
      excluded ??= path;
    }
  }

  await source.cleanUpDanglingStackLinks();
  await source.rescheduleDeadlines();
  await target.rescheduleDeadlines();
  return ProfileMoveResult(movedTo: movedTo, excludedPath: excluded);
}

void _checkDestination(ProfileMovePlan plan, String destinationFolder, String movedTo) {
  final source = plan.path;
  final isDir = Directory(source).existsSync();
  if (!isDir && !File(source).existsSync()) {
    throw ProfileMoveException(ProfileMoveBlock.sourceMissing, source);
  }
  if (p.equals(movedTo, source)) {
    throw ProfileMoveException(ProfileMoveBlock.sameLocation, destinationFolder);
  }
  if (isDir && p.isWithin(source, p.normalize(destinationFolder))) {
    throw ProfileMoveException(ProfileMoveBlock.destinationInsideSource, destinationFolder);
  }
  if (File(movedTo).existsSync() || Directory(movedTo).existsSync()) {
    throw ProfileMoveException(ProfileMoveBlock.destinationOccupied, movedTo);
  }
}

bool _scannedBy(ProjectRepository repo, String path) => repo.getRoots().any((r) {
      final root = p.normalize(r.path);
      return p.equals(root, path) || p.isWithin(root, path);
    });

/// Roughly how much moving [path] copies: file count and bytes, from file
/// metadata only (nothing is read — on a cloud drive reading downloads).
Future<({int files, int bytes})> sizeOfPath(String path) async {
  final file = File(path);
  if (await file.exists()) return (files: 1, bytes: await file.length());
  var files = 0, bytes = 0;
  final dir = Directory(path);
  if (!await dir.exists()) return (files: 0, bytes: 0);
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File) {
      files++;
      try {
        bytes += await e.length();
      } catch (_) {}
    }
  }
  return (files: files, bytes: bytes);
}
