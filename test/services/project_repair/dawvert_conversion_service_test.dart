import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/dawvert_conversion_service.dart';
import '../../helpers/dawproject_fixture.dart';

void main() {
  late Directory root;
  late File original;
  late File python;
  late File script;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm-dawvert-test-');
    original = File('${root.path}/song.rpp');
    await original.writeAsString('<REAPER_PROJECT 0.1\n>\n');
    python = File('${root.path}/python3');
    await python.writeAsString('synthetic test runtime');
    script = File('${root.path}/dawvert_cmd.py');
    await script.writeAsString('synthetic test script');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('refuses conversion without explicit user risk acceptance', () async {
    final service = DawVertConversionService(
      runner: (_, __, ___, ____) async => throw StateError('Must not run'),
    );
    expect(
      () => service.convert(
        original: original,
        dawvertScript: script,
        pythonExecutable: python.path,
        targetFormat: 'midi',
        acknowledgeFidelityRisks: false,
      ),
      throwsFormatException,
    );
  });

  test('converts only a staged copy and retains an immutable backup', () async {
    String? inputPath;
    final service = DawVertConversionService(
      runner: (_, arguments, __, ___) async {
        final input = arguments[arguments.indexOf('-i') + 1];
        final output = arguments[arguments.indexOf('-o') + 1];
        inputPath = input;
        expect(await File(input).readAsString(), await original.readAsString());
        await File(output).writeAsBytes([
          0x4d,
          0x54,
          0x68,
          0x64,
          0,
          0,
          0,
          6,
          0,
          1,
          0,
          1,
          1,
          0xe0,
          0x4d,
          0x54,
          0x72,
          0x6b,
          0,
          0,
          0,
          4,
          0,
          0xff,
          0x2f,
          0,
        ]);
        return const DawVertProcessOutcome(
          exitCode: 0,
          stdout: 'Converted',
          stderr: '',
        );
      },
    );
    final oldBytes = await original.readAsBytes();
    final result = await service.convert(
      original: original,
      dawvertScript: script,
      pythonExecutable: python.path,
      targetFormat: 'midi',
      acknowledgeFidelityRisks: true,
    );
    expect(inputPath, isNot(original.path));
    expect(await original.readAsBytes(), oldBytes);
    expect(await File(result.backupPath).readAsBytes(), oldBytes);
    expect(result.outputPath, contains('.project-repair-exports'));
    final manifest =
        jsonDecode(await File(result.reportPath).readAsString())
            as Map<String, dynamic>;
    expect(manifest['status'], 'generated_unverified');
    expect(manifest['native_daw_reopen_verified'], false);
    expect(manifest['plugin_state_preservation_verified'], false);
  });

  test('malformed output stays quarantined with failed report', () async {
    final service = DawVertConversionService(
      runner: (_, arguments, __, ___) async {
        final output = arguments[arguments.indexOf('-o') + 1];
        await File(output).writeAsString('not a midi project');
        return const DawVertProcessOutcome(exitCode: 0, stdout: '', stderr: '');
      },
    );
    await expectLater(
      service.convert(
        original: original,
        dawvertScript: script,
        pythonExecutable: python.path,
        targetFormat: 'midi',
        acknowledgeFidelityRisks: true,
      ),
      throwsFormatException,
    );
    expect(await original.readAsString(), '<REAPER_PROJECT 0.1\n>\n');
    final exports = Directory('${root.path}/.project-repair-exports');
    final runs = await exports.list().toList();
    expect(runs, hasLength(1));
    final report = File('${runs.single.path}/conversion-report.json');
    final result = jsonDecode(await report.readAsString());
    expect(result['status'], 'failed');
  });

  test('does not advertise unsupported native Cubase conversion', () async {
    final fakeCpr = File('${root.path}/song.cpr');
    await fakeCpr.writeAsBytes('RIFFxxxxNUND'.codeUnits);
    final service = DawVertConversionService(
      runner: (_, __, ___, ____) async => throw StateError('Must not run'),
    );
    await expectLater(
      service.convert(
        original: fakeCpr,
        dawvertScript: script,
        pythonExecutable: python.path,
        targetFormat: 'reaper',
        acknowledgeFidelityRisks: true,
      ),
      throwsFormatException,
    );
  });

  test('rejects a disguised ZIP output that is not a DAWproject', () async {
    final service = DawVertConversionService(
      runner: (_, args, __, ___) async {
        await File(
          args[args.indexOf('-o') + 1],
        ).writeAsBytes([80, 75, 3, 4, 1, 2]);
        return const DawVertProcessOutcome(exitCode: 0, stdout: '', stderr: '');
      },
    );
    await expectLater(
      service.convert(
        original: original,
        dawvertScript: script,
        pythonExecutable: python.path,
        targetFormat: 'dawproject',
        acknowledgeFidelityRisks: true,
      ),
      throwsFormatException,
    );
  });

  test('stages converter data and reports semantic differences', () async {
    final data = File('${root.path}/data_main/reference.txt');
    await data.parent.create();
    await data.writeAsString('fixture');
    await original.writeAsString(
      '<REAPER_PROJECT 0.1\n<TRACK\nNAME "Retain me"\n>\n>\n',
    );
    final service = DawVertConversionService(
      runner: (_, args, cwd, __) async {
        expect(
          await File('$cwd/data_main/reference.txt').readAsString(),
          'fixture',
        );
        expect(args.first, '$cwd/dawvert_cmd.py');
        expect(cwd, isNot(root.path));
        await File(
          args[args.indexOf('-o') + 1],
        ).writeAsBytes(dawProjectFixture());
        return const DawVertProcessOutcome(exitCode: 0, stdout: '', stderr: '');
      },
    );
    final result = await service.convert(
      original: original,
      dawvertScript: script,
      pythonExecutable: python.path,
      targetFormat: 'dawproject',
      acknowledgeFidelityRisks: true,
    );
    final report = jsonDecode(await File(result.reportPath).readAsString());
    expect(report['semantic_fidelity']['status'], 'differences_detected');
    expect(report['converter_runtime']['entry_point_sha256'], hasLength(64));
  });

  test(
    'rejects external DAWproject media before invoking the converter',
    () async {
      final source = File('${root.path}/external.dawproject');
      await source.writeAsBytes(
        dawProjectFixture(
          project:
              '<Project version="1.0"><Application name="Fixture"/><Audio><File path="/secret.wav" external="true"/></Audio></Project>',
        ),
      );
      final service = DawVertConversionService(
        runner: (_, __, ___, ____) async => throw StateError('Must not run'),
      );
      await expectLater(
        service.convert(
          original: source,
          dawvertScript: script,
          pythonExecutable: python.path,
          targetFormat: 'reaper',
          acknowledgeFidelityRisks: true,
        ),
        throwsFormatException,
      );
    },
  );
}
