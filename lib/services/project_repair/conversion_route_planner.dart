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
    this.requiresManualStep = false,
    this.sourceUrl,
  });

  final String id;
  final String sourceFormat;
  final String targetFormat;
  final ConversionEvidence evidence;
  final Set<String> lossRisks;
  final bool requiresExternalTool;
  final String? requiredPlatform;
  final bool requiresManualStep;
  final String? sourceUrl;
}

class ConversionRoute {
  const ConversionRoute(this.adapters);
  final List<ConversionAdapter> adapters;

  String get source => adapters.first.sourceFormat;
  String get target => adapters.last.targetFormat;
  bool get verified =>
      adapters.every((a) => a.evidence == ConversionEvidence.verified);
  bool get requiresManualStep => adapters.any((a) => a.requiresManualStep);
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
    bool includeManualSteps = true,
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
        if (!includeExperimental &&
            adapter.evidence == ConversionEvidence.experimental) {
          continue;
        }
        if (!includeManualSteps && adapter.requiresManualStep) continue;
        if (adapter.requiredPlatform != null &&
            adapter.requiredPlatform != platform) {
          continue;
        }
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
          r.adapters
                  .where((e) => e.evidence != ConversionEvidence.verified)
                  .length *
              5 +
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
    id: 'alltomidi-native',
    sourceFormat: 'cubase-all',
    targetFormat: 'midi',
    evidence: ConversionEvidence.experimental,
    requiresExternalTool: false,
    sourceUrl: 'https://github.com/OnjLouis/AllToMidi',
    lossRisks: {
      'audio',
      'plugin-state',
      'mixer-settings',
      'native-automation',
      'mid-song-tempo',
      'sysex',
      'unknown-all-variants',
    },
  ),
  ConversionAdapter(
    id: 'atari2cubase-all-to-dawproject',
    sourceFormat: 'cubase-all',
    targetFormat: 'dawproject',
    evidence: ConversionEvidence.experimental,
    requiresManualStep: true,
    sourceUrl:
        'https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292',
    lossRisks: {
      'atari-only-primary-scope',
      'pc-format-experimental',
      'plugin-state',
      'routing',
      'automation',
      'unverified-proprietary-decoder',
    },
  ),
  ConversionAdapter(
    id: 'atari2cubase-arr-to-dawproject',
    sourceFormat: 'cubase-arr',
    targetFormat: 'dawproject',
    evidence: ConversionEvidence.experimental,
    requiresManualStep: true,
    sourceUrl:
        'https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292',
    lossRisks: {
      'atari-only-primary-scope',
      'pc-format-experimental',
      'plugin-state',
      'routing',
      'automation',
      'unverified-proprietary-decoder',
    },
  ),
  ConversionAdapter(
    id: 'steinberg-legacy-all-import',
    sourceFormat: 'cubase-all',
    targetFormat: 'cubase',
    evidence: ConversionEvidence.documented,
    lossRisks: {'vst-effects', 'vst-instruments', 'mixer-settings'},
    requiresManualStep: true,
    sourceUrl:
        'https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format',
  ),
  ConversionAdapter(
    id: 'steinberg-legacy-arr-import',
    sourceFormat: 'cubase-arr',
    targetFormat: 'cubase',
    evidence: ConversionEvidence.documented,
    lossRisks: {'vst-effects', 'vst-instruments', 'mixer-settings'},
    requiresManualStep: true,
    sourceUrl:
        'https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format',
  ),
  ConversionAdapter(
    id: 'projectconverter-reaper-to-dawproject',
    sourceFormat: 'reaper',
    targetFormat: 'dawproject',
    evidence: ConversionEvidence.documented,
    lossRisks: {
      'plugin-parameter-automation',
      'complex-routing',
      'continuous-tempo',
      'au-plugins',
    },
    requiresManualStep: true,
    sourceUrl: 'https://github.com/git-moss/ProjectConverter',
  ),
  ConversionAdapter(
    id: 'projectconverter-dawproject-to-reaper',
    sourceFormat: 'dawproject',
    targetFormat: 'reaper',
    evidence: ConversionEvidence.documented,
    lossRisks: {
      'plugin-parameter-automation',
      'complex-routing',
      'continuous-tempo',
      'au-plugins',
    },
    requiresManualStep: true,
    sourceUrl: 'https://github.com/git-moss/ProjectConverter',
  ),
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
    id: 'dawvert-ableton-to-flstudio',
    sourceFormat: 'ableton',
    targetFormat: 'flstudio',
    evidence: ConversionEvidence.experimental,
    lossRisks: {'native-devices', 'automation', 'plugin-state'},
  ),
  ConversionAdapter(
    id: 'dawvert-flstudio-to-ableton',
    sourceFormat: 'flstudio',
    targetFormat: 'ableton',
    evidence: ConversionEvidence.experimental,
    lossRisks: {'native-devices', 'automation', 'plugin-state'},
  ),
];
