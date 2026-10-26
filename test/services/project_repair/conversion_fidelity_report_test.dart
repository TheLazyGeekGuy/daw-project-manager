import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/conversion_fidelity_report.dart';

void main() {
  test('detects dropped duplicate-named tracks and plugin instances', () {
    final report = ConversionFidelityReport.compare(
      const ConversionSemanticSnapshot(
        format: 'reaper',
        trackNames: ['Keys', 'Keys'],
        pluginCount: 2,
      ),
      const ConversionSemanticSnapshot(
        format: 'dawproject',
        trackNames: ['Keys'],
        pluginCount: 1,
      ),
    );
    expect(report['status'], 'differences_detected');
    expect(report['lossless'], false);
  });
  test('matching inventory never certifies native state or audio fidelity', () {
    final report = ConversionFidelityReport.compare(
      const ConversionSemanticSnapshot(
        format: 'reaper',
        trackNames: ['A'],
        pluginCount: 0,
      ),
      const ConversionSemanticSnapshot(
        format: 'dawproject',
        trackNames: ['A'],
        pluginCount: 0,
      ),
    );
    expect(report['status'], 'no_difference_in_observed_fields');
    expect(report['unverified_dimensions'], contains('audio_render'));
    expect(report['lossless'], false);
  });
  test('unknown dimensions stay unverified', () {
    final report = ConversionFidelityReport.compare(
      const ConversionSemanticSnapshot(format: 'midi'),
      const ConversionSemanticSnapshot(
        format: 'dawproject',
        trackNames: [],
        pluginCount: 0,
      ),
    );
    expect(
      (report['checks'] as List).every((c) => c['status'] == 'unverified'),
      true,
    );
  });
}
