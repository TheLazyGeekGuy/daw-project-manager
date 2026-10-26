import 'local_plugin_inventory.dart';

/// None of these states establish loadability, licence or preset compatibility.
enum PluginDependencyStatus {
  identifierPresent,
  compatibilityCandidate,
  ambiguous,
  identifierNotFound,
  candidatePresent,
  notFoundByName,
  unknown,
}

/// One serialized dependency or one aggregate of equivalent CPR UID records.
/// An occurrence count is not necessarily a count of active plug-in instances.
class PluginDependencyRequest {
  const PluginDependencyRequest({
    required this.name,
    this.identifier,
    this.format,
    this.source = 'display_name',
    this.occurrences = 1,
  });

  final String name;
  final String? identifier;
  final String? format;
  final String source;
  final int occurrences;

  Map<String, Object?> toJson() => {
    'name': name,
    'identifier': identifier,
    'format': format,
    'source': source,
    'serialized_occurrences': occurrences,
  };
}

class PluginDependencyMatch {
  const PluginDependencyMatch({
    required this.requestedName,
    required this.status,
    this.requestedIdentifier,
    this.evidence = 'display_name',
    this.candidates = const [],
  });

  final String requestedName;
  final String? requestedIdentifier;
  final String evidence;
  final PluginDependencyStatus status;
  final List<LocalPluginCandidate> candidates;

  Map<String, Object?> toJson() => {
    'requested_name': requestedName,
    'requested_identifier': requestedIdentifier,
    'status': status.name,
    'match_evidence': evidence,
    'identity_verified': false,
    'loadability': 'untested',
    'license_status': 'unknown',
    'absence_is_conclusive': false,
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

  /// Compatibility API for reports which have names but no identifier evidence.
  List<PluginDependencyMatch> compare(
    Iterable<String> projectPluginNames,
    Iterable<LocalPluginCandidate> localPlugins,
  ) => compareRequests(
    projectPluginNames.map((name) => PluginDependencyRequest(name: name)),
    localPlugins,
  );

  List<PluginDependencyMatch> compareRequests(
    Iterable<PluginDependencyRequest> requests,
    Iterable<LocalPluginCandidate> localPlugins,
  ) {
    final locals = localPlugins.toList(growable: false);
    return List.unmodifiable(
      requests.map((request) {
        final name = _normalize(request.name);
        final normalizedId = request.identifier == null
            ? null
            : LocalPluginInventory.normalizeClassId(request.identifier!);
        bool compatibleFormat(LocalPluginCandidate plugin) =>
            request.format == null ||
            plugin.format.toLowerCase() == request.format!.toLowerCase();
        final eligible = locals.where(compatibleFormat).toList(growable: false);
        final names = name.isEmpty
            ? <LocalPluginCandidate>[]
            : eligible
                  .where((plugin) => _normalize(plugin.name) == name)
                  .toList();
        PluginDependencyMatch result(
          PluginDependencyStatus status,
          List<LocalPluginCandidate> candidates,
          String evidence,
        ) => PluginDependencyMatch(
          requestedName: request.name,
          requestedIdentifier: request.identifier,
          status: status,
          candidates: List.unmodifiable(candidates),
          evidence: evidence,
        );

        if (normalizedId != null) {
          final exact = eligible
              .where(
                (plugin) =>
                    plugin.identifier != null &&
                    LocalPluginInventory.normalizeClassId(plugin.identifier!) ==
                        normalizedId,
              )
              .toList();
          if (exact.isNotEmpty) {
            return result(
              exact.length == 1
                  ? PluginDependencyStatus.identifierPresent
                  : PluginDependencyStatus.ambiguous,
              exact,
              'declared_identifier',
            );
          }
          final replacements = eligible
              .where(
                (plugin) => plugin.compatibleIdentifiers.any(
                  (id) =>
                      LocalPluginInventory.normalizeClassId(id) == normalizedId,
                ),
              )
              .toList();
          if (replacements.isNotEmpty) {
            return result(
              PluginDependencyStatus.compatibilityCandidate,
              replacements,
              'manifest_compatibility_declaration',
            );
          }
          // A same-name binary with a different CID must not be reported as the
          // requested plug-in. Return it only as evidence for manual diagnosis.
          return result(
            PluginDependencyStatus.identifierNotFound,
            names,
            'identifier_absent_from_scanned_manifests',
          );
        }
        if (request.identifier != null) {
          return result(
            PluginDependencyStatus.unknown,
            names,
            'unsupported_identifier_encoding',
          );
        }
        if (name.isEmpty) {
          return result(
            PluginDependencyStatus.unknown,
            const [],
            'no_identity',
          );
        }
        return result(
          names.isEmpty
              ? PluginDependencyStatus.notFoundByName
              : names.length == 1
              ? PluginDependencyStatus.candidatePresent
              : PluginDependencyStatus.ambiguous,
          names,
          'display_name',
        );
      }),
    );
  }
}
