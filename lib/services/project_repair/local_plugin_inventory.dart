import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Passive installation evidence. A manifest is a declaration, not proof that
/// the binary can load, is licensed, or accepts a project's saved state.
class LocalPluginCandidate {
  const LocalPluginCandidate({
    required this.path,
    required this.name,
    required this.format,
    this.identifier,
    this.vendor,
    this.version,
    this.manifestPath,
    this.compatibleIdentifiers = const [],
  });

  final String path;
  final String name;
  final String format;
  final String? identifier;
  final String? vendor;
  final String? version;
  final String? manifestPath;
  final List<String> compatibleIdentifiers;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'format': format,
    'identifier': identifier,
    'vendor': vendor,
    'version': version,
    'manifest_path': manifestPath,
    'identity_evidence': manifestPath == null ? 'filename' : 'module_manifest',
    'compatible_identifiers': compatibleIdentifiers,
    'loadability': 'untested',
    'license_status': 'unknown',
  };
}

class LocalPluginInventoryReport {
  const LocalPluginInventoryReport({
    required this.candidates,
    required this.requestedRoots,
    required this.scannedRoots,
    required this.warnings,
    required this.visitedEntries,
    required this.truncated,
  });

  final List<LocalPluginCandidate> candidates;
  final List<String> requestedRoots;
  final List<String> scannedRoots;
  final List<String> warnings;
  final int visitedEntries;
  final bool truncated;

  Map<String, Object?> toJson() => {
    'candidates': [for (final candidate in candidates) candidate.toJson()],
    'requested_roots': requestedRoots,
    'scanned_roots': scannedRoots,
    'warnings': warnings,
    'visited_entries': visitedEntries,
    'truncated': truncated,
    'third_party_code_executed': false,
    'absence_is_conclusive': false,
  };
}

/// Bounded, passive inventory. No binary is opened as executable code.
///
/// VST3 processor classes are read from the SDK's optional moduleinfo.json.
/// Other formats remain filename candidates until a reliable identity source
/// is available. In particular, arbitrary DLLs are not labelled verified VST2.
class LocalPluginInventory {
  static const _suffixes = {
    '.vst3': 'VST3',
    '.vst': 'VST2',
    '.dll': 'VST2-candidate',
    '.component': 'AU',
    '.clap': 'CLAP',
  };

