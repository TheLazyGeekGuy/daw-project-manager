import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/sample_pack/sample_classifier.dart';
import 'package:daw_project_manager/services/sample_pack/sample_naming.dart';

void main() {
  group('sampleTraitsOf', () {
    test('reads the tempo however it is written', () {
      expect(sampleTraitsOf('VVE2 Vocal Loops 128BPM 149').bpm, 128);
      expect(sampleTraitsOf('Fill 140 BPM (41)').bpm, 140);
      expect(sampleTraitsOf('RTW_145_bpm_Drums').bpm, 145);
      expect(sampleTraitsOf('Loop BPM 174').bpm, 174);
      expect(sampleTraitsOf('Pad 87.5bpm').bpm, 87.5);
      expect(sampleTraitsOf('Kick 2013').bpm, isNull);
      expect(sampleTraitsOf('Hit 999 BPM').bpm, isNull, reason: 'implausible');
    });

    test('reads a key with what kind it is', () {
      expect(sampleTraitsOf('FINAL LEAD Am').key, 'Am');
      expect(sampleTraitsOf('Key To the Universe F#m').key, 'F#m');
      expect(sampleTraitsOf('Arp Lead 02 D#_Cm').key, 'Cm');
      expect(sampleTraitsOf('Arp Lead 04 G Phrygian').key, 'G Phrygian');
      expect(sampleTraitsOf('Pad A minor').key, 'Am');
      expect(sampleTraitsOf('Stab Ebmaj').key, 'Eb');
      expect(sampleTraitsOf('Bass (Bbm) 03').key, 'Bbm');
    });

    test('a sharp or flat note on its own is a key', () {
      expect(sampleTraitsOf('Psy Fx F# (10)').key, 'F#');
      expect(sampleTraitsOf('Bass Eb').key, 'Eb');
    });

    test('words are not keys', () {
      expect(sampleTraitsOf('Hamond').key, isNull);
      expect(sampleTraitsOf('Emotional Pad').key, isNull);
      expect(sampleTraitsOf('Bass A 1').key, isNull, reason: 'a bare letter');
      expect(sampleTraitsOf('Dmitri Cmd').key, isNull);
      expect(sampleTraitsOf('KICK AM').key, isNull);
    });
  });

  test('cleanSampleName drops the tempo, key and leftovers', () {
    expect(cleanSampleName('gataka_time_to_change_kick'),
        'gataka time to change kick');
    expect(cleanSampleName('Fill 140 BPM (41)'), 'Fill (41)');
    expect(cleanSampleName('FINAL LEAD (Am)'), 'FINAL LEAD');
    expect(cleanSampleName('Rolling Bass - F#m - 145bpm'), 'Rolling Bass');
    expect(cleanSampleName('x' * 80).length, 60);
  });

  group('SampleNaming', () {
    test('category and number, then name, tempo and key', () {
      const naming = SampleNaming();
      expect(
        naming.fileName(
          category: SampleCategory.bass,
          number: 1,
          original: 'rolling_bassline 145bpm.wav',
          bpm: 145,
          key: 'F#m',
        ),
        'Bass 001 - rolling bassline - 145 BPM - F#m.wav',
      );
      expect(
        naming.fileName(
          category: SampleCategory.kick,
          number: 12,
          original: 'gataka_time_to_change_kick.wav',
        ),
        'Kick 012 - gataka time to change kick.wav',
        reason: 'nothing found, nothing added',
      );
    });

    test('parts can be left out, and a prefix put in front', () {
      const naming = SampleNaming(
        includeName: false,
        includeKey: false,
        prefix: 'AC',
      );
      expect(
        naming.fileName(
          category: SampleCategory.drumLoop,
          number: 3,
          original: 'Top Loop.flac',
          bpm: 140,
          key: 'Am',
        ),
        'AC Drum Loop 003 - 140 BPM.flac',
      );
    });

    test('a name that is only a tempo and key adds no empty part', () {
      expect(
        const SampleNaming().fileName(
          category: SampleCategory.loop,
          number: 1,
          original: '140 BPM Am.wav',
          bpm: 140,
          key: 'Am',
        ),
        'Loop 001 - 140 BPM - Am.wav',
      );
    });

    test('numbers carry on from the highest in the folder', () {
      const naming = SampleNaming(prefix: 'AC');
      expect(
        naming.nextNumber(SampleCategory.kick, [
          'AC Kick 002 - x.wav',
          'ac kick 010.wav',
          'Kick 050.wav', // another prefix: not this scheme's
          'kick by hand.wav',
          'AC Kick 0071x.wav',
        ]),
        11,
      );
      expect(const SampleNaming().nextNumber(SampleCategory.kick, []), 1);
    });

    test('round-trips through JSON; defaults to everything, no prefix', () {
      const naming = SampleNaming(includeBpm: false, prefix: 'AC');
      final back = SampleNaming.fromJson(naming.toJson());
      expect(back.includeName, isTrue);
      expect(back.includeBpm, isFalse);
      expect(back.includeKey, isTrue);
      expect(back.prefix, 'AC');
      final none = SampleNaming.fromJson(null);
      expect(none.includeBpm && none.includeKey && none.includeName, isTrue);
      expect(none.prefix, '');
    });
  });

  test('bpmFromLoopLength takes the project tempo only for whole bars', () {
    // 4 bars at 140 BPM: 4 * 240 / 140 s.
    final fourBars = Duration(microseconds: (4 * 240 / 140 * 1e6).round());
    expect(bpmFromLoopLength(fourBars, 140), 140);
    expect(bpmFromLoopLength(fourBars, 128), isNull);
    expect(
      bpmFromLoopLength(const Duration(milliseconds: 400), 140),
      isNull,
      reason: 'a one-shot has no tempo',
    );
    final threeBars = Duration(microseconds: (3 * 240 / 140 * 1e6).round());
    expect(bpmFromLoopLength(threeBars, 140), isNull);
  });

  test('formatBpm', () {
    expect(formatBpm(140), '140');
    expect(formatBpm(87.5), '87.5');
    expect(formatBpm(127.98), '128');
  });
}
