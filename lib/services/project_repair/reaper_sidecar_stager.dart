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
  const ReaperSidecarManifest({required this.files, required this.totalBytes});

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
    r'''^(\s*FILE\s+)(?:"([^"]+)"|'([^']+)'|`([^`]+)`|(\S+))(.*)$''',
    multiLine: true,
  );
  static final _windowsDrive = RegExp(r'^[A-Za-z]:');

  static Future<ReaperSidecarManifest> stage({
    required File original,
    required Directory workspace,
    int maxFiles = 2000,
    int maxBytes = 4 * 1024 * 1024 * 1024,
  }) async {
    if (maxFiles < 1 || maxBytes < 1) {
      throw ArgumentError('Invalid media limits');
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
      workspace.absolute.path,
    );
    if (p.equals(
      p.normalize(workspace.absolute.path),
      p.normalize(original.parent.absolute.path),
    )) {
      throw const FileSystemException(
        'Media staging must use a separate directory',
      );
    }
    final content = utf8.decode(
      await original.readAsBytes(),
      allowMalformed: true,
    );
    final references = <String>{};
    for (final match in _reference.allMatches(content)) {
      final raw = _pathFrom(match);
      if (raw.trim().isEmpty) continue;
      final unix = raw.replaceAll('\\', '/');
      if (p.posix.isAbsolute(unix) ||
          _windowsDrive.hasMatch(raw) ||
          p.windows.isAbsolute(raw) ||
          unix.split('/').contains('..')) {
        throw FormatException(
          'External or parent-relative media reference requires manual relocation',
        );
      }
      final relative = p.normalize(unix.replaceAll('/', p.separator));
      if (relative == '.' ||
          p.isAbsolute(relative) ||
          relative == '..' ||
          p.split(relative).contains('..')) {
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
      await VerifiedProjectBackup.ensureNoSymlinkComponents(
        source.absolute.path,
      );
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FormatException('Referenced media not found: $relative');
      }
      final length = await source.length();
      totalBytes += length;
      if (totalBytes > maxBytes) {
        throw const FormatException(
          'Referenced media exceeds staging size limit',
        );
      }
      final clone = File(p.join(workspace.path, relative));
      await VerifiedProjectBackup.ensureNoSymlinkComponents(
        clone.absolute.path,
      );
      if (await FileSystemEntity.type(clone.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'Media staging would overwrite an existing file',
        );
      }
      await clone.parent.create(recursive: true);
      final before = await _digest(source);
      await source.copy(clone.path);
      final after = await _digest(source);
      if (before != after ||
          before != await _digest(clone) ||
          length != await clone.length()) {
        throw const FileSystemException('Media staging verification failed');
      }
      staged.add(
        StagedReaperSidecar(
          relativePath: relative,
          length: length,
          sha256Digest: before,
        ),
      );
    }
    return ReaperSidecarManifest(
      files: List.unmodifiable(staged),
      totalBytes: totalBytes,
    );
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static String _pathFrom(Match match) =>
      match.group(2) ??
      match.group(3) ??
      match.group(4) ??
      match.group(5) ??
      '';

  /// Make only the newly generated RPP portable. Every referenced file must
  /// already be inside this conversion workspace; host files are never copied.
  static Future<Map<String, Object?>> materializeOutput({
    required File output,
    required Directory trustedWorkspace,
    int maxFiles = 2000,
    int maxBytes = 4 * 1024 * 1024 * 1024,
  }) async {
    await VerifiedProjectBackup.ensureNoSymlinkComponents(output.absolute.path);
    final root = p.normalize(trustedWorkspace.absolute.path);
    if (!p.isWithin(root, p.normalize(output.absolute.path))) {
      throw const FileSystemException(
        'Output must be inside its managed workspace',
      );
    }
    final content = utf8.decode(await output.readAsBytes());
    final originalHash = await _digest(output);
    final replacements = <String, String>{};
    final files = <Map<String, Object?>>[];
    var total = 0;
    for (final match in _reference.allMatches(content)) {
      final raw = _pathFrom(match);
      if (replacements.containsKey(raw)) continue;
      if (replacements.length >= maxFiles) {
        throw const FormatException('Too many output media references');
      }
      final normalized = raw.replaceAll('\\', '/');
      if (!Platform.isWindows && _windowsDrive.hasMatch(raw)) {
        throw const FormatException(
          'Output uses a foreign absolute media path',
        );
      }
      final path = p.normalize(
        p.isAbsolute(normalized)
            ? normalized
            : p.join(output.parent.absolute.path, normalized),
      );
      if (!p.isWithin(root, path) || p.equals(path, output.absolute.path)) {
        throw const FileSystemException(
          'Output references media outside its managed workspace',
        );
      }
      await VerifiedProjectBackup.ensureNoSymlinkComponents(path);
      final source = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException(
          'Generated project references missing media',
        );
      }
      final length = await source.length();
      total += length;
      if (total > maxBytes) {
        throw const FormatException('Output media exceeds size limit');
      }
      final hash = await _digest(source);
      final extension = p.extension(path).toLowerCase();
      if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)) {
        throw const FormatException(
          'Output media has an unsupported extension',
        );
      }
      final relative = 'media/$hash$extension';
      final target = File(p.join(output.parent.path, relative));
      await VerifiedProjectBackup.ensureNoSymlinkComponents(
        target.absolute.path,
      );
      await target.parent.create(recursive: true);
      if (!await target.exists()) await source.copy(target.path);
      if (await _digest(source) != hash ||
          await _digest(target) != hash ||
          await target.length() != length) {
        throw const FileSystemException('Output media verification failed');
      }
      replacements[raw] = relative;
      files.add({'relative_path': relative, 'sha256': hash, 'bytes': length});
    }
    if (replacements.isNotEmpty) {
      final rewritten = content.replaceAllMapped(
        _reference,
        (match) =>
            '${match.group(1)}"${replacements[_pathFrom(match)]}"${match.group(6) ?? ''}',
      );
      final staging = File('${output.path}.portable.tmp');
      if (await staging.exists()) {
        throw const FileSystemException('Output staging collision');
      }
      await staging.writeAsString(rewritten, flush: true);
      await staging.rename(output.path);
    }
    return {
      'status': 'referenced_files_materialized',
      'generated_before_relocation_sha256': originalHash,
      'files': files,
      'total_bytes': total,
      'opaque_plugin_media_verified': false,
    };
  }
}
