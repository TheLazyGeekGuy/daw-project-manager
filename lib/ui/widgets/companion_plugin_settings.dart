import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/companion_bridge/companion_protocol.dart';

/// Settings > DAW plugin: what the DPM Companion plugin is, whether this
/// computer has seen it, where to get it (or its update), and the work
/// session switches it drives.
///
/// Plain values and callbacks — no Riverpod, no Hive — so it can be
/// widget-tested; the settings page wires it up.
class CompanionPluginSettingsView extends StatelessWidget {
  const CompanionPluginSettingsView({
    super.key,
    required this.sighting,
    required this.latestRelease,
    required this.platform,
    required this.endSessionWhenDawCloses,
    required this.startSessionWhenDawOpens,
    required this.onDownload,
    required this.onEndSessionChanged,
    required this.onStartSessionChanged,
  });

  final CompanionSighting? sighting;
  final CompanionRelease? latestRelease;
  final CompanionPlatform platform;
  final bool endSessionWhenDawCloses;
  final bool startSessionWhenDawOpens;
  final ValueChanged<String> onDownload;
  final ValueChanged<bool> onEndSessionChanged;
  final ValueChanged<bool> onStartSessionChanged;

  /// A newer release than the one this computer last saw running.
  bool get updateAvailable {
    final seen = sighting, latest = latestRelease;
    return seen != null && latest != null && isNewerCompanionVersion(latest.version, seen.version);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final seen = sighting;

    final status = seen == null
        ? l10n.companionPluginNotSeen
        : l10n.companionPluginLastSeen(
            seen.hostName.trim().isEmpty ? l10n.companionUnknownDaw : seen.hostName.trim(),
            seen.version,
            DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm().format(seen.at.toLocal()),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.extension_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l10n.companionPluginTitle, style: theme.textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l10n.companionPluginDescription, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      seen == null ? Icons.radio_button_unchecked : Icons.check_circle_outline,
                      size: 18,
                      color: seen == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(status, style: theme.textTheme.bodyMedium)),
                  ],
                ),
                if (updateAvailable) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.system_update_alt_outlined, size: 18, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.companionPluginUpdateAvailable(latestRelease!.version))),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: Text(updateAvailable ? l10n.companionPluginDownloadUpdate : l10n.companionPluginDownload),
                  onPressed: () => onDownload(companionDownloadUrl(latestRelease, platform)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bookmark_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l10n.workSessionsTabLabel, style: theme.textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l10n.companionSessionsDescription, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.companionEndSessionWhenDawCloses),
                  subtitle: Text(l10n.companionEndSessionWhenDawClosesDescription),
                  value: endSessionWhenDawCloses,
                  onChanged: onEndSessionChanged,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.companionStartSessionWhenDawOpens),
                  subtitle: Text(l10n.companionStartSessionWhenDawOpensDescription),
                  value: startSessionWhenDawOpens,
                  onChanged: onStartSessionChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
