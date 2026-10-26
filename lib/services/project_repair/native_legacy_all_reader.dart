import 'dart:typed_data';

import 'legacy_all_midi_decoder.dart' as canonical;

/// Compatibility preview for DPM's bounded, cross-platform Cubase ALL decoder.
///
/// Public preview types remain stable; parsing, skipped-part reporting and
/// format limits come from the same engine used for native MIDI recovery.
/// AllToMidi's MIT attribution is retained in third_party/alltomidi/LICENSE.txt
/// and docs/project-repair/third-party/AllToMidi-LICENSE.txt.
/// This does not decode ARR, audio, VST state, SysEx or the original mix.
class NativeLegacyAllReader {
  const NativeLegacyAllReader();

  static const maxInputBytes = canonical.LegacyAllMidiDecoder.maxInputBytes;
  static const maxNamedRecords = canonical.LegacyAllMidiDecoder.maxCandidates;
  static const maxMidiEvents = canonical.LegacyAllMidiDecoder.maxEvents;

  LegacyAllSong read(Uint8List data) {
    final decoded = canonical.LegacyAllMidiDecoder.decode(data);
    return LegacyAllSong(
      tracks: List.unmodifiable([
        for (final track in decoded.tracks)
          LegacyAllTrack(
            name: track.name,
            channel: track.channel,
            trackNumber: track.trackNumber,
            layout: track.layout,
            partCount: track.partCount,
            events: List.unmodifiable([
              for (final event in track.events)
                LegacyAllEvent(
                  tick: event.tick,
                  status: event.status,
                  data1: event.data1,
                  data2: event.data2,
                  duration: event.duration,
                ),
            ]),
          ),
      ]),
      microsecondsPerQuarter: decoded.initialTempoMicroseconds,
      signatures: List.unmodifiable([
        for (final signature in decoded.timeSignatures)
          LegacyAllTimeSignature(
            tick: signature.tick,
            numerator: signature.numerator,
            denominatorPower: signature.denominatorPower,
          ),
      ]),
      skippedParts: decoded.skippedParts,
      tempoDefaulted: decoded.tempoDefaulted,
      warnings: List.unmodifiable([
        'Experimental recovery from undocumented Cubase ALL layouts.',
        'Audio, VST instruments, effects, mixer settings and SysEx are not recovered.',
        'Mid-song tempo changes and newer time-signature variants may be incomplete.',
        'The result must be checked against the original in a compatible DAW.',
        if (decoded.skippedParts > 0)
          '${decoded.skippedParts} unrecognized MIDI parts were skipped.',
        if (decoded.tempoDefaulted)
          'The initial tempo was unrecognized; an 80 BPM fallback was used.',
      ]),
    );
  }
}

class LegacyAllEvent {
  const LegacyAllEvent({
    required this.tick,
    required this.status,
    required this.data1,
    required this.data2,
    this.duration = 0,
  });

  final int tick, status, data1, data2, duration;
}

class LegacyAllTrack {
  const LegacyAllTrack({
    required this.name,
    required this.channel,
    required this.trackNumber,
    required this.layout,
    required this.partCount,
    required this.events,
  });

  final String name, layout;
  final int channel, trackNumber, partCount;
  final List<LegacyAllEvent> events;

  int get noteCount => events
      .where(
        (event) =>
            (event.status & 0xf0) == 0x90 &&
            event.data2 > 0 &&
            event.duration > 0,
      )
      .length;
}

class LegacyAllTimeSignature {
  const LegacyAllTimeSignature({
    required this.tick,
    required this.numerator,
    required this.denominatorPower,
  });

  final int tick, numerator, denominatorPower;
}

class LegacyAllSong {
  const LegacyAllSong({
    required this.tracks,
    required this.microsecondsPerQuarter,
    required this.signatures,
    required this.warnings,
    this.skippedParts = 0,
    this.tempoDefaulted = false,
  });

  final List<LegacyAllTrack> tracks;
  final int microsecondsPerQuarter, skippedParts;
  final List<LegacyAllTimeSignature> signatures;
  final List<String> warnings;
  final bool tempoDefaulted;

  int get eventCount =>
      tracks.fold(0, (sum, track) => sum + track.events.length);
  int get noteCount => tracks.fold(0, (sum, track) => sum + track.noteCount);

  Map<String, Object?> toJson() => {
    'format': 'cubase-vst-all',
    'decoder': 'native-dart-experimental',
    'status': skippedParts > 0
        ? 'partial_recovery_unverified'
        : 'generated_unverified',
    'skipped_parts': skippedParts,
    'initial_tempo_defaulted': tempoDefaulted,
    'tracks': [
      for (final track in tracks)
        {
          'name': track.name,
          'midi_channel': track.channel,
          'track_number': track.trackNumber,
          'parts': track.partCount,
          'layout': track.layout,
          'midi_events': track.events.length,
          'notes': track.noteCount,
        },
    ],
    'total_midi_events': eventCount,
    'total_notes': noteCount,
    'initial_bpm': 60000000 / microsecondsPerQuarter,
    'time_signatures': [
      for (final signature in signatures)
        {
          'tick': signature.tick,
          'numerator': signature.numerator,
          'denominator': 1 << signature.denominatorPower,
        },
    ],
    'warnings': warnings,
    'verified_against_native_cubase': false,
    'vst_state_preserved': false,
  };
}
