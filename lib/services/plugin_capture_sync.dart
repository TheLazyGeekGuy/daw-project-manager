// What Drive sync does with the DAW plugin's latest captures — the rules
// only, no Drive: google_drive_capture_sync.dart does the uploading and
// downloading they decide on.
//
// A capture's file travels like a preview song's, but on its own track: the
// backup's `pluginCaptures` maps "<profileId>/<projectId>" (rows are matched
// by profile and id, never id alone) to one [CaptureEntry].

import '../models/plugin_capture.dart';

/// One project's capture as the backup on Drive knows it.
class CaptureEntry {
  const CaptureEntry({
    required this.fileId,
    required this.hash,
    required this.name,
    required this.capturedAt,
    required this.durationSeconds,
  });

  /// The file on Drive.
  final String fileId;

  /// Its content hash: an unchanged file is never uploaded again.
  final String hash;

  /// The file name the capture had, kept for the copy each device makes.
  final String name;

  final DateTime capturedAt;
  final double durationSeconds;

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'hash': hash,
        'name': name,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'seconds': durationSeconds,
      };

  /// Null for anything malformed: one bad entry costs that capture, never
  /// the sync.
  static CaptureEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final fileId = raw['fileId'], hash = raw['hash'], name = raw['name'], seconds = raw['seconds'];
    final at = raw['capturedAt'] is String ? DateTime.tryParse(raw['capturedAt'] as String) : null;
    if (fileId is! String || hash is! String || name is! String || seconds is! num || at == null) return null;
    return CaptureEntry(
      fileId: fileId,
      hash: hash,
      name: name,
      capturedAt: at.toLocal(),
      durationSeconds: seconds.toDouble(),
    );
  }

  CaptureEntry withFile(String fileId, String hash) => CaptureEntry(
      fileId: fileId, hash: hash, name: name, capturedAt: capturedAt, durationSeconds: durationSeconds);
}

String captureEntryKey(String profileId, String projectId) => '$profileId/$projectId';

/// Every well-formed entry of a backup's `pluginCaptures`.
Map<String, CaptureEntry> captureEntriesFrom(Object? raw) {
  if (raw is! Map) return const {};
  final entries = <String, CaptureEntry>{};
  for (final e in raw.entries) {
    final entry = CaptureEntry.tryFromJson(e.value);
    if (e.key is String && entry != null) entries[e.key as String] = entry;
  }
  return entries;
}

/// What the upload does with one project's capture.
sealed class CaptureUpload {
  const CaptureUpload();
}

/// Nothing to send: no capture, or one that is neither here nor on Drive.
class NoCaptureUpload extends CaptureUpload {
  const NoCaptureUpload();
}

/// Drive already has this very file: keep its entry.
class KeepCaptureEntry extends CaptureUpload {
  const KeepCaptureEntry(this.entry);
  final CaptureEntry entry;
}

/// Send the file (new, or changed since the entry on Drive).
class UploadCapture extends CaptureUpload {
  const UploadCapture({this.replacing});

  /// The entry it replaces, whose Drive file is overwritten in place.
  final CaptureEntry? replacing;
}

/// Decides what the upload does with [local], whose file has [localHash]
/// when it is on this device (null when it isn't — synced from elsewhere,
/// not come down yet), given [onDrive], the entry the backup already holds.
CaptureUpload decideCaptureUpload({
  required PluginCapture? local,
  required String? localHash,
  required CaptureEntry? onDrive,
}) {
  if (local == null) return const NoCaptureUpload();
  final sameTake = onDrive != null && onDrive.capturedAt.isAtSameMomentAs(local.capturedAt);
  if (localHash == null) {
    // Not here to send; while Drive's entry is this very take, keep it, or
    // this device's upload would take the capture away from every other.
    return sameTake ? KeepCaptureEntry(onDrive) : const NoCaptureUpload();
  }
  if (onDrive != null && onDrive.hash == localHash) return KeepCaptureEntry(onDrive);
  return UploadCapture(replacing: onDrive);
}

/// Whether a merge downloads [remote]: when this device has no capture, an
/// older one, or this very one without its file.
bool captureNeedsDownload({
  required PluginCapture? local,
  required bool localFileExists,
  required CaptureEntry remote,
}) {
  if (local == null) return true;
  if (remote.capturedAt.isAfter(local.capturedAt)) return true;
  return remote.capturedAt.isAtSameMomentAs(local.capturedAt) && !localFileExists;
}
