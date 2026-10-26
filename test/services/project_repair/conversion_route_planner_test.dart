import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/conversion_route_planner.dart';

void main() {
  test(
    'legacy and ProjectConverter routes are visible but cannot auto-run',
    () {
      const planner = ConversionRoutePlanner(candidateConversionAdapters);
      final routes = planner.findRoutes('cubase-all', 'cubase');
      expect(routes.single.requiresManualStep, true);
      expect(routes.single.lossRisks, contains('mixer-settings'));
      expect(
        planner.findRoutes('cubase-all', 'cubase', includeManualSteps: false),
        isEmpty,
      );
      expect(
        planner.findRoutes(
          'cubase-arr',
          'dawproject',
          includeExperimental: false,
        ),
        isEmpty,
      );
      final experimental = planner.findRoutes(
        'cubase-arr',
        'dawproject',
        includeExperimental: true,
      );
      expect(
        experimental.any(
          (r) =>
              r.adapters.first.id == 'atari2cubase-arr-to-dawproject' &&
              r.requiresManualStep,
        ),
        true,
      );
    },
  );
  final planner = ConversionRoutePlanner(const [
    ConversionAdapter(
      id: 'direct',
      sourceFormat: 'a',
      targetFormat: 'c',
      evidence: ConversionEvidence.verified,
      lossRisks: {},
    ),
    ConversionAdapter(
      id: 'first',
      sourceFormat: 'a',
      targetFormat: 'b',
      evidence: ConversionEvidence.documented,
      lossRisks: {'preset'},
    ),
    ConversionAdapter(
      id: 'second',
      sourceFormat: 'b',
      targetFormat: 'c',
      evidence: ConversionEvidence.documented,
      lossRisks: {},
    ),
    ConversionAdapter(
      id: 'reverse',
      sourceFormat: 'b',
      targetFormat: 'a',
      evidence: ConversionEvidence.documented,
      lossRisks: {},
    ),
  ]);

  test('prefers verified direct route', () {
    final routes = planner.findRoutes('a', 'c');
    expect(routes.length, 2);
    expect(routes.first.adapters.first.id, 'direct');
    expect(routes.last.lossRisks, contains('preset'));
  });

  test('avoids cycles and same-format route', () {
    expect(planner.findRoutes('a', 'a'), isEmpty);
    expect(planner.findRoutes('a', 'c', maxHops: 1).length, 1);
  });

  test('experimental paths must be explicitly enabled', () {
    const p = ConversionRoutePlanner(candidateConversionAdapters);
    expect(p.findRoutes('cubase', 'reaper'), isEmpty);
    expect(
      p
          .findRoutes('cubase', 'reaper', includeExperimental: true)
          .single
          .verified,
      isFalse,
    );
  });

  test('filters platform-restricted adapters', () {
    const p = ConversionRoutePlanner([
      ConversionAdapter(
        id: 'mac-only',
        sourceFormat: 'a',
        targetFormat: 'b',
        evidence: ConversionEvidence.documented,
        lossRisks: {},
        requiredPlatform: 'macos',
      ),
    ]);
    expect(p.findRoutes('a', 'b', platform: 'windows'), isEmpty);
    expect(p.findRoutes('a', 'b', platform: 'macos'), hasLength(1));
  });
}
