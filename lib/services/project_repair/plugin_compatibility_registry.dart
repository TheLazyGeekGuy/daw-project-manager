/// Typed, explicit compatibility evidence for optional plug-in migration.
///
/// Display-name similarity is never sufficient to claim preset compatibility.
enum PluginMigrationStrategy {
  nativeStateImport,
  parameterTranslation,
  approximateReplacement,
  none,
}

enum PluginMigrationEvidence { testedInDaw, documented, experimental }

class PluginIdentity {
  final String format;
  final String identifier;
  final String vendor;
  final String? version;

  const PluginIdentity({
    required this.format,
    required this.identifier,
    required this.vendor,
    this.version,
  });

  String get key => '${format.toLowerCase()}:${identifier.toLowerCase()}';
}

class PluginMigrationProfile {
  final String id;
  final PluginIdentity source;
  final PluginIdentity target;
  final PluginMigrationStrategy strategy;
  final PluginMigrationEvidence evidence;
  final Map<String, String> parameterMapping;
  final String notes;

  const PluginMigrationProfile({
    required this.id,
    required this.source,
    required this.target,
    required this.strategy,
    required this.evidence,
    this.parameterMapping = const {},
    this.notes = '',
  });

  bool get presetPreservationVerified =>
      evidence == PluginMigrationEvidence.testedInDaw &&
      (strategy == PluginMigrationStrategy.nativeStateImport ||
       strategy == PluginMigrationStrategy.parameterTranslation);
}

/// No migrations are registered by default: vendor compatibility and
/// parameter mappings require real version-specific evidence.
class PluginCompatibilityRegistry {
  final List<PluginMigrationProfile> profiles;
  const PluginCompatibilityRegistry([this.profiles = const []]);

  List<PluginMigrationProfile> candidates(PluginIdentity source) =>
      List.unmodifiable(profiles.where((p) => p.source.key == source.key));

  PluginMigrationProfile? findById(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}
