import 'dart:io';
import 'dart:typed_data';

import '../daw_parsers/cubase_project_parser.dart';
import '../daw_parsers/reaper_project_parser.dart';
import 'project_format_registry.dart';
import 'cubase_structural_probe.dart';

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

  const ProjectDependencyReport({
    required this.path,
    required this.formatId,
    required this.pluginNames,
    required this.trackCount,
    required this.limitations,
    this.savedDawVersion,
    this.cubaseContainer,
    this.pluginUidEvidence = const [],
  });

  Map<String, Object?> toJson() => {
    'schema_version': '1.0',
    'source_path': path,
    'format_id': formatId,
    'plugin_names': pluginNames,
    'track_count': trackCount,
    'limitations': limitations,
    'saved_daw_version': savedDawVersion,
    if (cubaseContainer != null) 'container': cubaseContainer!.toJson(),
    'plugin_uid_evidence': [
      for (final plugin in pluginUidEvidence) plugin.toJson(),
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
    final bytes = await file.readAsBytes();
    return inspectBytes(file.path, bytes);
  }

  static ProjectDependencyReport inspectBytes(String path, Uint8List bytes) {
    final descriptor = ProjectFormatRegistry.detect(path, bytes);
    if (descriptor == null) {
      throw const FormatException('Unsupported format or invalid file signature');
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
      case 'reaper':
        final parser = ReaperProjectParser(String.fromCharCodes(bytes));
        final stats = parser.readStats(countMidiClips: false);
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: List.unmodifiable(stats.plugins),
          trackCount: stats.audioTracks + stats.midiTracks + stats.instrumentTracks + stats.busTracks + stats.folderTracks,
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
