import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/services/project_repair/cubase_lossless_container.dart';
import 'package:daw_project_manager/services/project_repair/cubase_preservation_service.dart';

const _usage = '''
Usage: dart run bin/project_repair_cpr.dart [--preserve] [--output-root DIR] FILE...

The default verifies unchanged CPR container reconstruction in memory.
--preserve creates a verified backup and a new workspace with an unchanged CPR,
opaque chunk files and a provenance report. Original projects are never edited.
Native Cubase reopening and plug-in/preset migration are not performed.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(_usage);
    exitCode = arguments.isEmpty ? 64 : 0;
    return;
  }
  var preserve = false;
  Directory? outputRoot;
  final inputs = <String>[];
  try {
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '--preserve') {
        preserve = true;
      } else if (argument == '--output-root') {
        if (++i >= arguments.length || arguments[i].startsWith('--')) {
          throw const FormatException('--output-root requires a directory');
        }
        outputRoot = Directory(arguments[i]);
      } else if (argument.startsWith('--')) {
        throw FormatException('Unknown argument: $argument');
      } else {
        inputs.add(argument);
      }
    }
    if (inputs.isEmpty || (outputRoot != null && !preserve)) {
      throw const FormatException(
        'Supply project files; output-root requires --preserve',
      );
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final results = <Map<String, Object?>>[];
  for (final path in inputs) {
    try {
      final file = File(path);
      if (await file.length() > 256 * 1024 * 1024) {
        throw const FormatException('CPR exceeds the roundtrip size limit');
      }
      final report = preserve
          ? await CubasePreservationService().preserve(
              file,
              outputRoot: outputRoot,
            )
          : CubaseLosslessContainer.parse(
              await file.readAsBytes(),
            ).verificationReport();
      results.add({
        'status': 'ok',
        'source_path': file.absolute.path,
        ...report,
      });
    } catch (error) {
      exitCode = 1;
      results.add({
        'status': 'error',
        'source_path': path,
        'message': '$error',
      });
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'schema_version': 1, 'results': results}),
  );
}
