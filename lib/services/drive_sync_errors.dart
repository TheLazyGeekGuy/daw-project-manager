import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;

import 'google_drive_sync_service.dart';

/// What went wrong with a sync, in terms a user can act on. The UI turns
/// each into a sentence; the raw error is only ever a detail under it.
enum SyncErrorKind {
  /// No connection to Google (offline, DNS, TLS, timeout).
  offline,

  /// Google no longer accepts this device's sign-in: sign in again.
  signInExpired,

  /// The user's Google Drive is out of space.
  driveFull,

  /// There is no backup on Drive yet.
  noBackup,

  /// Anything else — shown with its details.
  other,
}

SyncErrorKind classifySyncError(Object error) {
  if (error is NoBackupOnDriveException) return SyncErrorKind.noBackup;
  if (error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException ||
      error is http.ClientException) {
    return SyncErrorKind.offline;
  }
  if (error is auth_io.AccessDeniedException) return SyncErrorKind.signInExpired;
  if (error is drive.DetailedApiRequestError) {
    final reasons = [for (final e in error.errors) e.reason ?? ''];
    final message = (error.message ?? '').toLowerCase();
    if (reasons.contains('storageQuotaExceeded') ||
        message.contains('storagequotaexceeded') ||
        message.contains('storage quota')) {
      return SyncErrorKind.driveFull;
    }
    if (error.status == 401) return SyncErrorKind.signInExpired;
    return SyncErrorKind.other;
  }
  if ('$error'.contains('Not signed in to Google Drive')) {
    return SyncErrorKind.signInExpired;
  }
  return SyncErrorKind.other;
}

/// [SyncErrorKind] from its stored name; unknown names read as [SyncErrorKind.other].
SyncErrorKind syncErrorKindFromName(String? name) => SyncErrorKind.values
    .firstWhere((k) => k.name == name, orElse: () => SyncErrorKind.other);
