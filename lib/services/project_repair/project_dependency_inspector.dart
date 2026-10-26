import 'dart:io';
import 'dart:typed_data';

import '../daw_parsers/cubase_project_parser.dart';
import '../daw_parsers/reaper_project_parser.dart';
import 'project_format_registry.dart';

/// Machine-readable dependency report. A name is not a stable plug-in UID.
class ProjectDependencyReport {
  final String path;
  final String formatId;
  final List<String> pluginNames;
  final int? trackCount;
  final List<String> limitations;

  const ProjectDependencyReport({
    required this.path,
    required this.formatId,
    required this.pluginNames,
    required this.trackCount,
    required this.limitations,
  });

  Map<String, Object?> toJson() => {
    'schema_version': '1.0',
    'source_path': path,
    'format_id': formatId,
    'plugin_names': pluginNames,
    'track_count': trackCount,
    'limitations': limitations,
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
        final parser = CubaseProjectParser(bytes);
        final tracks = parser.readTracks();
        return ProjectDependencyReport(
          path: path,
          formatId: descriptor.id,
          pluginNames: List.unmodifiable(parser.readPluginNames()),
          trackCount: tracks.length,
          limitations: const [
            'Plug-in UIDs and saved states are not verified by this report.',
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
