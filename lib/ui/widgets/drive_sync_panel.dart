import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../models/auto_backup_interval.dart';
import '../../utils/drive_sync_format.dart';

/// Everything the Google Drive sync page shows, as plain values — resolved
/// by `GoogleDriveSyncSection` from the sync service and
/// `driveSyncStatusProvider`, so this widget needs no Riverpod or Hive and
/// can be tested on its own.
class DriveSyncPanelData {
  const DriveSyncPanelData({
    required this.now,
    this.checkingSession = false,
    this.signedIn = false,
    this.waitingForBrowser = false,
    this.busy = false,
    this.email,
    this.lastSyncedAt,
    this.remoteUpdatedAt,
    this.remoteDevice,
    this.remoteIsThisDevice = false,
    this.newerOnDrive = false,
    this.errorTitle,
    this.errorText,
    this.errorDetails,
    this.interval = AutoBackupInterval.off,
    this.lastAutoSyncAt,
    this.uploadAutoDetected = false,
    this.syncOnStartup = true,
    this.isMobile = false,
  });

  final DateTime now;
  final bool checkingSession;
  final bool signedIn;
  final bool waitingForBrowser;

  /// A sync, restore or other Drive operation is running.
  final bool busy;
  final String? email;
  final DateTime? lastSyncedAt;
  final DateTime? remoteUpdatedAt;
  final String? remoteDevice;
  final bool remoteIsThisDevice;
  final bool newerOnDrive;

  /// A heading for the error ("Last sync failed 2 h ago"), optional.
  final String? errorTitle;

  /// What went wrong, in a sentence; null when nothing did.
  final String? errorText;

  /// The raw error under the sentence.
  final String? errorDetails;
  final AutoBackupInterval interval;

  /// When automatic sync last ran, for its "next sync in …" line.
  final DateTime? lastAutoSyncAt;
  final bool uploadAutoDetected;
  final bool syncOnStartup;
  final bool isMobile;
}

class DriveSyncPanel extends StatelessWidget {
  const DriveSyncPanel({
    super.key,
    required this.data,
    required this.onSignIn,
    required this.onCancelSignIn,
    required this.onSignOut,
    required this.onSyncNow,
    required this.onRestoreFromDrive,
    required this.onRecoverEarlier,
    required this.onOverwriteDrive,
    required this.onDeleteDriveData,
    required this.onIntervalChanged,
    required this.onUploadAutoDetectedChanged,
    required this.onSyncOnStartupChanged,
    required this.snapshotsKept,
  });

