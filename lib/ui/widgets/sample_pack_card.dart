import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';

/// The "sample pack from your projects" card on the settings page.
///
/// Split out of `settings_page.dart` so it can be pumped on its own, like
/// `MelodicExportCard`.
class SamplePackCard extends StatelessWidget {
  const SamplePackCard({
    super.key,
    required this.busy,
    required this.onExport,
  });

  /// Disables the button while another settings task is running.
  final bool busy;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.samplePackTitle,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(l10n.samplePackSubtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: busy ? null : onExport,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(l10n.templateExportButton),
            ),
          ],
        ),
      ),
    );
  }
}
