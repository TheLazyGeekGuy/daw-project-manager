import 'dart:convert';
import 'dart:io';

import 'package:daw_project_manager/services/project_repair/project_dependency_inspector.dart';
import 'package:daw_project_manager/services/project_repair/project_format_registry.dart';

/// Read-only diagnostic command. It never changes the source project.
///
/// Usage: dart run bin/project_repair_inspect.dart `project-file` [more-files]
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln('Usage: dart run bin/project_repair_inspect.dart <project-file> [more-files]');
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }

  final reports = <Map<String, Object?>>[];
  var failed = false;
  for (final name in args) {
    try {
      final report = await ProjectDependencyInspector.inspect(File(name));
      reports.add({'status': 'ok', ...report.toJson()});
    } on FileSystemException catch (error) {
      failed = true;
      reports.add({'status': 'error', 'path': name, 'message': error.message});
    } on FormatException catch (error) {
      failed = true;
      reports.add({'status': 'error', 'path': name, 'message': error.message});
    } catch (error) {
      failed = true;
      reports.add({'status': 'error', 'path': name, 'message': 'Inspection failed'});
      stderr.writeln('Unexpected error inspecting $name: ${error.runtimeType}');
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'schema_version': '1.0',
    'operation': 'read-only-inspection',
    'results': reports,
    'supported_formats': ProjectFormatRegistry.formats.map((f) => f.id).toList(),
  }));
  if (failed) exitCode = 1;
}
