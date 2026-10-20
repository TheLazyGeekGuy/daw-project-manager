import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../generated/l10n/app_localizations.dart';
import '../models/music_project.dart';
import '../models/scan_root.dart';
import '../providers/providers.dart';
import '../repository/project_repository.dart';
import '../services/profile_move_service.dart';
import '../utils/drive_sync_format.dart' show formatSyncBytes;
import 'app_snack_bar.dart';
import 'dialogs/move_to_profile_dialog.dart';

/// The sentence for a move that couldn't happen.
String profileMoveBlockSentence(
  AppLocalizations l10n,
  ProfileMoveException e, {
  required String targetName,
}) =>
    switch (e.block) {
      ProfileMoveBlock.archived => l10n.moveToProfileBlockedArchived,
      ProfileMoveBlock.targetHasOwnCopy => l10n.moveToProfileBlockedTargetCopy(targetName),
      ProfileMoveBlock.sourceMissing => l10n.moveToProfileBlockedSourceMissing,
      ProfileMoveBlock.destinationOccupied =>
        l10n.moveToProfileBlockedOccupied(p.dirname(e.path ?? '')),
      ProfileMoveBlock.destinationInsideSource => l10n.moveToProfileBlockedInsideSource,
      ProfileMoveBlock.sameLocation => l10n.moveToProfileBlockedSameLocation,
      ProfileMoveBlock.versionsInSeveralFolders => l10n.moveToProfileCantMoveFiles,
    };

/// "Move to profile…" on a project: a song (its whole version stack) goes
/// to another artist's profile, its files staying or moving with it.
Future<void> moveToProfileFromMenu(
  BuildContext context,
  WidgetRef ref,
  MusicProject project,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text, {Color? color}) =>
      messenger.showAppSnackBar(SnackBar(content: Text(text), backgroundColor: color));

  final profileRepo = await ref.read(profileRepositoryProvider.future);
  final source = await ref.read(repositoryProvider.future);
  final currentId = profileRepo.getCurrentProfileId();
  final sourceName = profileRepo.getProfileById(source.profileId)?.name ?? '';
  final targets = <MoveTargetProfile>[];
  for (final profile in profileRepo.getAllProfiles()) {
    if (profile.id == currentId) continue;
    final roots = await Hive.openBox<ScanRoot>('${profile.id}_roots');
    targets.add(MoveTargetProfile(
      id: profile.id,
      name: profile.name,
      scanFolders: [for (final r in roots.values) r.path],
    ));
  }
  if (targets.isEmpty) {
    say(l10n.moveToProfileNoOtherProfiles);
    return;
  }

  final ProfileMovePlan plan;
  try {
    plan = planProfileMove(source, project);
  } on ProfileMoveException catch (e) {
    say(profileMoveBlockSentence(l10n, e, targetName: ''), color: Colors.red);
    return;
  }
  final active = ref.read(activeProjectProvider);
  if (active != null && plan.ids.contains(active.id)) {
    say(l10n.moveToProfileInSession);
    return;
  }
  final scanned = source.getRoots().any((r) {
    final root = p.normalize(r.path);
    return p.equals(root, plan.path) || p.isWithin(root, plan.path);
  });
  if (!context.mounted) return;

  final choice = await showDialog<MoveToProfileChoice>(
    context: context,
    builder: (_) => MoveToProfileDialog(
      songName: plan.song.displayName,
      sourceProfileName: sourceName,
      targets: targets,
      path: plan.path,
      pathIsScanned: scanned,
      canMoveFiles: plan.outlyingFiles.isEmpty,
      releaseTitles: [for (final r in plan.releasesUsing) r.title],
      versionCount: plan.song.isVirtual ? plan.rows.length - 1 : 0,
      sizeLabel: () async {
        final size = await sizeOfPath(plan.path);
        return l10n.moveToProfileSize(size.files, formatSyncBytes(size.bytes));
      },
      pickFolder: () => FilePicker.getDirectoryPath(dialogTitle: l10n.moveToProfileOtherFolder),
    ),
  );
  if (choice == null || !context.mounted) return;
  final targetName = targets.firstWhere((t) => t.id == choice.profileId).name;

  final navigator = Navigator.of(context, rootNavigator: true);
  final movingFiles = choice.destinationFolder != null;
  if (movingFiles) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.moveToProfileMoving)),
            ],
          ),
        ),
      ),
    );
  }
  try {
    final target = await ProjectRepository.initWithProfile(profileRepo, choice.profileId);
    await moveSongToProfile(
      source: source,
      target: target,
      plan: plan,
      destinationFolder: choice.destinationFolder,
    );
    if (movingFiles) navigator.pop();
    ref.invalidate(allProjectsStreamProvider);
    ref.invalidate(releasesProvider);
    say(l10n.moveToProfileDone(plan.song.displayName, targetName), color: Colors.green);
  } on ProfileMoveException catch (e) {
    if (movingFiles) navigator.pop();
    say(profileMoveBlockSentence(l10n, e, targetName: targetName), color: Colors.red);
  } on FileSystemException catch (e) {
    if (movingFiles) navigator.pop();
    say('${l10n.moveToProfileCopyFailed}\n${e.path ?? e.message}', color: Colors.red);
  }
}