  static String? normalizeClassId(String value) {
    var normalized = value.trim().toUpperCase();
    if (normalized.startsWith('{') && normalized.endsWith('}')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    if (RegExp(r'^[A-F0-9]{32}$').hasMatch(normalized)) return normalized;
    if (RegExp(
      r'^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$',
    ).hasMatch(normalized)) {
      return normalized.replaceAll('-', '');
    }
    return null;
  }

  static List<String> defaultRoots() {
    final env = Platform.environment;
    final userDirectory = env['HOME'] ?? env['USERPROFILE'] ?? '';
    if (Platform.isMacOS) {
      return [
        '/Library/Audio/Plug-Ins/VST',
        '/Library/Audio/Plug-Ins/VST3',
        '/Library/Audio/Plug-Ins/Components',
        '/Library/Audio/Plug-Ins/CLAP',
        if (userDirectory.isNotEmpty) ...[
          '$userDirectory/Library/Audio/Plug-Ins/VST',
          '$userDirectory/Library/Audio/Plug-Ins/VST3',
          '$userDirectory/Library/Audio/Plug-Ins/Components',
          '$userDirectory/Library/Audio/Plug-Ins/CLAP',
        ],
      ];
    }
    if (Platform.isWindows) {
      final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';
      final commonFiles =
          env['CommonProgramFiles'] ?? p.join(programFiles, 'Common Files');
      return [
        p.join(commonFiles, 'VST3'),
        p.join(commonFiles, 'CLAP'),
        p.join(programFiles, 'VstPlugins'),
        p.join(
          env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
          'VstPlugins',
        ),
        if (env['LOCALAPPDATA'] case final String localAppData) ...[
          p.join(localAppData, 'Programs', 'Common', 'VST3'),
          p.join(localAppData, 'Programs', 'Common', 'CLAP'),
        ],
      ];
    }
    if (Platform.isLinux) {
      return [
        '/usr/lib/vst',
        '/usr/lib/vst3',
        '/usr/lib/clap',
        '/usr/local/lib/vst',
        '/usr/local/lib/vst3',
        '/usr/local/lib/clap',
        if (userDirectory.isNotEmpty) ...[
          '$userDirectory/.vst',
          '$userDirectory/.vst3',
          '$userDirectory/.clap',
        ],
      ];
    }
    return const [];
  }

  /// Compatibility API for callers that only need candidates. Use scanReport
  /// for diagnostic UI so truncation and unreadable paths remain visible.
  static List<LocalPluginCandidate> scan({
    List<String>? roots,
    int maxDepth = 6,
    int maxEntries = 30000,
  }) => scanReport(
    roots: roots,
    maxDepth: maxDepth,
    maxEntries: maxEntries,
  ).candidates;

  static LocalPluginInventoryReport scanReport({
    List<String>? roots,
    int maxDepth = 6,
    int maxEntries = 30000,
    int maxManifestBytes = 1024 * 1024,
  }) {
    if (maxDepth < 0 || maxEntries < 1 || maxManifestBytes < 1) {
      throw ArgumentError(
        'Inventory limits must be positive (depth may be zero)',
      );
    }
    final candidates = <LocalPluginCandidate>[];
    final warnings = <String>[];
    final seen = <String>{};
    final requestedRoots = (roots ?? defaultRoots())
        .map(p.absolute)
        .map(p.normalize)
        .toSet()
        .toList();
    final scannedRoots = <String>[];
    var visited = 0;
    var truncated = false;

    void visit(Directory folder, int depth) {
      if (depth > maxDepth || visited >= maxEntries) {
        truncated = true;
        return;
      }
      Iterable<FileSystemEntity> entries;
      try {
        entries = folder.listSync(followLinks: false);
      } on FileSystemException {
        warnings.add('Cannot read plug-in directory: ${folder.path}');
        return;
      }
      for (final entry in entries) {
        if (visited >= maxEntries) {
          truncated = true;
          break;
        }
        visited++;
        final kind = FileSystemEntity.typeSync(entry.path, followLinks: false);
        if (kind == FileSystemEntityType.link) {
          warnings.add('Skipped symbolic link: ${entry.path}');
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
        if (format != null &&
            (kind == FileSystemEntityType.file ||
                kind == FileSystemEntityType.directory)) {
          final canonical = p.normalize(entry.absolute.path);
          if (!seen.add(canonical)) continue;
          var manifestCandidates = <LocalPluginCandidate>[];
          if (format == 'VST3' && kind == FileSystemEntityType.directory) {
            manifestCandidates = _readVst3Manifest(
              canonical,
              warnings,
              maxManifestBytes,
            );
          }
          candidates.addAll(
            manifestCandidates.isNotEmpty
                ? manifestCandidates
                : [
                    LocalPluginCandidate(
                      path: canonical,
                      name: p.basenameWithoutExtension(name),
                      format: format,
                    ),
                  ],
          );
          continue; // Bundle internals are not separate plug-ins.
        }
        if (kind == FileSystemEntityType.directory) {
          visit(Directory(entry.path), depth + 1);
        }
      }
    }

    for (final root in requestedRoots) {
      if (visited >= maxEntries) {
        truncated = true;
        break;
      }
      if (_hasLinkedAncestor(root)) {
        warnings.add('Skipped linked inventory root: $root');
      } else if (FileSystemEntity.typeSync(root, followLinks: false) ==
          FileSystemEntityType.directory) {
        scannedRoots.add(root);
        visit(Directory(root), 0);
      } else {
        warnings.add('Inventory root not available: $root');
      }
    }
    if (truncated) {
      warnings.add('Inventory stopped at a configured entry or depth limit');
    }
    candidates.sort((a, b) {
      final pathOrder = a.path.compareTo(b.path);
      return pathOrder == 0
          ? (a.identifier ?? a.name).compareTo(b.identifier ?? b.name)
          : pathOrder;
    });
    return LocalPluginInventoryReport(
      candidates: List.unmodifiable(candidates),
      requestedRoots: List.unmodifiable(requestedRoots),
      scannedRoots: List.unmodifiable(scannedRoots),
      warnings: List.unmodifiable(warnings),
      visitedEntries: visited,
      truncated: truncated,
    );
  }

  static List<LocalPluginCandidate> _readVst3Manifest(
    String bundle,
    List<String> warnings,
    int maxBytes,
  ) {
    for (final relative in [
      p.join('Contents', 'Resources', 'moduleinfo.json'),
      p.join('Contents', 'moduleinfo.json'),
    ]) {
      final path = p.join(bundle, relative);
      if (_hasLinkedAncestor(path)) {
        warnings.add('Skipped linked VST3 manifest: $path');
        continue;
      }
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final file = File(path);
        if (file.lengthSync() > maxBytes) {
          throw const FormatException('Manifest exceeds size limit');
        }
        final bytes = file.readAsBytesSync();
        if (bytes.length > maxBytes) {
          throw const FormatException('Manifest exceeds size limit');
        }
        final document = jsonDecode(_sdkJson(utf8.decode(bytes)));
        if (document is! Map || document['Classes'] is! List) {
          throw const FormatException('Missing VST3 class list');
        }
        final classes = document['Classes'] as List;
        if (classes.length > 1024) {
          throw const FormatException('Excessive VST3 class count');
        }
        final compatibility = <String, Set<String>>{};
        if (document['Compatibility'] case final List entries) {
          if (entries.length > 1024) {
            throw const FormatException('Excessive VST3 compatibility count');
          }
          for (final entry in entries) {
            if (entry is! Map ||
                entry['New'] is! String ||
                entry['Old'] is! List) {
              continue;
            }
            final current = normalizeClassId(entry['New'] as String);
            if (current == null) continue;
            final old = entry['Old'] as List;
            if (old.length > 1024) {
              throw const FormatException('Excessive compatibility aliases');
            }
            for (final value in old) {
              final id = value is String ? normalizeClassId(value) : null;
              if (id != null) {
                compatibility.putIfAbsent(current, () => {}).add(id);
              }
            }
          }
        }
        final result = <LocalPluginCandidate>[];
        final seenIds = <String>{};
        for (final entry in classes) {
          if (entry is! Map || entry['Category'] != 'Audio Module Class') {
            continue;
          }
          final id = entry['CID'] is String
              ? normalizeClassId(entry['CID'] as String)
              : null;
          final name = _text(entry['Name']);
          if (id == null || name == null || !seenIds.add(id)) {
            warnings.add('Invalid or duplicate processor class in $path');
            continue;
          }
          final factory = document['Factory Info'];
          result.add(
            LocalPluginCandidate(
              path: bundle,
              name: name,
              format: 'VST3',
              identifier: id,
              vendor:
                  _text(entry['Vendor']) ??
                  (factory is Map ? _text(factory['Vendor']) : null),
              version: _text(entry['Version']) ?? _text(document['Version']),
              manifestPath: path,
              compatibleIdentifiers: List.unmodifiable(
                compatibility[id] ?? const <String>{},
              ),
            ),
          );
        }
        if (result.isEmpty) {
          warnings.add('No readable VST3 processor class in $path');
        }
        return result;
      } on FileSystemException {
        warnings.add('Cannot read VST3 manifest: $path');
      } on FormatException catch (error) {
        warnings.add('Unverified VST3 manifest $path: ${error.message}');
      }
    }
    return const [];
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty && value.length <= 1024
      ? value.trim()
      : null;

  static bool _hasLinkedAncestor(String path) {
    var current = p.normalize(p.absolute(path));
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
      final parent = p.dirname(current);
      if (parent == current) return false;
      current = parent;
    }
  }

  /// The SDK emits JSON strings plus comments and trailing commas. Handle
  /// those without corrupting URLs or quoted text. Other JSON5 extensions
  /// (single-quoted strings, unquoted keys, Infinity) are rejected explicitly
  /// by jsonDecode and produce a manifest warning instead of guessed IDs.
  static String _sdkJson(String text) {
    final cleaned = StringBuffer();
    var inString = false;
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        cleaned.write(char);
        if (char == '\\' && i + 1 < text.length) {
          cleaned.write(text[++i]);
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
        cleaned.write(char);
      } else if (char == '/' && i + 1 < text.length && text[i + 1] == '/') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        cleaned.write('\n');
      } else if (char == '/' && i + 1 < text.length && text[i + 1] == '*') {
        final end = text.indexOf('*/', i + 2);
        if (end < 0) {
          throw const FormatException('Unterminated manifest comment');
        }
        cleaned.write(' ');
        i = end + 1;
      } else {
        if (char == '{' || char == '[') {
          if (++depth > 64) {
            throw const FormatException('Manifest nesting exceeds limit');
          }
        } else if (char == '}' || char == ']') {
          depth--;
        }
        cleaned.write(char);
      }
    }
    final source = cleaned.toString();
    final output = StringBuffer();
    inString = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (inString) {
        output.write(char);
        if (char == '\\' && i + 1 < source.length) {
          output.write(source[++i]);
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
        output.write(char);
      } else if (char == ',') {
        var next = i + 1;
        while (next < source.length && source[next].trim().isEmpty) {
          next++;
        }
        if (next >= source.length ||
            (source[next] != '}' && source[next] != ']')) {
          output.write(char);
        }
      } else {
        output.write(char);
      }
    }
    return output.toString();
  }
}
