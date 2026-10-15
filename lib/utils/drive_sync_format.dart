import 'package:intl/intl.dart';

import '../generated/l10n/app_localizations.dart';
import '../services/drive_sync_errors.dart';
import '../services/google_drive_sync_service.dart';

/// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago", then the
/// date — how the sync page says when something happened.
String syncAgoLabel(
  AppLocalizations l10n,
  DateTime when,
  DateTime now, {
  required String locale,
}) {
  final local = when.toLocal();
  final diff = now.difference(local);
  if (diff.inSeconds < 60) return l10n.driveAgoJustNow;
  if (diff.inMinutes < 60) return l10n.driveAgoMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l10n.driveAgoHours(diff.inHours);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 1) return l10n.dateYesterday;
  if (days < 7) return l10n.dateDaysAgo(days);
  return DateFormat.yMMMd(locale).format(local);
}

/// A byte count for people: 900 B, 12 KB, 4.2 MB, 1.3 GB.
String formatSyncBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}

/// One sentence for a sync error, in the user's language. The raw error is
/// shown under it as details, never instead of it.
String syncErrorSentence(AppLocalizations l10n, SyncErrorKind kind) {
  switch (kind) {
    case SyncErrorKind.offline:
      return l10n.driveErrorOffline;
    case SyncErrorKind.signInExpired:
      return l10n.driveErrorSignInExpired;
    case SyncErrorKind.driveFull:
      return l10n.driveErrorDriveFull;
    case SyncErrorKind.noBackup:
      return l10n.driveErrorNoBackup;
    case SyncErrorKind.other:
      return l10n.driveErrorOther;
  }
}

/// Why a desktop sign-in could not finish, in the user's language.
String signInFailureSentence(AppLocalizations l10n, DesktopSignInFailure f) {
  switch (f) {
    case DesktopSignInFailure.portInUse:
      return l10n.driveSignInPortInUse('${GoogleDriveSyncService.loopbackPort}');
    case DesktopSignInFailure.timedOut:
      return l10n.driveSignInTimedOut;
    case DesktopSignInFailure.browserUnavailable:
      return l10n.driveSignInNoBrowser;
  }
}

/// The browser's "you can go back to the app" page, in the user's language.
LoopbackPageTexts loopbackPageTexts(AppLocalizations l10n) => LoopbackPageTexts(
      successHeading: l10n.driveBrowserSignedInTitle,
      successMessage: l10n.driveBrowserSignedInBody,
      cancelledHeading: l10n.driveBrowserCancelledTitle,
      cancelledMessage: l10n.driveBrowserCancelledBody,
      errorHeading: l10n.driveBrowserErrorTitle,
      errorMessage: l10n.driveBrowserErrorBody,
    );

/// The lines a merge preview reads as ("3 new projects", "1 project
/// updated"…); empty when it changes nothing.
List<String> mergePreviewLines(AppLocalizations l10n, MergePreview p) => [
      if (p.projectsAdded > 0) l10n.driveMergeAdds(p.projectsAdded),
      if (p.projectsUpdated > 0) l10n.driveMergeUpdates(p.projectsUpdated),
      if (p.projectsDeleted > 0) l10n.driveMergeRemoves(p.projectsDeleted),
      if (p.releasesAdded > 0) l10n.driveMergeReleases(p.releasesAdded),
      if (p.releasesDeleted > 0)
        l10n.driveMergeReleasesRemoved(p.releasesDeleted),
    ];
