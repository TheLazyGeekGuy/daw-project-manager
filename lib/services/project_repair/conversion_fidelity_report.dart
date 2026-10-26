import 'dart:convert';
import 'dart:io';

import 'dawproject_archive_inspector.dart';
import 'midi_file_validator.dart';

/// A deliberately small read-only inventory for detecting obvious losses.
/// It must never be used as a session serialization format.
class ConversionSemanticSnapshot {
  const ConversionSemanticSnapshot({
    required this.format,
    this.trackNames,
    this.pluginCount,
    this.noteCount,
    this.dawProject,
    this.midi,
  });
  final String format;
  final List<String>? trackNames;
  final int? pluginCount, noteCount;
  final DawProjectSummary? dawProject;
  final MidiFileSummary? midi;

  static Future<ConversionSemanticSnapshot> read(
    File file,
    String format,
  ) async {
    if (format == 'midi') {
      final midi = MidiFileValidator.inspect(await file.readAsBytes());
      return ConversionSemanticSnapshot(
        format: format,
        noteCount: midi.noteCount,
        midi: midi,
      );
    }
    if (format == 'dawproject') {
      final summary = DawProjectArchiveInspector.inspect(
        await file.readAsBytes(),
      );
      return ConversionSemanticSnapshot(
        format: format,
        trackNames: [
          for (final t in summary.tracks)
            if (!t.isMaster) t.name,
        ],
        pluginCount: summary.plugins.length,
        noteCount: summary.noteCount,
        dawProject: summary,
      );
    }
    if (format != 'reaper') return ConversionSemanticSnapshot(format: format);
    final tracks = <String>[];
    final stack = <String>[];
    var plugins = 0;
    var notes = 0;
    var currentTrack = -1;
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final value = line.trim();
      if (value.startsWith('<')) {
        final tag = value.substring(1).split(RegExp(r'\s+')).first;
        stack.add(tag);
        if (stack.length > 256) {
          throw const FormatException('Excessive REAPER nesting');
        }
        if (tag == 'TRACK') {
          currentTrack = tracks.length;
          tracks.add('');
        }
        if (const {'VST', 'CLAP', 'AU'}.contains(tag)) plugins++;
      } else if (value == '>') {
        if (stack.isEmpty) {
          throw const FormatException('Unbalanced REAPER block');
        }
        if (stack.removeLast() == 'TRACK') currentTrack = -1;
      } else if (currentTrack >= 0 &&
          stack.lastOrNull == 'TRACK' &&
          value.startsWith('NAME ')) {
        var name = value.substring(5).trim();
        if (name.length >= 2 &&
            const {'"', "'", '`'}.contains(name[0]) &&
            name.endsWith(name[0])) {
          name = name.substring(1, name.length - 1);
        }
        tracks[currentTrack] = name;
      } else if (stack.lastOrNull == 'SOURCE') {
        final event = RegExp(
          r'^[Ee]\s+\d+\s+([0-9a-fA-F]{2})\s+[0-9a-fA-F]{2}\s+([0-9a-fA-F]{2})(?:\s|$)',
        ).firstMatch(value);
        if (event != null &&
            (int.parse(event.group(1)!, radix: 16) & 0xf0) == 0x90 &&
            int.parse(event.group(2)!, radix: 16) != 0) {
          notes++;
        }
      }
    }
    if (stack.isNotEmpty) throw const FormatException('Unclosed REAPER block');
    return ConversionSemanticSnapshot(
      format: format,
      trackNames: List.unmodifiable(tracks),
      pluginCount: plugins,
      // Inline note-on count is evidence only; external MIDI is not decoded.
      noteCount: notes,
    );
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'track_names': trackNames,
    'plugin_count': pluginCount,
    'inline_note_count': noteCount,
    if (dawProject != null) 'dawproject': dawProject!.toJson(),
    if (midi != null) 'midi': midi!.toJson(),
  };
}

class ConversionFidelityReport {
  static Map<String, Object?> compare(
    ConversionSemanticSnapshot source,
    ConversionSemanticSnapshot output,
  ) {
    final checks = <Map<String, Object?>>[];
    void compareValue(String dimension, Object? before, Object? after) {
      checks.add({
        'dimension': dimension,
        'source': before,
        'output': after,
        'status': before == null || after == null
            ? 'unverified'
            : before == after
            ? 'matched_observation'
            : 'changed',
      });
    }

    compareValue(
      'track_count',
      source.trackNames?.length,
      output.trackNames?.length,
    );
    compareValue(
      'plugin_instance_count',
      source.pluginCount,
      output.pluginCount,
    );
    final beforeNames = source.trackNames == null
        ? null
        : ([...source.trackNames!]..sort());
    final afterNames = output.trackNames == null
        ? null
        : ([...output.trackNames!]..sort());
    compareValue(
      'track_name_multiset',
      beforeNames == null ? null : jsonEncode(beforeNames),
      afterNames == null ? null : jsonEncode(afterNames),
    );
    // Comparing only counts never establishes matching notes, states or timing.
    return {
      'scope': 'read_only_inventory_observations',
      'status': checks.any((c) => c['status'] == 'changed')
          ? 'differences_detected'
          : 'no_difference_in_observed_fields',
      'source': source.toJson(),
      'output': output.toJson(),
      'checks': checks,
      'unverified_dimensions': const [
        'note_positions_and_durations',
        'tempo_map',
        'time_units',
        'plugin_state_equivalence',
        'automation',
        'routing',
        'sidechain',
        'media_playback',
        'native_daw_reopen',
        'audio_render',
      ],
      'lossless': false,
    };
  }
}