  final DriveSyncPanelData data;
  final VoidCallback onSignIn;
  final VoidCallback onCancelSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onSyncNow;
  final VoidCallback onRestoreFromDrive;
  final VoidCallback onRecoverEarlier;
  final VoidCallback onOverwriteDrive;
  final VoidCallback onDeleteDriveData;
  final ValueChanged<AutoBackupInterval> onIntervalChanged;
  final ValueChanged<bool> onUploadAutoDetectedChanged;
  final ValueChanged<bool> onSyncOnStartupChanged;
  final int snapshotsKept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _accountCard(context, l10n),
        const SizedBox(height: 12),
        _autoSyncCard(context, l10n),
        if (data.signedIn) ...[
          const SizedBox(height: 12),
          _moreOptionsCard(context, l10n),
        ],
      ],
    );
  }

  String _ago(BuildContext context, AppLocalizations l10n, DateTime when) =>
      syncAgoLabel(
        l10n,
        when,
        data.now,
        locale: Localizations.localeOf(context).toString(),
      );

  Widget _accountCard(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.googleDriveSync,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (data.busy || data.checkingSession)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.checkingSession)
              const SizedBox(height: 48)
            else if (!data.signedIn)
              ..._signedOut(context, l10n)
            else
              ..._signedIn(context, l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _signedOut(BuildContext context, AppLocalizations l10n) => [
        Text(l10n.driveSyncIntro, style: Theme.of(context).textTheme.bodyMedium),
        if (data.errorText != null) ...[
          const SizedBox(height: 12),
          _errorBanner(context, l10n),
        ],
        const SizedBox(height: 16),
        if (data.waitingForBrowser)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.driveWaitingForBrowser)),
              TextButton(onPressed: onCancelSignIn, child: Text(l10n.cancel)),
            ],
          )
        else
          Align(
            alignment: data.isMobile ? Alignment.center : Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.login, size: 18),
              label: Text(l10n.signInToGoogleDrive),
              onPressed: data.busy ? null : onSignIn,
            ),
          ),
      ];

  List<Widget> _signedIn(BuildContext context, AppLocalizations l10n) {
    final remoteLine = data.remoteUpdatedAt == null
        ? l10n.driveNoBackupYet
        : (data.remoteIsThisDevice || data.remoteDevice != null)
            ? l10n.driveUpdatedFrom(
                _ago(context, l10n, data.remoteUpdatedAt!),
                data.remoteIsThisDevice ? l10n.driveThisDevice : data.remoteDevice!,
              )
            : l10n.driveUpdatedAt(_ago(context, l10n, data.remoteUpdatedAt!));
    final syncButton = FilledButton.icon(
      icon: const Icon(Icons.sync, size: 18),
      label: Text(l10n.driveSyncNow),
      onPressed: data.busy ? null : onSyncNow,
    );
    final signOutButton = TextButton.icon(
      icon: const Icon(Icons.logout, size: 18),
      label: Text(l10n.signOut),
      onPressed: data.busy ? null : onSignOut,
    );
    return [
      _infoRow(
        context,
        Icons.person_outline,
        data.email == null ? l10n.googleDrive : l10n.signedInAs(data.email!),
      ),
      _infoRow(
        context,
        Icons.devices_outlined,
        data.lastSyncedAt == null
            ? l10n.driveThisDeviceNeverSynced
            : l10n.driveThisDeviceSynced(_ago(context, l10n, data.lastSyncedAt!)),
      ),
      _infoRow(context, Icons.cloud_queue, remoteLine),
      if (data.errorText != null) ...[
        const SizedBox(height: 12),
        _errorBanner(context, l10n),
      ] else if (data.newerOnDrive && !data.busy) ...[
        const SizedBox(height: 12),
        _newerBanner(context, l10n),
      ],
      const SizedBox(height: 16),
      if (data.isMobile) ...[
        syncButton,
        const SizedBox(height: 8),
        signOutButton,
      ] else
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [syncButton, const Spacer(), signOutButton],
        ),
      const SizedBox(height: 8),
      Text(l10n.driveSyncNowHint, style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('drive-sync-error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.errorTitle != null)
                  Text(
                    data.errorTitle!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onErrorContainer,
                    ),
                  ),
                Text(data.errorText!, style: TextStyle(color: cs.onErrorContainer)),
                if (data.errorDetails != null && data.errorDetails!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    data.errorDetails!,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onErrorContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _newerBanner(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('drive-sync-newer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.cloud_download_outlined, size: 20, color: cs.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.remoteDevice != null && !data.remoteIsThisDevice
                  ? l10n.driveNewerBanner(data.remoteDevice!)
                  : l10n.driveNewerBannerNoDevice,
              style: TextStyle(color: cs.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoSyncCard(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final enabled = data.signedIn && !data.busy;
    final showNext = data.signedIn &&
        data.interval != AutoBackupInterval.off &&
        data.lastAutoSyncAt != null;
    return Card(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_outlined, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  l10n.driveAutoSyncTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.driveAutoSyncDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.driveSyncOnStartup, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                l10n.driveSyncOnStartupHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: data.syncOnStartup,
              onChanged: enabled ? onSyncOnStartupChanged : null,
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              children: [
                Text(l10n.driveAutoSyncIntervalLabel, style: const TextStyle(fontSize: 14)),
                DropdownButton<AutoBackupInterval>(
                  value: data.interval,
                  items: [
                    for (final i in AutoBackupInterval.values)
                      DropdownMenuItem(value: i, child: Text(_intervalLabel(l10n, i))),
                  ],
                  onChanged: enabled
                      ? (v) {
                          if (v != null) onIntervalChanged(v);
                        }
                      : null,
                ),
              ],
            ),
            if (showNext)
              Text(
                l10n.driveNextSync(_nextLabel(l10n)),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.uploadAutoDetectedPreviewSongs, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                l10n.uploadAutoDetectedPreviewSongsSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: data.uploadAutoDetected,
              onChanged: enabled ? onUploadAutoDetectedChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _intervalLabel(AppLocalizations l10n, AutoBackupInterval i) {
    switch (i) {
      case AutoBackupInterval.off:
        return l10n.autoBackupOff;
      case AutoBackupInterval.every30min:
        return l10n.autoBackupEvery30Min;
      case AutoBackupInterval.hourly:
        return l10n.autoBackupHourly;
      case AutoBackupInterval.every6hours:
        return l10n.autoBackupEvery6Hours;
      case AutoBackupInterval.daily:
        return l10n.autoBackupDaily;
    }
  }

  String _nextLabel(AppLocalizations l10n) {
    final next = data.lastAutoSyncAt!.add(data.interval.duration!);
    final diff = next.difference(data.now);
    if (diff.isNegative || diff.inSeconds < 30) return l10n.autoBackupNextSoon;
    if (diff.inMinutes < 60) return l10n.autoBackupNextInMinutes(diff.inMinutes);
    if (diff.inHours == 1) return l10n.autoBackupNextInOneHour;
    if (diff.inHours < 24) return l10n.autoBackupNextInHours(diff.inHours);
    if (diff.inDays == 1) return l10n.autoBackupNextInOneDay;
    return l10n.autoBackupNextInDays(diff.inDays);
  }

  Widget _moreOptionsCard(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? color,
    }) =>
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(icon, color: color),
          title: Text(title, style: color == null ? null : TextStyle(color: color)),
          subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          enabled: !data.busy,
          onTap: onTap,
        );
    return Card(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.settings_backup_restore, color: cs.primary),
        title: Text(l10n.driveMoreOptions),
        children: [
          option(
            icon: Icons.cloud_download_outlined,
            title: l10n.driveRestoreFromDrive,
            subtitle: l10n.driveRestoreFromDriveHint,
            onTap: onRestoreFromDrive,
          ),
          option(
            icon: Icons.history,
            title: l10n.driveRecoverEarlier,
            subtitle: l10n.driveRecoverEarlierHint(snapshotsKept),
            onTap: onRecoverEarlier,
          ),
          option(
            icon: Icons.cloud_upload_outlined,
            title: l10n.driveOverwrite,
            subtitle: l10n.driveOverwriteHint,
            onTap: onOverwriteDrive,
          ),
          option(
            icon: Icons.delete_forever_outlined,
            title: l10n.driveDeleteData,
            subtitle: l10n.driveDeleteDataHint,
            onTap: onDeleteDriveData,
            color: cs.error,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
