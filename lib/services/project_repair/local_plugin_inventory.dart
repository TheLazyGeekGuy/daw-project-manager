import 'dart:io';

import 'package:path/path.dart' as p;

/// Filesystem evidence only; a found plug-in is not necessarily loadable.
class LocalPluginCandidate {
  const LocalPluginCandidate({
    required this.path,
    required this.name,
    required this.format,
    this.identifier,
  });
  final String path;
  final String name;
  final String format;
  final String? identifier;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'format': format,
    'identifier': identifier,
    'loadability': 'untested',
  };
}

/// Bounded, passive inventory: never executes third-party binaries.
class LocalPluginInventory {
  static const _suffixes = {
    '.vst3': 'VST3',
    '.vst': 'VST2',
    '.dll': 'VST2-candidate',
    '.component': 'AU',
    '.clap': 'CLAP',
  };

  static List<String> defaultRoots() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    if (Platform.isMacOS) {
      return [
      '/Library/Audio/Plug-Ins/VST',
      '/Library/Audio/Plug-Ins/VST3',
      '/Library/Audio/Plug-Ins/Components',
      '/Library/Audio/Plug-Ins/CLAP',
      if (home.isNotEmpty) ...[
        '$home/Library/Audio/Plug-Ins/VST',
        '$home/Library/Audio/Plug-Ins/VST3',
        '$home/Library/Audio/Plug-Ins/Components',
        '$home/Library/Audio/Plug-Ins/CLAP',
      ],
    ];
    }
    if (Platform.isWindows) {
      return [
      r'C:\Program Files\Common Files\VST3',
      r'C:\Program Files\Common Files\CLAP',
      r'C:\Program Files\VstPlugins',
      r'C:\Program Files (x86)\VstPlugins',
    ];
    }
    if (Platform.isLinux) {
      return [
      '/usr/lib/vst', '/usr/lib/vst3', '/usr/lib/clap',
      '/usr/local/lib/vst', '/usr/local/lib/vst3', '/usr/local/lib/clap',
      if (home.isNotEmpty) ...[
        '$home/.vst', '$home/.vst3', '$home/.clap',
      ],
    ];
    }
    return const [];
  }

  /// If a root is untrusted, symlinks are skipped and depth and item count
  /// are bounded. Detection reports names, not authenticated plug-in IDs.
  static List<LocalPluginCandidate> scan({
    List<String>? roots,
    int maxDepth = 6,
    int maxEntries = 30000,
  }) {
    final candidates = <LocalPluginCandidate>[];
    final seen = <String>{};
    var visited = 0;

    void visit(Directory folder, int depth) {
      if (depth > maxDepth || visited >= maxEntries) {
        return;
      }
      Iterable<FileSystemEntity> entries;
      try {
        entries = folder.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entry in entries) {
        if (++visited > maxEntries) break;
        final kind = FileSystemEntity.typeSync(entry.path, followLinks: false);
        if (kind == FileSystemEntityType.link) {
          continue;
        }
        final name = p.basename(entry.path);
        final lower = name.toLowerCase();
        String? format;
        for (final suffix in _suffixes.keys) {
          if (lower.endsWith(suffix)) {
            format = _suffixes[suffix];
            break;
          }
        }
        if (format != null) {
          if (seen.add(p.normalize(entry.absolute.path))) {
            candidates.add(LocalPluginCandidate(
              path: entry.absolute.path,
              name: p.basenameWithoutExtension(name),
              format: format,
            ));
          }
          continue; // Bundle internals are not separate plug-ins.
        }
        if (kind == FileSystemEntityType.directory) visit(Directory(entry.path), depth + 1);
      }
    }

    for (final root in roots ?? defaultRoots()) {
      if (visited >= maxEntries) break;
      if (FileSystemEntity.typeSync(root, followLinks: false) == FileSystemEntityType.directory) {
        visit(Directory(root), 0);
      }
    }
    candidates.sort((a, b) => a.path.compareTo(b.path));
    return List.unmodifiable(candidates);
  }
}
