import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'verified_project_backup.dart';

/// REAPER FILE references are relative to the project directory unless they
/// contain an absolute path. We only stage safely bounded relative sidecars.
///
/// This does not decode opaque plug-in state or guarantee all dependencies are
/// discoverable. Unsupported absolute/external references fail closed.
class ReaperSidecarManifest {
  const ReaperSidecarManifest({
    required this.files,
    required this.totalBytes,
  });

  final List<StagedReaperSidecar> files;
  final int totalBytes;

  Map<String, Object?> toJson() => {
    'files_staged': files.length,
    'total_bytes_staged': totalBytes,
    'files': [for (final item in files) item.toJson()],
    'opaque_plugin_media_verified': false,
  };
}

class StagedReaperSidecar {
  const StagedReaperSidecar({
    required this.relativePath,
    required this.length,
    required this.sha256Digest,
  });

  final String relativePath;
  final int length;
  final String sha256Digest;

  Map<String, Object> toJson() => {
    'relative_path': relativePath,
    'length': length,
    'sha256': sha256Digest,
  };
}

class ReaperSidecarStager {
  static final _reference = RegExp(
    r'^\s*FILE\s+(?:"([^"]+)"|(\S+))',
    multiLine: true,
  );
  static final _windowsDrive = RegExp(r'^[A-Za-z]:');

  static Future<ReaperSidecarManifest> stage({
    required File original,
    required Directory workspace,
    int maxFiles = 2000,
    int maxBytes = 4 * 1024 * 1024 * 1024,
  }) async {
    if (maxFiles < 1 || maxBytes < 1) throw ArgumentError('Invalid media limits');
    final content = utf8.decode(await original.readAsBytes(), allowMalformed: true);
    final references = <String>{};
    for (final match in _reference.allMatches(content)) {
      final raw = match.group(1) ?? match.group(2) ?? '';
      if (raw.trim().isEmpty) continue;
      final unix = raw.replaceAll('\\', '/');
      if (p.posix.isAbsolute(unix) || _windowsDrive.hasMatch(raw) ||
          p.windows.isAbsolute(raw) ||
          unix.split('/').contains('..')) {
        throw FormatException(
          'External or parent-relative media reference requires manual relocation',
        );
      }
      final relative = p.normalize(unix.replaceAll('/', p.separator));
      if (relative == '.' || p.isAbsolute(relative) ||
          relative == '..' || p.split(relative).contains('..')) {
        throw const FormatException('Invalid media relative path');
      }
      references.add(relative);
      if (references.length > maxFiles) {
        throw const FormatException('Too many referenced media files');
      }
    }

    final staged = <StagedReaperSidecar>[];
    var totalBytes = 0;
    for (final relative in references) {
      final source = File(p.join(original.parent.path, relative));
      await VerifiedProjectBackup.ensureNoSymlinkComponents(source.absolute.path);
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FormatException('Referenced media not found: ' + relative);
      }
      final length = await source.length();
      totalBytes += length;
      if (totalBytes > maxBytes) {
        throw const FormatException('Referenced media exceeds staging size limit');
      }
      final clone = File(p.join(workspace.path, relative));
      await clone.parent.create(recursive: true);
      final before = await _digest(source);
      await source.copy(clone.path);
      final after = await _digest(source);
      if (before != after || before != await _digest(clone) ||
          length != await clone.length()) {
        throw const FileSystemException('Media staging verification failed');
      }
      staged.add(StagedReaperSidecar(
        relativePath: relative,
        length: length,
        sha256Digest: before,
      ));
    }
    return ReaperSidecarManifest(
      files: List.unmodifiable(staged),
      totalBytes: totalBytes,
    );
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
