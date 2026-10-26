import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

import '../daw_parsers/cubase_project_parser.dart';
import '../daw_parsers/reaper_project_parser.dart';
import 'project_format_registry.dart';
import 'cubase_structural_probe.dart';
import 'plugin_dependency_matcher.dart';
import 'legacy_cubase_conversion.dart';
import 'dawproject_archive_inspector.dart';

/// Machine-readable dependency report. A name is not a stable plug-in UID.
class ProjectDependencyReport {
  final String path;
  final String formatId;
  final List<String> pluginNames;
  final int? trackCount;
  final List<String> limitations;
  final String? savedDawVersion;
  final CubaseContainerManifest? cubaseContainer;
  final List<CubasePluginUidEvidence> pluginUidEvidence;
  final Map<String, Object?>? legacyConversionGuide;
  final DawProjectSummary? dawProjectSummary;

  const ProjectDependencyReport({
    required this.path,
    required this.formatId,
    required this.pluginNames,
    required this.trackCount,
    required this.limitations,
    this.savedDawVersion,
    this.cubaseContainer,
    this.pluginUidEvidence = const [],
    this.legacyConversionGuide,
    this.dawProjectSummary,
  });

  /// Serialized UID records take precedence over display-name hints. These
  /// records may include cached/offline instances and are not active FX counts.
  List<PluginDependencyRequest> get dependencyRequests {
    final records = pluginUidEvidence
        .where((entry) => !entry.internalDevice)
        .toList();
    final declared =
        dawProjectSummary?.plugins ?? const <DawProjectPluginSummary>[];
    final named = {
      ...records.map((entry) => entry.name.toLowerCase()),
      ...declared.map((entry) => entry.name.toLowerCase()),
    };
    return List.unmodifiable([
      for (final entry in declared)
        PluginDependencyRequest(
          name: entry.name,
          identifier: entry.pluginId,
          format: entry.format,
          source: 'dawproject_plugin_declaration',
        ),
      for (final entry in records)
        PluginDependencyRequest(
          name: entry.name,
          identifier: entry.uid,
          source: 'cubase_serialized_guid',
          occurrences: entry.occurrences,
        ),
      for (final name in pluginNames)
        if (!named.contains(name.toLowerCase()))
          PluginDependencyRequest(name: name),
    ]);
  }

  Map<String, Object?> toJson() => {
    'schema_version': '1.1',
    'source_path': path,
    'format_id': formatId,
    'plugin_names': pluginNames,
    if (legacyConversionGuide != null)
      'legacy_conversion_guide': legacyConversionGuide,
    'track_count': trackCount,
    'limitations': limitations,
    'saved_daw_version': savedDawVersion,
    if (dawProjectSummary != null)
      'dawproject_structure': dawProjectSummary!.toJson(),
    if (cubaseContainer != null) 'container': cubaseContainer!.toJson(),
    'plugin_uid_evidence': [
      for (final plugin in pluginUidEvidence) plugin.toJson(),
    ],
    'dependency_requests': [
      for (final request in dependencyRequests) request.toJson(),
    ],
    'plugin_loadability': 'untested',
    'plugin_state_preservation': 'untested',
    'original_modified': false,
  };
}

/// Inspection-only adapter. It does not attempt binary CPR writes, migration,
/// load third-party plug-ins, or classify unknown plug-ins as missing.
class ProjectDependencyInspector {
  static Future<ProjectDependencyReport> inspect(File file) async {
    final length = await file.length();
    if (length > 256 * 1024 * 1024) {
      throw const FormatException('Project exceeds the inspection size limit');
    }
    final path = file.path;
    return Isolate.run(() => inspectBytes(path, File(path).readAsBytesSync()));
  }

  static ProjectDependencyReport inspectBytes(String path, Uint8List bytes) {
    if (bytes.length > 256 * 1024 * 1024) {
      throw const FormatException('Project exceeds the inspection size limit');
    }
    final descriptor = ProjectFormatRegistry.detect(path, bytes);
    if (descriptor == null) {
      throw const FormatException(
        'Unsupported format or invalid file signature',
      );
    }
    switch (descriptor.id) {
      case 'cubase':
      case 'nuendo':
        final container = CubaseContainerManifest.inspect(bytes);
        final uidEvidence = CubasePluginUidProbe.inspect(bytes);
        final parser = CubaseProjectParser(bytes);
        final tracks = parser.readTracks();
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          savedDawVersion: CubaseProjectParser.appVersion(bytes),
          cubaseContainer: container,
          pluginUidEvidence: uidEvidence,
          pluginNames: List.unmodifiable(parser.readPluginNames()),
          trackCount: tracks.length,
          limitations: const [
            'Serialized plug-in UIDs are read-only evidence, not verified vendor identities or state compatibility.',
            'The typed UID scan targets one known Cubase attribute layout; absence of a UID is inconclusive.',
            'The project may contain routing or plug-in information not decoded by the reader.',
            'Installed, disabled, missing, and loadable statuses have not been tested.',
          ],
        );
      case 'dawproject':
        final summary = DawProjectArchiveInspector.inspect(bytes);
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: List.unmodifiable(
            summary.plugins.map((entry) => entry.name),
          ),
          trackCount: summary.tracks.where((track) => !track.isMaster).length,
          dawProjectSummary: summary,
          limitations: [
            'DAWproject ZIP/XML structure is inspected; complete XSD validation and native DAW reopening are not verified.',
            'Plug-in IDs are declarations, not proof of installation, loadability or state compatibility.',
            if (summary.externalReferences.isNotEmpty)
              '${summary.externalReferences.length} external file references require resolution before portable conversion.',
            if (summary.missingReferences.isNotEmpty)
              '${summary.missingReferences.length} referenced assets/states are missing from the archive.',
            if (summary.duplicateIds.isNotEmpty)
              'Duplicate XML IDs make object relationships ambiguous.',
          ],
        );
      case 'cubase-all':
      case 'cubase-arr':
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: const [],
          trackCount: null,
          legacyConversionGuide: LegacyCubaseConversion.guideFor(path),
          limitations: const [
            'Legacy Cubase format identified by extension only; binary contents are not decoded.',
            'Manual SE 3/SL 3/SX 3 import preserves audio/MIDI parts but loses VST effects, instruments and mixer settings.',
            'A compatible existing legacy license and operating system are required.',
          ],
        );
      case 'reaper':
        final parser = ReaperProjectParser(
          utf8.decode(bytes, allowMalformed: true),
        );
        final stats = parser.readStats(countMidiClips: false);
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: List.unmodifiable(stats.plugins),
          trackCount:
              stats.audioTracks +
              stats.midiTracks +
              stats.instrumentTracks +
              stats.busTracks +
              stats.folderTracks,
          limitations: const [
            'Plug-in IDs, saved states and loadability are not verified.',
            'Track classification is inferred from project use.',
          ],
        );
      default:
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: const [],
          trackCount: null,
          limitations: const [
            'Detailed dependency extraction is not implemented for this format.',
            'An empty plug-in list does not mean the project has no plug-ins.',
          ],
        );
    }
  }
}
