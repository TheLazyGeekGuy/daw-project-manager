import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/services/project_repair/dawvert_conversion_service.dart';

/// Explicit, opt-in conversion into a new managed output workspace.
///
/// This is not a CPR writer and does not certify VST states or render parity.
const _usage = '''
Usage:
  dart run bin/project_repair_convert.dart \\
    --input /path/session.rpp \\
    --target dawproject \\
    --script /path/DawVert/dawvert_cmd.py \\
    --python /absolute/path/to/python3 \\
    --accept-loss [--output-root /path/exports]

Targets: reaper, dawproject, flstudio, ableton, lmms, midi.
No network downloads, original overwrites, or native DAW fidelity claims.
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
      '--input', '--target', '--script', '--python', '--output-root',
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
      values[arg] = arguments[++index];
    }
    for (final required in ['--input', '--target', '--script', '--python']) {
      if (!values.containsKey(required)) {
        throw FormatException('Missing argument: $required');
      }
    }
    final result = await DawVertConversionService().convert(
      original: File(values['--input']!),
      dawvertScript: File(values['--script']!),
      pythonExecutable: values['--python']!,
      targetFormat: values['--target']!,
      acknowledgeFidelityRisks: acknowledged,
      outputRoot: values['--output-root'] == null
          ? null : Directory(values['--output-root']!),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
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
