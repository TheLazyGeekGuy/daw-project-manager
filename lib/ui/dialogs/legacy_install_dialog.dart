import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';

/// Asks whether to remove the copy the previous Windows installer left
/// behind. True: remove it; false: keep it and stop asking; null: closed
/// without an answer, so the next launch asks again.
Future<bool?> showLegacyInstallDialog(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (_) => const LegacyInstallDialog(),
    );

class LegacyInstallDialog extends StatelessWidget {
  const LegacyInstallDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.legacyInstallTitle),
      content: SizedBox(width: 420, child: Text(l10n.legacyInstallMessage)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.legacyInstallKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.legacyInstallRemove),
        ),
      ],
    );
  }
}
