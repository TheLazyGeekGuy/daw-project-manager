import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'verified_project_backup.dart';

/// Copies a user-installed converter into its own bounded working directory.
/// DawVert reads data_main/plugins relative to cwd and writes sample caches
/// there. Running its original script in an empty export folder is incorrect.
/// A runtime snapshot prevents those writes reaching the user's installation.
class ConverterRuntimeStager {
  static const _directories = {
    'data_main',
    'data_ext',
    'functions',
    'functions_compat',
    'functions_plugin',
    'functions_plugin_cvpj',
    'functions_plugin_ext',
    'functions_plugin_ext_nonfree',
    'functions_song',
    'objects',
    'objects_midi',
    'objects_ui',
    'plugins',
  };

  static Future<Map<String, Object?>> stageDawVert({
    required File script,
    required Directory destination,
    int maxFiles = 10000,
    int maxBytes = 256 * 1024 * 1024,
  }) async {
    await VerifiedProjectBackup.ensureNoSymlinkComponents(script.absolute.path);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
      destination.absolute.path,
    );
    await destination.create(recursive: true);
    var files = 0;
    var total = 0;
    final hashes = <String, String>{};

    Future<void> copyFile(File source) async {
      final relative = p.relative(source.path, from: script.parent.path);
      if (p.split(relative).contains('__pycache__') ||
          relative.endsWith('.pyc')) {
        return;
      }
      final type = await FileSystemEntity.type(source.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const FileSystemException(
          'Converter runtime contains a non-regular file',
        );
      }
      final length = await source.length();
      files++;
      total += length;
      if (files > maxFiles || total > maxBytes) {
        throw const FormatException(
          'Converter runtime exceeds snapshot limits',
        );
      }
      final target = File(p.join(destination.path, relative));
      await target.parent.create(recursive: true);
      final before = await _digest(source);
      await source.copy(target.path);
      if (await _digest(target) != before || await _digest(source) != before) {
        throw const FileSystemException(
          'Converter runtime changed during snapshot',
        );
      }
      hashes[relative.replaceAll(p.separator, '/')] = before;
    }

    await for (final entry in script.parent.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is File && name.endsWith('.py')) await copyFile(entry);
      if (!_directories.contains(name)) continue;
      if (entry is! Directory) {
        throw const FileSystemException(
          'Converter runtime directory is linked or invalid',
        );
      }
      await for (final child in entry.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is Link) {
          throw const FileSystemException(
            'Converter runtime symlinks are not supported',
          );
        }
        if (child is File) await copyFile(child);
      }
    }
    if (!await File(p.join(destination.path, 'dawvert_cmd.py')).exists()) {
      throw const FileSystemException(
        'Converter entry point missing from snapshot',
      );
    }
    return {
      'files': files,
      'bytes': total,
      'entry_point_sha256': hashes['dawvert_cmd.py'],
      'file_sha256': hashes,
      'user_config_copied': false,
      'runtime_is_os_sandbox': false,
    };
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
