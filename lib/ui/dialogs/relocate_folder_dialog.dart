import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../utils/relocation_preview.dart';

/// Asks before pointing a scan folder at [to]: what happens (nothing moves on
/// disk, every project keeps its details), and how many of its projects are
/// at the new place already — which tells a download still in progress from
/// a folder picked one level too high or too low. Pops `true` to go ahead.
///
/// Plain values in, no providers, so it can be tested on its own.
class RelocateFolderDialog extends StatelessWidget {
  const RelocateFolderDialog({
    super.key,
    required this.from,
    required this.to,
    required this.preview,
  });

  final String from;
  final String to;
  final RelocationPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget pathRow(String label, String path) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
              Expanded(child: SelectableText(path, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    final warning = preview.noneFound
        ? l10n.relocateFolderNoneFound
        : preview.allFound
            ? null
            : l10n.relocateFolderSomeMissing;

    return AlertDialog(
      title: Text(l10n.relocateFolderDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.relocateFolderConfirmBody),
              const SizedBox(height: 8),
              pathRow(l10n.relocateFolderFrom, from),
              pathRow(l10n.relocateFolderTo, to),
              if (preview.projects > 0) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      preview.allFound ? Icons.check_circle_outline : Icons.info_outline,
                      size: 18,
                      color: preview.allFound ? Colors.green : muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.relocateFolderFound(preview.found, preview.projects),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (warning != null) ...[
                  const SizedBox(height: 6),
                  Text(warning, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.relocateFolderAction),
        ),
      ],
    );
  }
}
