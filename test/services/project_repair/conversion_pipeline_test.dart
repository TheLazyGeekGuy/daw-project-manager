import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/conversion_pipeline.dart';
import 'package:daw_project_manager/services/project_repair/conversion_route_planner.dart';
import 'package:daw_project_manager/services/project_repair/dawvert_conversion_service.dart';

import '../../helpers/dawproject_fixture.dart';

void main() {
  late Directory root;
  late File source, script, python;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm-pipeline-test-');
    source = File('${root.path}/source.rpp');
    await source.writeAsString('<REAPER_PROJECT 0.1\n>\n');
    script = File('${root.path}/dawvert_cmd.py');
    await script.writeAsString('fixture');
    python = File('${root.path}/python3');
    await python.writeAsString('fixture');
  });
  tearDown(() async => root.delete(recursive: true));
  const route = ConversionRoute([
    ConversionAdapter(
      id: 'dawvert-reaper-to-dawproject',
      sourceFormat: 'reaper',
      targetFormat: 'dawproject',
      evidence: ConversionEvidence.experimental,
      lossRisks: {'plugin-state'},
    ),
    ConversionAdapter(
      id: 'dawvert-dawproject-to-reaper',
      sourceFormat: 'dawproject',
      targetFormat: 'reaper',
      evidence: ConversionEvidence.experimental,
      lossRisks: {'routing'},
    ),
  ]);
  test('retains each hop and a cumulative report', () async {
    var calls = 0;
    final service = DawVertConversionService(
      runner: (_, args, __, ___) async {
        final output = File(args[args.indexOf('-o') + 1]);
        if (calls++ == 0) {
          await output.writeAsBytes(dawProjectFixture());
        } else {
          await output.writeAsString('<REAPER_PROJECT 0.1\n>\n');
        }
        return const DawVertProcessOutcome(exitCode: 0, stdout: '', stderr: '');
      },
    );
    final report = await ConversionPipeline(service: service).execute(
      original: source,
      route: route,
      dawvertScript: script,
      pythonExecutable: python.path,
      acknowledgeFidelityRisks: true,
    );
    expect(calls, 2);
    expect(report['steps'], hasLength(2));
    expect(report['loss_risks'], ['plugin-state', 'routing']);
    expect(report['native_daw_reopen_verified'], false);
    expect(
      jsonDecode(
        await File(report['report'] as String).readAsString(),
      )['status'],
      'generated_unverified',
    );
    expect(await source.readAsString(), '<REAPER_PROJECT 0.1\n>\n');
  });
  test('refuses manual routes without invoking external tools', () async {
    final manual = ConversionRoute([
      candidateConversionAdapters.firstWhere(
        (a) => a.id == 'steinberg-legacy-all-import',
      ),
    ]);
    await expectLater(
      ConversionPipeline().execute(
        original: source,
        route: manual,
        dawvertScript: script,
        pythonExecutable: python.path,
        acknowledgeFidelityRisks: true,
      ),
      throwsFormatException,
    );
  });
}
