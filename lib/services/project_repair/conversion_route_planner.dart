/// Capability declarations only. These do not imply a verified conversion.
enum ConversionEvidence { verified, documented, experimental }

class ConversionAdapter {
  const ConversionAdapter({
    required this.id,
    required this.sourceFormat,
    required this.targetFormat,
    required this.evidence,
    required this.lossRisks,
    this.requiresExternalTool = true,
    this.requiredPlatform,
  });

  final String id;
  final String sourceFormat;
  final String targetFormat;
  final ConversionEvidence evidence;
  final Set<String> lossRisks;
  final bool requiresExternalTool;
  final String? requiredPlatform;
}

class ConversionRoute {
  const ConversionRoute(this.adapters);
  final List<ConversionAdapter> adapters;

  String get source => adapters.first.sourceFormat;
  String get target => adapters.last.targetFormat;
  bool get verified => adapters.every((a) => a.evidence == ConversionEvidence.verified);
  Set<String> get lossRisks => {
    for (final adapter in adapters) ...adapter.lossRisks,
  };
}

/// Finds possible paths without executing any converter.
///
/// Paths are ranked conservatively: fewer unknowns/risks, then fewer hops.
/// A discovered path does not certify project or preset fidelity.
class ConversionRoutePlanner {
  const ConversionRoutePlanner(this.adapters);
  final List<ConversionAdapter> adapters;

  List<ConversionRoute> findRoutes(
    String source,
    String target, {
    int maxHops = 3,
    String? platform,
    bool includeExperimental = false,
  }) {
    if (source == target || maxHops < 1) {
      return const [];
    }
    final result = <ConversionRoute>[];

    void visit(String current, List<ConversionAdapter> path, Set<String> seen) {
      if (path.length >= maxHops) {
        return;
      }
      for (final adapter in adapters) {
        if (adapter.sourceFormat != current) {
          continue;
        }
        if (!includeExperimental && adapter.evidence == ConversionEvidence.experimental) {
          continue;
        }
        if (adapter.requiredPlatform != null &&
            adapter.requiredPlatform != platform) continue;
        if (seen.contains(adapter.targetFormat)) {
          continue;
        }
        final next = [...path, adapter];
        if (adapter.targetFormat == target) {
          result.add(ConversionRoute(next));
        } else {
          visit(adapter.targetFormat, next, {...seen, adapter.targetFormat});
        }
      }
    }

    visit(source, const [], {source});
    result.sort((a, b) {
      int risk(ConversionRoute r) =>
          r.lossRisks.length * 10 +
          r.adapters.where((e) => e.evidence != ConversionEvidence.verified).length * 5 +
          r.adapters.length;
      return risk(a).compareTo(risk(b));
    });
    return List.unmodifiable(result);
  }
}

/// Initial researched adapter catalogue. No adapter here is certified or
/// automatically downloaded or executed.
const candidateConversionAdapters = <ConversionAdapter>[
  ConversionAdapter(
    id: 'cpr2rpp',
    sourceFormat: 'cubase',
    targetFormat: 'reaper',
    evidence: ConversionEvidence.experimental,
    lossRisks: {'plugin-state', 'routing', 'automation'},
  ),
  ConversionAdapter(
    id: 'dawvert-reaper-to-dawproject',
    sourceFormat: 'reaper',
    targetFormat: 'dawproject',
    evidence: ConversionEvidence.documented,
    lossRisks: {'plugin-state', 'routing'},
  ),
  ConversionAdapter(
    id: 'dawvert-dawproject-to-reaper',
    sourceFormat: 'dawproject',
    targetFormat: 'reaper',
    evidence: ConversionEvidence.documented,
    lossRisks: {'plugin-state', 'routing'},
  ),
  ConversionAdapter(
    id: 'dawvert-ableton-to-flp',
    sourceFormat: 'ableton',
    targetFormat: 'flstudio',
    evidence: ConversionEvidence.experimental,
    lossRisks: {'native-devices', 'automation', 'plugin-state'},
  ),
  ConversionAdapter(
    id: 'dawvert-flp-to-ableton',
    sourceFormat: 'flstudio',
    targetFormat: 'ableton',
    evidence: ConversionEvidence.experimental,
    lossRisks: {'native-devices', 'automation', 'plugin-state'},
  ),
];
