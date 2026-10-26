import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/legacy_cubase_conversion.dart';
import 'package:daw_project_manager/services/project_repair/project_format_registry.dart';

void main() {
  test('recognizes legacy extensions without pretending to decode them', () {
    expect(ProjectFormatRegistry.byExtension('1998.ALL')?.id, 'cubase-all');
    expect(
      ProjectFormatRegistry.byExtension('mix.ARR')?.inspectionSupported,
      isFalse,
    );
    final guide = LegacyCubaseConversion.guideFor('1998.ALL')!;
    expect(guide['automatic_conversion_supported'], isFalse);
    expect(guide['lossless'], isFalse);
    expect(guide['documented_losses'], contains('VST instruments'));
    expect(guide['execution'], 'manual-external-application');
  });

  test('does not route native CPR through the legacy importer', () {
    expect(LegacyCubaseConversion.guideFor('mix.cpr'), isNull);
  });
}
