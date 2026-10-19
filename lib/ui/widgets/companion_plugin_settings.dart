import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/companion_bridge/companion_install_scan.dart';
import '../../services/companion_bridge/companion_protocol.dart';

/// Settings > DAW plugin: what the DPM Companion plugin is, whether this
/// computer has seen it, which copies are installed where, where to get it
/// (or its update), and the work session switches it drives.
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
    this.installs,
    this.searching = false,
    this.scanAvailable = true,
    this.customFolders = const [],
    this.onSearchAgain,
    this.onAddFolder,
    this.onRemoveFolder,
  });

  final CompanionSighting? sighting;
  final CompanionRelease? latestRelease;
  final CompanionPlatform platform;
  final bool endSessionWhenDawCloses;
  final bool startSessionWhenDawOpens;
  final ValueChanged<String> onDownload;
  final ValueChanged<bool> onEndSessionChanged;
  final ValueChanged<bool> onStartSessionChanged;

  /// The installed copies found on disk; null while searching or where the
  /// folders can't be seen.
  final List<CompanionInstall>? installs;
  final bool searching;

  /// False inside the Flatpak, whose sandbox can't see the plug-in folders.
  final bool scanAvailable;

  /// The user's own folders, offered only when the standard ones have no copy.
  final List<String> customFolders;
  final VoidCallback? onSearchAgain;
  final VoidCallback? onAddFolder;
  final ValueChanged<String>? onRemoveFolder;

  /// The version this computer has: the newest installed copy, else the one
  /// last seen running.
  String? get installedVersion =>
      newestInstalledCompanionVersion(installs ?? const []) ?? sighting?.version;

  /// A newer release than the version this computer has.
  bool get updateAvailable {
    final have = installedVersion, latest = latestRelease;
    return have != null && latest != null && isNewerCompanionVersion(latest.version, have);
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
                const SizedBox(height: 16),
                _InstalledCopies(view: this, l10n: l10n),
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

/// "Installed": each copy with its format, version and folder, a warning when
/// there are two of one format, and — only when the standard folders have
/// none — the user's own folders to look in.
class _InstalledCopies extends StatelessWidget {
  const _InstalledCopies({required this.view, required this.l10n});

  final CompanionPluginSettingsView view;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installs = view.installs ?? const <CompanionInstall>[];
    final foundInStandard = installs.any((i) => !i.inCustomFolder);

    Widget searchAgain() => TextButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.companionSearchAgain),
          onPressed: view.searching ? null : view.onSearchAgain,
        );

    if (!view.scanAvailable) {
      return Text(l10n.companionScanUnavailable, style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.companionInstalledTitle, style: theme.textTheme.titleSmall)),
            if (view.searching)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(l10n.companionSearching, style: theme.textTheme.bodySmall),
              )
            else
              searchAgain(),
          ],
        ),
        if (!view.searching && installs.isEmpty)
          Text(l10n.companionInstalledNone, style: theme.textTheme.bodyMedium),
        for (final install in installs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(install.format == CompanionPluginFormat.au ? Icons.apple : Icons.extension_outlined, size: 20),
            title: Text('${install.format == CompanionPluginFormat.au ? 'AU' : 'VST3'}  ·  '
                '${l10n.companionInstalledVersion(install.version)}'),
            subtitle: Text(install.inCustomFolder ? '${install.path}  ·  ${l10n.companionCustomFolderTag}' : install.path),
          ),
        if (hasDuplicateCompanionInstalls(installs))
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.companionInstalledDuplicates, style: theme.textTheme.bodySmall)),
            ],
          ),
        // The user's own folders: only when the standard ones have no copy.
        if (!view.searching && !foundInStandard) ...[
          const SizedBox(height: 8),
          Text(l10n.companionCustomFoldersHint, style: theme.textTheme.bodySmall),
          for (final folder in view.customFolders)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(folder),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.remove,
                onPressed: view.onRemoveFolder == null ? null : () => view.onRemoveFolder!(folder),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: Text(l10n.addFolder),
              onPressed: view.onAddFolder,
            ),
          ),
        ],
      ],
    );
  }
}
