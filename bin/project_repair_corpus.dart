import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/services/project_repair/'
    'project_dependency_inspector.dart';

/// Read-only metadata report for *locally extracted* Cubase demo projects.
///
/// DPM never downloads, distributes or changes Steinberg demo media. A
/// successful scan is not an application-level Cubase reopen or audio test.
///
/// dart run bin/project_repair_corpus.dart /path/to/extracted/demos
/// dart run bin/project_repair_corpus.dart /path/to/demos --output /tmp/report.json
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln('Usage: dart run bin/project_repair_corpus.dart '
        '<extracted-demo-root> [--output <report.json>]');
    exitCode = args.isEmpty ? 64 : 0;
    return;
  }
  if (args.length != 1 && args.length != 3) {
    stderr.writeln('Expected root and optional --output path');
    exitCode = 64;
    return;
  }
  final root = Directory(args.first);
  if (!await root.exists()) {
    stderr.writeln('Demo directory does not exist');
    exitCode = 64;
    return;
  }
  final output = args.length == 3 && args[1] == '--output'
      ? File(args[2]) : null;
  if (args.length == 3 && output == null) {
    stderr.writeln('Expected --output <report.json>');
    exitCode = 64;
    return;
  }
  if (output != null &&
      p.extension(output.path).toLowerCase() != '.json') {
    stderr.writeln('Only a new JSON report is permitted');
    exitCode = 64;
    return;
  }
  const maxEntries = 30000;
  const maxProjects = 300;
  final reports = <Map<String, Object?>>[];
  var visited = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (++visited > maxEntries || reports.length >= maxProjects) {
      stderr.writeln('Corpus scan truncated by conservative limits');
      break;
    }
    if (entity is! File ||
        p.extension(entity.path).toLowerCase() != '.cpr' ||
        entity.path.split(p.separator).any(
            (part) => const {
              '.project-repair-backups',
              '.project-repair-exports',
            }.contains(part))) {
      continue;
    }
    try {
      final hash = (await sha256.bind(entity.openRead()).first).toString();
      final inspected = await ProjectDependencyInspector.inspect(entity);
      reports.add({
        'source': entity.absolute.path,
        'size_bytes': await entity.length(),
        'sha256': hash,
        'saved_daw_version': inspected.savedDawVersion,
        'track_count': inspected.trackCount,
        'plugins': inspected.pluginNames,
        'plugin_uid_records': [
          for (final uid in inspected.pluginUidEvidence) uid.toJson(),
        ],
        'container_chunks': inspected.cubaseContainer?.chunks.length,
        'archive_blocks': inspected.cubaseContainer?.archiveCount,
        'status': 'read_only_metadata_parsed',
        'native_cubase_reopen_verified': false,
        'preset_automation_routing_fidelity_verified': false,
      });
    } catch (error) {
      reports.add({
        'source': entity.absolute.path,
        'status': 'inspection_failed',
        'error': error.runtimeType.toString(),
      });
    }
  }
  final body = const JsonEncoder.withIndent('  ').convert({
    'schema_version': '1.0',
    'operation': 'local-demo-corpus-inspection-only',
    'native_reopen_verified': false,
    'project_count': reports.length,
    'reports': reports,
  });
  if (output != null) {
    if (await output.exists()) {
      stderr.writeln('Refusing to overwrite an existing corpus report');
      exitCode = 73;
      return;
    }
    await output.parent.create(recursive: true);
    await output.writeAsString(body, flush: true);
    stdout.writeln('Report written: ${output.absolute.path}');
  } else {
    stdout.writeln(body);
  }
  if (reports.isEmpty || reports.any((r) => r['status'] == 'inspection_failed')) {
    exitCode = 1;
  }
}
