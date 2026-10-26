import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'conversion_fidelity_report.dart';
import 'conversion_route_planner.dart';
import 'dawvert_conversion_service.dart';
import 'verified_project_backup.dart';

/// Executes only explicit DawVert routes, retaining every intermediate file.
/// Manual Steinberg/ProjectConverter and research-only adapters cannot execute.
class ConversionPipeline {
  ConversionPipeline({DawVertConversionService? service})
    : _service = service ?? DawVertConversionService();
  final DawVertConversionService _service;

  Future<Map<String, Object?>> execute({
    required File original,
    required ConversionRoute route,
    required File dawvertScript,
    required String pythonExecutable,
    required bool acknowledgeFidelityRisks,
    Directory? outputRoot,
    Duration timeoutPerStep = const Duration(minutes: 5),
  }) async {
    if (!acknowledgeFidelityRisks ||
        route.adapters.isEmpty ||
        route.adapters.length > 3) {
      throw const FormatException(
        'An explicit accepted route of one to three steps is required',
      );
    }
    var expected = route.source;
    for (final adapter in route.adapters) {
      if (adapter.requiresManualStep ||
          adapter.id !=
              'dawvert-${adapter.sourceFormat}-to-${adapter.targetFormat}' ||
          adapter.sourceFormat != expected ||
          adapter.sourceFormat == adapter.targetFormat ||
          !DawVertConversionService.supportedFormats.containsKey(
            adapter.sourceFormat,
          ) ||
          !DawVertConversionService.supportedFormats.containsKey(
            adapter.targetFormat,
          )) {
        throw const FormatException(
          'Route requires a manual or unsupported adapter',
        );
      }
      expected = adapter.targetFormat;
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
      original.absolute.path,
    );
    final before = await ConversionSemanticSnapshot.read(
      original,
      route.source,
    );
    final sourceHash = (await sha256.bind(original.openRead()).first)
        .toString();
    final root =
        (outputRoot ??
                Directory(
                  p.join(
                    original.parent.absolute.path,
                    '.project-repair-exports',
                  ),
                ))
            .absolute;
    if (p.split(root.path).contains('.project-repair-backups')) {
      throw const FileSystemException(
        'Pipeline output cannot be inside managed backups',
      );
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(root.path);
    await root.create(recursive: true);
    final run = await root.createTemp('dpm-pipeline-');
    final reportFile = File(p.join(run.path, 'pipeline-report.json'));
    final results = <DawVertConversionResult>[];
    var current = original;
    try {
      for (final adapter in route.adapters) {
        final result = await _service.convert(
          original: current,
          dawvertScript: dawvertScript,
          pythonExecutable: pythonExecutable,
          targetFormat: adapter.targetFormat,
          acknowledgeFidelityRisks: true,
          outputRoot: Directory(p.join(run.path, 'step-${results.length + 1}')),
          timeout: timeoutPerStep,
        );
        if (result.sourceFormat != adapter.sourceFormat) {
          throw const FormatException(
            'Actual project format disagrees with conversion route',
          );
        }
        results.add(result);
        current = File(result.outputPath);
      }
      if ((await sha256.bind(original.openRead()).first).toString() !=
          sourceHash) {
        throw const FileSystemException(
          'Pipeline source changed during conversion',
        );
      }
      final after = await ConversionSemanticSnapshot.read(
        current,
        route.target,
      );
      final report = <String, Object?>{
        'status': 'generated_unverified',
        'source': original.absolute.path,
        'source_sha256': sourceHash,
        'output': current.path,
        'report': reportFile.path,
        'steps': [for (final result in results) result.toJson()],
        'loss_risks': route.lossRisks.toList()..sort(),
        'semantic_fidelity': ConversionFidelityReport.compare(before, after),
        'native_daw_reopen_verified': false,
        'audio_fidelity_verified': false,
      };
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      return report;
    } catch (error) {
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'status': 'failed',
          'detail': error.toString(),
          'source': original.absolute.path,
          'source_sha256': sourceHash,
          'completed_steps': [for (final result in results) result.toJson()],
          'intermediates_retained': true,
          'native_daw_reopen_verified': false,
        }),
        flush: true,
      );
      rethrow;
    }
  }
}
