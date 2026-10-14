import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/sample_reference.dart';

/// Finds the file a [SampleReference] names on this computer.
///
/// What a project says is often out of date — the project was moved, a
/// drive letter changed, a library was reorganised, FL Studio 7 stored paths
/// relative to an install that no longer exists — so the stored paths are
/// only the first try:
///
/// 1. each of the reference's candidates, a relative one taken from the
///    project's folder and `%VARIABLES%` expanded;
/// 2. files of the same name in the project's folder tree, which is the
///    project's own;
/// 3. files of the same name in the [libraryFolders] the user listed — only
///    those that agree with the project: the size it recorded, or else the
///    folder the file was in (`…\Kick\kick 15.wav` is not just any
///    `kick 15.wav`).
///
/// Among several, one of the size the project recorded wins, then the one
/// sharing the most trailing folders with a stored path, then the first
/// found.
///
/// Folder listings are made once per folder and kept for the locator's
/// lifetime, so one export lists each library once.
class SampleLocator {
  SampleLocator({
    this.libraryFolders = const [],
    Map<String, String>? environment,
    this.projectTreeDepth = 6,
  }) : _environment = environment ?? Platform.environment;

  final List<String> libraryFolders;
  final Map<String, String> _environment;

  /// How deep a project's folder is searched — a project saved at the top
  /// of a drive must not have the whole drive listed.
  final int projectTreeDepth;

  final _indices = <String, Future<Map<String, List<String>>>>{};

  /// The file [ref] names, or null when none can be found.
  Future<String?> locate(SampleReference ref, {required String projectDir}) async {
    for (final candidate in ref.candidates) {
      final path = _expand(candidate, projectDir);
      if (path != null && await File(path).exists()) return p.normalize(path);
    }

    final key = ref.fileName.toLowerCase();
    final inProject =
        (await _index(projectDir, projectTreeDepth))[key] ?? const <String>[];
    if (inProject.isNotEmpty) return _best(inProject, ref);

    // A library holds many "Kick 15.wav"s, so one is only taken when it
    // agrees with what the project recorded: the size, where the format
    // keeps it, or else the folder the file was in.
    final size = ref.sizeBytes;
    final needsFolder = ref.candidates.any((c) => _segments(c).length > 1);
    final trusted = <String>[];
    for (final folder in libraryFolders) {
      for (final hit in (await _index(folder, null))[key] ?? const <String>[]) {
        final ok = size != null
            ? await _sizeOf(hit) == size
            : !needsFolder || _trailingMatch(hit, ref.candidates) >= 2;
        if (ok) trusted.add(hit);
      }
    }
    return trusted.isEmpty ? null : _best(trusted, ref);
  }

  /// The hit sharing the most trailing folders with a stored path, then the
  /// one of the recorded size; the first found on a tie.
  Future<String> _best(List<String> hits, SampleReference ref) async {
    if (hits.length == 1) return hits.single;
    var best = hits.first;
    var bestScore = -1;
    for (final hit in hits) {
      var score = _trailingMatch(hit, ref.candidates) * 2;
      if (ref.sizeBytes != null && await _sizeOf(hit) == ref.sizeBytes) {
        score += 1000;
      }
      if (score > bestScore) {
        best = hit;
        bestScore = score;
      }
    }
    return best;
  }

  static Future<int?> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  /// [candidate] as a path to try here, or null when it can't be one.
  String? _expand(String candidate, String projectDir) {
    var path = candidate.replaceAllMapped(
      RegExp(r'%([A-Za-z0-9_]+)%'),
      (m) => _environment[m[1]!] ?? m[0]!,
    );
    if (path.contains('%')) return null; // A variable this machine lacks.
    if (_isAbsoluteAnywhere(path)) {
      // A Windows path read on macOS/Linux, or the reverse, isn't a path
      // here; the search by name may still find the file.
      if (Platform.isWindows != _isWindowsPath(path)) return null;
      return path;
    }
    // FL Studio's "\Patches\…" is relative to an install, not the project.
    if (path.startsWith(r'\') || path.startsWith('/')) return null;
    return p.join(projectDir, p.joinAll(path.split(RegExp(r'[\\/]'))));
  }

  static bool _isWindowsPath(String path) =>
      RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(path);

  static bool _isAbsoluteAnywhere(String path) =>
      _isWindowsPath(path) || path.startsWith('/') && !path.startsWith('//');

  /// How many path segments [hit] shares, from the end, with the closest of
  /// [candidates], compared case-insensitively.
  static int _trailingMatch(String hit, List<String> candidates) {
    final hitParts = _segments(hit);
    var best = 0;
    for (final c in candidates) {
      final parts = _segments(c);
      var n = 0;
      while (n < hitParts.length &&
          n < parts.length &&
          hitParts[hitParts.length - 1 - n] == parts[parts.length - 1 - n]) {
        n++;
      }
      if (n > best) best = n;
    }
    return best;
  }

  static List<String> _segments(String path) => path
      .toLowerCase()
      .split(RegExp(r'[\\/]'))
      .where((s) => s.isNotEmpty)
      .toList();

  /// Audio files under [root] by lower-case name, [maxDepth] folders deep
  /// (unbounded when null).
  Future<Map<String, List<String>>> _index(String root, int? maxDepth) {
    final key = '${p.normalize(root).toLowerCase()}|$maxDepth';
    return _indices[key] ??= _list(root, maxDepth);
  }

  static Future<Map<String, List<String>>> _list(
    String root,
    int? maxDepth,
  ) async {
    final out = <String, List<String>>{};
    Future<void> walk(Directory dir, int depth) async {
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        return; // An unreadable folder costs that folder.
      }
      for (final entity in entries) {
        if (entity is File) {
          if (!isSampleAudioFile(entity.path)) continue;
          out
              .putIfAbsent(p.basename(entity.path).toLowerCase(), () => [])
              .add(entity.path);
        } else if (entity is Directory &&
            (maxDepth == null || depth < maxDepth)) {
          await walk(entity, depth + 1);
        }
      }
    }

    final dir = Directory(root);
    if (await dir.exists()) await walk(dir, 0);
    return out;
  }
}
