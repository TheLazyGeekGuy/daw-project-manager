import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';

/// What the user chose in [showDeleteProjectDialog].
class DeleteProjectChoice {
  const DeleteProjectChoice({required this.stopScanning});

  /// Also exclude the project's path from scanning, so the next scan
  /// doesn't add it straight back as a new, empty project.
  final bool stopScanning;
}

/// Asks before deleting [projectName] into "Recently deleted".
///
/// [scannedPath] is set when the project's file sits inside one of the
/// profile's scan folders — then a scan would bring it back, and the dialog
/// offers to stop scanning that path ([scannedPathIsFolder]: its own folder,
/// else just the file), ticked by default.
Future<DeleteProjectChoice?> showDeleteProjectDialog(
  BuildContext context, {
  required String projectName,
  String? scannedPath,
  bool scannedPathIsFolder = false,
}) {
  return showDialog<DeleteProjectChoice>(
    context: context,
    builder: (context) => _DeleteProjectDialog(
      projectName: projectName,
      scannedPath: scannedPath,
      scannedPathIsFolder: scannedPathIsFolder,
    ),
  );
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({
    required this.projectName,
    required this.scannedPath,
    required this.scannedPathIsFolder,
  });

  final String projectName;
  final String? scannedPath;
  final bool scannedPathIsFolder;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  bool _stopScanning = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scanned = widget.scannedPath;
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Text(l10n.deleteProjectTitle(widget.projectName)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteProjectBody),
            if (scanned != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.deleteProjectStillScanned,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              CheckboxListTile(
                value: _stopScanning,
                onChanged: (v) => setState(() => _stopScanning = v ?? false),
                title: Text(
                  widget.scannedPathIsFolder
                      ? l10n.deleteProjectStopScanningFolder
                      : l10n.deleteProjectStopScanningFile,
                ),
                subtitle: Text(scanned, maxLines: 2, overflow: TextOverflow.ellipsis),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            DeleteProjectChoice(stopScanning: scanned != null && _stopScanning),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
