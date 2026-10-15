import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../generated/l10n/app_localizations.dart';
import '../models/music_project.dart';
import '../providers/providers.dart';
import '../repository/project_repository.dart';
import '../repository/project_trash.dart';
import '../utils/project_folder_utils.dart';
import 'app_snack_bar.dart';
import 'dialogs/delete_project_dialog.dart';
import 'dialogs/drive_sync_dialogs.dart' show showDriveConfirmDialog;
import 'widgets/recently_deleted_card.dart';

/// What a scan would find again of [project]: its own folder when nothing
/// else lives there, else just its file — or null when it sits outside every
/// one of the profile's scan folders, and a deletion stays deleted.
({String path, bool isFolder})? pathAScanWouldFind(
  MusicProject project,
  Iterable<String> scanRoots,
  Iterable<String> allProjectPaths,
) {
  final file = p.normalize(project.filePath);
  final scanned = scanRoots.any((root) {
    final r = p.normalize(root);
    return p.equals(r, file) || p.isWithin(r, file);
  });
  if (!scanned) return null;
  if (folderIsDedicatedTo(file, allProjectPaths)) {
    return (path: p.normalize(containingFolderOf(file)), isFolder: true);
  }
  return (path: file, isFolder: false);
}

/// "Delete…" on a project: asks, deletes it into Recently deleted —
/// optionally excluding its path from scanning so it doesn't come straight
/// back — and offers Undo.
Future<void> deleteProjectFromLibrary(
  BuildContext context,
  WidgetRef ref,
  MusicProject project,
) async {
  final repo = await ref.read(repositoryProvider.future);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final scanned = pathAScanWouldFind(
    project,
    repo.getRoots().map((r) => r.path),
    repo.getAllProjects().map((p) => p.filePath),
  );
  final choice = await showDeleteProjectDialog(
    context,
    projectName: project.displayName,
    scannedPath: scanned?.path,
    scannedPathIsFolder: scanned?.isFolder ?? false,
  );
  if (choice == null || !context.mounted) return;

  String? excludedId;
  if (choice.stopScanning && scanned != null) {
    await repo.addIgnoredPath(scanned.path);
    excludedId = repo
        .getIgnoredPaths()
        .where((i) => p.equals(i.path, scanned.path))
        .map((i) => i.id)
        .lastOrNull;
  }
  // Excluding a path spares projects that are on a release; this one was
  // asked for by name, so it goes either way.
  if (repo.getById(project.id) != null) {
    await repo.deleteProjects([project.id]);
  }
  ref.invalidate(allProjectsStreamProvider);
  ref.invalidate(recentlyDeletedProvider);
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showAppSnackBar(SnackBar(
    content: Text(l10n.projectMovedToRecentlyDeleted(project.displayName)),
    action: SnackBarAction(
      label: l10n.undo,
      onPressed: () async {
        if (excludedId != null) await repo.removeIgnoredPath(excludedId);
        await repo.restoreFromTrash(project.id);
        ref.invalidate(allProjectsStreamProvider);
        ref.invalidate(recentlyDeletedProvider);
      },
    ),
  ));
}

/// Settings > Project folders > Recently deleted, for the current profile.
class RecentlyDeletedSection extends ConsumerStatefulWidget {
  const RecentlyDeletedSection({super.key});

  @override
  ConsumerState<RecentlyDeletedSection> createState() => _RecentlyDeletedSectionState();
}

class _RecentlyDeletedSectionState extends ConsumerState<RecentlyDeletedSection> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(ProjectRepository repo) action) async {
    setState(() => _busy = true);
    try {
      await action(await ref.read(repositoryProvider.future));
    } finally {
      ref.invalidate(allProjectsStreamProvider);
      ref.invalidate(recentlyDeletedProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(TrashedProject item) async {
    final l10n = AppLocalizations.of(context)!;
    var replaced = false;
    await _run((repo) async => replaced = await repo.restoreFromTrash(item.project.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showAppSnackBar(SnackBar(
      content: Text(replaced
          ? l10n.projectRestoredReplacingRescan(item.project.displayName)
          : l10n.projectRestored(item.project.displayName)),
    ));
  }

  Future<void> _deleteForever(TrashedProject item) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDriveConfirmDialog(
      context,
      title: l10n.deleteForeverTitle(item.project.displayName),
      body: l10n.deleteForeverBody,
      confirmLabel: l10n.recentlyDeletedDeleteForever,
      destructive: true,
    );
    if (ok) await _run((repo) => repo.deleteFromTrash([item.project.id]));
  }

  Future<void> _empty(int count) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDriveConfirmDialog(
      context,
      title: l10n.emptyRecentlyDeletedTitle,
      body: l10n.emptyRecentlyDeletedBody(count),
      confirmLabel: l10n.recentlyDeletedEmptyAll,
      destructive: true,
    );
    if (ok) await _run((repo) => repo.trash.empty());
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(recentlyDeletedProvider).value ?? const <TrashedProject>[];
    return RecentlyDeletedCard(
      items: items,
      now: DateTime.now(),
      busy: _busy,
      onRestore: _restore,
      onDeleteForever: _deleteForever,
      onEmpty: () => _empty(items.length),
    );
  }
}
