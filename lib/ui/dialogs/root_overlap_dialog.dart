import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../providers/providers.dart';
import '../../utils/root_overlap.dart';

/// Before adding [path] as a scan folder: when another profile already
/// scans it (or a folder inside or around it), says so and asks. Returns
/// whether to go ahead — true straight away when nothing overlaps.
///
/// [forProfileId] is the profile the folder is being added to — by default
/// the active one; Settings can add to another.
Future<bool> confirmScanFolderOverlap(
  BuildContext context,
  WidgetRef ref,
  String path, {
  String? forProfileId,
}) async {
  List<RootOverlap> overlaps;
  try {
    final profileRepo = await ref.read(profileRepositoryProvider.future);
    overlaps = findRootOverlaps(
      path,
      await otherProfilesRoots(
        profileRepo,
        forProfileId ?? profileRepo.getCurrentProfileId(),
      ),
    );
  } catch (_) {
    return true; // Can't tell: don't stand in the way.
  }
  if (overlaps.isEmpty || !context.mounted) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => RootOverlapDialog(overlaps: overlaps),
  );
  return go == true;
}

class RootOverlapDialog extends StatelessWidget {
  const RootOverlapDialog({super.key, required this.overlaps});

  final List<RootOverlap> overlaps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String line(RootOverlap o) => switch (o.kind) {
          RootOverlapKind.same => l10n.scanFolderOverlapSame(o.profileName),
          RootOverlapKind.inside =>
            l10n.scanFolderOverlapInside(o.profileName, o.rootPath),
          RootOverlapKind.contains =>
            l10n.scanFolderOverlapContains(o.profileName, o.rootPath),
        };
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Text(l10n.scanFolderOverlapTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in overlaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('•  ${line(o)}'),
              ),
            const SizedBox(height: 8),
            Text(l10n.scanFolderOverlapBody),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.scanFolderOverlapAddAnyway),
        ),
      ],
    );
  }
}
