import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/plugin_compatibility_registry.dart';

void main() {
  const vst2 = PluginIdentity(format: 'VST2', identifier: '1234', vendor: 'Test');
  const vst3 = PluginIdentity(format: 'VST3', identifier: 'ABCD', vendor: 'Test');
  test('empty registry cannot invent replacement compatibility', () {
    expect(const PluginCompatibilityRegistry().candidates(vst2), isEmpty);
  });
  test('only a DAW-tested mapping can claim verified preset preservation', () {
    const documented = PluginMigrationProfile(
      id: 'documented', source: vst2, target: vst3,
      strategy: PluginMigrationStrategy.nativeStateImport,
      evidence: PluginMigrationEvidence.documented,
    );
    const verified = PluginMigrationProfile(
      id: 'verified', source: vst2, target: vst3,
      strategy: PluginMigrationStrategy.parameterTranslation,
      evidence: PluginMigrationEvidence.testedInDaw,
      parameterMapping: {'attack': 'attackTime'},
    );
    const registry = PluginCompatibilityRegistry([documented, verified]);
    expect(registry.candidates(vst2), hasLength(2));
    expect(registry.candidates(const PluginIdentity(
      format: 'VST2', identifier: '1234', vendor: 'Test')), hasLength(2));
    expect(documented.presetPreservationVerified, isFalse);
    expect(verified.presetPreservationVerified, isTrue);
  });
}
