import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/services/project_repair/dawvert_conversion_service.dart';
import 'package:daw_project_manager/services/project_repair/conversion_pipeline.dart';
import 'package:daw_project_manager/services/project_repair/conversion_route_planner.dart';
import 'package:daw_project_manager/services/project_repair/project_format_registry.dart';
import 'package:daw_project_manager/services/project_repair/legacy_all_conversion_service.dart';

/// Explicit, opt-in conversion into a new managed output workspace.
///
/// This is not a CPR writer and does not certify VST states or render parity.
const _usage = '''
Usage:
  dart run bin/project_repair_convert.dart \\
    --engine native-all --input /path/legacy.ALL --target midi --accept-loss

  dart run bin/project_repair_convert.dart \\
    --input /path/session.rpp \\
    --target dawproject \\
    --script /path/DawVert/dawvert_cmd.py \\
    --python /absolute/path/to/python3 \\
    --accept-loss [--output-root /path/exports] [--via dawproject] \\
    [--timeout-seconds 300]

Targets: reaper, dawproject, flstudio, ableton, lmms, midi.
At most three steps. --via is a comma-separated list of intermediate formats.
Manual legacy Cubase / ProjectConverter routes cannot execute through this CLI.
Trusted locally installed tools only; no native DAW fidelity certification.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.isEmpty) {
    stdout.writeln(_usage);
    exitCode = arguments.isEmpty ? 64 : 0;
    return;
  }

  try {
    final values = <String, String>{};
    var acknowledged = false;
    const accepted = {
      '--input',
      '--target',
      '--script',
      '--python',
      '--output-root',
      '--via',
      '--timeout-seconds',
      '--engine',
    };
    for (var index = 0; index < arguments.length; index++) {
      final arg = arguments[index];
      if (arg == '--accept-loss') {
        acknowledged = true;
        continue;
      }
      if (!accepted.contains(arg) ||
          index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('Invalid or missing command-line argument: $arg');
      }
      if (values.containsKey(arg)) {
        throw FormatException('Duplicate argument: $arg');
      }
      values[arg] = arguments[++index];
    }
    for (final required in ['--input', '--target']) {
      if (!values.containsKey(required)) {
        throw FormatException('Missing argument: $required');
      }
    }
    final engine = values['--engine'] ?? 'dawvert';
    if (engine == 'native-all') {
      if (values['--target'] != 'midi' ||
          values.containsKey('--via') ||
          values.containsKey('--script') ||
          values.containsKey('--python')) {
        throw const FormatException(
          'native-all accepts only .ALL to MIDI, without an external script or intermediate route',
        );
      }
      final result = await LegacyAllConversionService.convert(
        original: File(values['--input']!),
        acknowledgeFidelityRisks: acknowledged,
        outputRoot: values['--output-root'] == null
            ? null
            : Directory(values['--output-root']!),
      );
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
      return;
    }
    if (engine != 'dawvert') {
      throw const FormatException('Unknown converter engine');
    }
    for (final required in ['--script', '--python']) {
      if (!values.containsKey(required)) {
        throw FormatException('Missing argument: $required');
      }
    }
    final timeoutSeconds = int.tryParse(values['--timeout-seconds'] ?? '300');
    if (timeoutSeconds == null || timeoutSeconds < 1 || timeoutSeconds > 3600) {
      throw const FormatException('Timeout must be between 1 and 3600 seconds');
    }
    final intermediates = values.containsKey('--via')
        ? values['--via']!.split(',')
        : <String>[];
    if (intermediates.any((value) => value.isEmpty) ||
        intermediates.length > 2) {
      throw const FormatException(
        'Select zero to two nonempty intermediate formats',
      );
    }
    Map<String, Object?> resultJson;
    if (intermediates.isEmpty) {
      final result = await DawVertConversionService().convert(
        original: File(values['--input']!),
        dawvertScript: File(values['--script']!),
        pythonExecutable: values['--python']!,
        targetFormat: values['--target']!,
        acknowledgeFidelityRisks: acknowledged,
        outputRoot: values['--output-root'] == null
            ? null
            : Directory(values['--output-root']!),
        timeout: Duration(seconds: timeoutSeconds),
      );
      resultJson = result.toJson();
    } else {
      final source = ProjectFormatRegistry.byExtension(values['--input']!);
      if (source == null) throw const FormatException('Unknown source format');
      var previous = source.id;
      final adapters = <ConversionAdapter>[];
      for (final target in [...intermediates, values['--target']!]) {
        adapters.add(
          ConversionAdapter(
            id: 'dawvert-$previous-to-$target',
            sourceFormat: previous,
            targetFormat: target,
            evidence: ConversionEvidence.experimental,
            lossRisks: {'plugin-state', 'automation', 'routing', 'timing'},
          ),
        );
        previous = target;
      }
      resultJson = await ConversionPipeline().execute(
        original: File(values['--input']!),
        route: ConversionRoute(adapters),
        dawvertScript: File(values['--script']!),
        pythonExecutable: values['--python']!,
        acknowledgeFidelityRisks: acknowledged,
        outputRoot: values['--output-root'] == null
            ? null
            : Directory(values['--output-root']!),
        timeoutPerStep: Duration(seconds: timeoutSeconds),
      );
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(resultJson));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('I/O failure: ${error.message}');
    exitCode = 1;
  } on ProcessException catch (error) {
    stderr.writeln('External converter failed: ${error.message}');
    exitCode = 1;
  } on TimeoutException catch (error) {
    stderr.writeln('Conversion time limit exceeded: $error');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Conversion failed: ${error.runtimeType}');
    exitCode = 1;
  }
}
