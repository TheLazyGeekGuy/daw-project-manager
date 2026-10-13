/// [paths] (relative, `/`-separated files) drawn as a tree under [rootName],
/// the way `tree` prints a folder: folders first, then files, each sorted
/// case-insensitively, a folder followed by how many files it holds in all.
///
/// ```text
/// Pack/ (3)
/// ├── Kick/ (2)
/// │   ├── kick 1.wav
/// │   └── kick 2.wav
/// └── report.csv
/// ```
String folderTreeText(String rootName, Iterable<String> paths) {
  final root = _Folder();
  for (final path in paths) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    var folder = root;
    for (final name in parts.take(parts.length - 1)) {
      folder = folder.folders.putIfAbsent(name, _Folder.new);
    }
    folder.files.add(parts.last);
  }

  final out = StringBuffer('$rootName/ (${root.fileCount})\n');
  void draw(_Folder folder, String indent) {
    int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final folderNames = folder.folders.keys.toList()..sort(byName);
    final fileNames = folder.files.toList()..sort(byName);
    final count = folderNames.length + fileNames.length;
    var i = 0;
    for (final name in folderNames) {
      final last = ++i == count;
      final sub = folder.folders[name]!;
      out.writeln('$indent${last ? '└── ' : '├── '}$name/ (${sub.fileCount})');
      draw(sub, '$indent${last ? '    ' : '│   '}');
    }
    for (final name in fileNames) {
      final last = ++i == count;
      out.writeln('$indent${last ? '└── ' : '├── '}$name');
    }
  }

  draw(root, '');
  return out.toString();
}

class _Folder {
  final folders = <String, _Folder>{};
  final files = <String>{};

  int get fileCount =>
      files.length + folders.values.fold(0, (n, f) => n + f.fileCount);
}
