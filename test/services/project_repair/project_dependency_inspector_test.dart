import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/project_dependency_inspector.dart';
import 'package:daw_project_manager/services/project_repair/cubase_structural_probe.dart';
import '../../helpers/dawproject_fixture.dart';

void main() {
  test('unsupported files fail closed', () {
    expect(
      () => ProjectDependencyInspector.inspectBytes(
        'broken.cpr',
        Uint8List.fromList('RIFFxxxxWAVE'.codeUnits),
      ),
      throwsFormatException,
    );
  });

  test(
    'recognized but unimplemented format reports unknown, not empty dependencies',
    () {
      final result = ProjectDependencyInspector.inspectBytes(
        'session.song',
        Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
      );
      expect(result.formatId, 'studioone');
      expect(result.trackCount, isNull);
      expect(result.limitations.first, contains('not implemented'));
      expect(result.toJson()['plugin_loadability'], 'untested');
      expect(result.toJson()['original_modified'], isFalse);
    },
  );

  test(
    'legacy songs have a manual lossy import guide and no invented dependencies',
    () {
      final report = ProjectDependencyInspector.inspectBytes(
        'archive.ALL',
        Uint8List(4),
      );
      expect(report.formatId, 'cubase-all');
      expect(
        report.legacyConversionGuide?['automatic_conversion_supported'],
        false,
      );
      expect(
        report.legacyConversionGuide?['documented_losses'],
        contains('VST instruments'),
      );
      expect(report.trackCount, isNull);
      expect(report.pluginNames, isEmpty);
    },
  );

  test(
    'CPR serialized occurrences are preserved without duplicate name requests',
    () {
      const report = ProjectDependencyReport(
        path: 'session.cpr',
        formatId: 'cubase',
        pluginNames: ['Synth', 'Unknown'],
        trackCount: 2,
        limitations: [],
        pluginUidEvidence: [
          CubasePluginUidEvidence(
            name: 'Synth',
            uid: '0123456789ABCDEF0123456789ABCDEF',
            occurrences: 12,
            internalDevice: false,
          ),
        ],
      );
      expect(report.dependencyRequests, hasLength(2));
      expect(report.dependencyRequests.first.occurrences, 12);
      expect(report.dependencyRequests.first.source, 'cubase_serialized_guid');
      expect(report.toJson()['dependency_requests'], hasLength(2));
    },
  );

  test('REAPER plug-in names decode UTF-8', () {
    const source =
        '<REAPER_PROJECT 0.1 7.0 1\n<TRACK\n<FXCHAIN\n'
        '<VST "VST3: Synthé (Test)" synth.vst3 0 "" 0<1>\n>\n>\n>\n>\n';
    final report = ProjectDependencyInspector.inspectBytes(
      'utf8.rpp',
      Uint8List.fromList(utf8.encode(source)),
    );
    expect(report.pluginNames, contains('Synthé'));
  });

  test('DAWproject exposes per-instance IDs and unresolved references', () {
    final report = ProjectDependencyInspector.inspectBytes(
      'session.dawproject',
      dawProjectFixture(
        project:
            '<Project version="1.0"><Application name="Synthetic" version="1"/>'
            '<Structure><Track id="t1" name="Synth"><Channel id="c1" role="regular">'
            '<Devices><Vst3Plugin id="p1" deviceName="Synth" deviceID="0123456789ABCDEF0123456789ABCDEF">'
            '<State path="plugins/missing.vstpreset"/></Vst3Plugin></Devices></Channel></Track></Structure>'
            '</Project>',
      ),
    );
    expect(report.trackCount, 1);
    expect(report.dawProjectSummary?.missingReferences, [
      'plugins/missing.vstpreset',
    ]);
    expect(
      report.dependencyRequests.single.identifier,
      '0123456789ABCDEF0123456789ABCDEF',
    );
    expect(
      report.dependencyRequests.single.source,
      'dawproject_plugin_declaration',
    );
    expect(report.limitations.any((entry) => entry.contains('missing')), true);
  });
}
