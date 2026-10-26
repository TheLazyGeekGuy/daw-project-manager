import 'local_plugin_inventory.dart';

/// A name-based candidate match is a hint, never a verified plug-in identity.
enum PluginDependencyStatus {
  candidatePresent,
  notFoundByName,
  unknown,
}

class PluginDependencyMatch {
  const PluginDependencyMatch({
    required this.requestedName,
    required this.status,
    this.candidates = const [],
  });
  final String requestedName;
  final PluginDependencyStatus status;
  final List<LocalPluginCandidate> candidates;

  Map<String, Object?> toJson() => {
    'requested_name': requestedName,
    'status': status.name,
    'identity_verified': false,
    'loadability': 'untested',
    'candidates': candidates.map((p) => p.toJson()).toList(),
  };
}

class PluginDependencyMatcher {
  const PluginDependencyMatcher();

  String _normalize(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\((?:x64|64-bit|x86|32-bit)\)\s*$'), '')
      .replaceAll(RegExp(r'[_ -]+(?:x64|x86|64bit|32bit)$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<PluginDependencyMatch> compare(
    Iterable<String> projectPluginNames,
    Iterable<LocalPluginCandidate> localPlugins,
  ) {
    final inventory = <String, List<LocalPluginCandidate>>{};
    for (final local in localPlugins) {
      final key = _normalize(local.name);
      if (key.isNotEmpty) {
        inventory.putIfAbsent(key, () => []).add(local);
      }
    }

    return List.unmodifiable(projectPluginNames.map((name) {
      final key = _normalize(name);
      if (key.isEmpty) {
        return PluginDependencyMatch(
          requestedName: name,
          status: PluginDependencyStatus.unknown,
        );
      }
      final matches = inventory[key] ?? const <LocalPluginCandidate>[];
      return PluginDependencyMatch(
        requestedName: name,
        status: matches.isEmpty
            ? PluginDependencyStatus.notFoundByName
            : PluginDependencyStatus.candidatePresent,
        candidates: List.unmodifiable(matches),
      );
    }));
  }
}
