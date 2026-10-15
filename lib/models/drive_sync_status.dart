import '../services/drive_sync_errors.dart';

/// What the dashboard's cloud button shows about Drive sync.
enum DriveSyncIndicator {
  /// Not signed in, or nothing to say.
  none,

  /// A sync is running.
  syncing,

  /// The last sync failed (kept until one succeeds, across restarts).
  failed,

  /// Another device has written to Drive since this one last synced.
  newerOnDrive,

  /// Signed in and level with Drive.
  upToDate,
}

/// Drive sync's state as the whole app sees it — the dashboard, the tray,
/// the sync page and the automatic timer all read and report here, so a
/// failure in the background doesn't go unnoticed.
class DriveSyncStatus {
  const DriveSyncStatus({
    this.signedIn = false,
    this.syncing = false,
    this.lastSyncedAt,
    this.lastFailureAt,
    this.lastFailureMessage,
    this.lastFailureKind,
    this.newerOnDrive = false,
    this.remoteDevice,
    this.remoteUpdatedAt,
  });

  final bool signedIn;
  final bool syncing;

  /// When this device last finished a sync, upload or restore.
  final DateTime? lastSyncedAt;
  final DateTime? lastFailureAt;
  final String? lastFailureMessage;
  final SyncErrorKind? lastFailureKind;
  final bool newerOnDrive;

  /// Which device last wrote the backup on Drive, and when (Drive's clock).
  final String? remoteDevice;
  final DateTime? remoteUpdatedAt;

  bool get hasFailure => lastFailureAt != null;

  DriveSyncIndicator get indicator {
    if (syncing) return DriveSyncIndicator.syncing;
    if (hasFailure) return DriveSyncIndicator.failed;
    if (!signedIn) return DriveSyncIndicator.none;
    if (newerOnDrive) return DriveSyncIndicator.newerOnDrive;
    return DriveSyncIndicator.upToDate;
  }

  DriveSyncStatus copyWith({
    bool? signedIn,
    bool? syncing,
    DateTime? lastSyncedAt,
    DateTime? lastFailureAt,
    String? lastFailureMessage,
    SyncErrorKind? lastFailureKind,
    bool clearFailure = false,
    bool? newerOnDrive,
    String? remoteDevice,
    DateTime? remoteUpdatedAt,
    bool clearRemote = false,
  }) =>
      DriveSyncStatus(
        signedIn: signedIn ?? this.signedIn,
        syncing: syncing ?? this.syncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastFailureAt: clearFailure ? null : (lastFailureAt ?? this.lastFailureAt),
        lastFailureMessage:
            clearFailure ? null : (lastFailureMessage ?? this.lastFailureMessage),
        lastFailureKind:
            clearFailure ? null : (lastFailureKind ?? this.lastFailureKind),
        newerOnDrive: newerOnDrive ?? this.newerOnDrive,
        remoteDevice: clearRemote ? null : (remoteDevice ?? this.remoteDevice),
        remoteUpdatedAt:
            clearRemote ? null : (remoteUpdatedAt ?? this.remoteUpdatedAt),
      );
}
