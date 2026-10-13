import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/models/sample_reference.dart';
import 'package:daw_project_manager/services/sample_pack/sample_classifier.dart';

void main() {
  final project = p.join(p.separator, 'music', 'Song Project');
  final library = p.join(p.separator, 'samples', 'Re-Twin');

  group('sampleOriginOf', () {
    SampleOrigin origin(List<String> under, String name,
            {String? root, SampleKind? kind, Duration? duration}) =>
        sampleOriginOf(
          path: p.joinAll([root ?? project, ...under, name]),
          projectDir: project,
          kind: kind,
          duration: duration,
        );

    test('outside the project folder is a library', () {
      expect(origin(['Kicks'], 'k.wav', root: library), SampleOrigin.library);
    });

    test('inside it, an imported copy', () {
      expect(origin(['Audio'], 'k.wav'), SampleOrigin.project);
      expect(origin([], 'k.wav'), SampleOrigin.project);
    });

    test('what the DAW says wins', () {
      expect(origin(['Audio'], 'v.wav', kind: SampleKind.recorded),
          SampleOrigin.recorded);
      expect(origin(['Audio'], 'v.wav', kind: SampleKind.processed),
          SampleOrigin.processed);
    });

    test('folders DAWs record and render into', () {
      expect(origin(['Recorded'], 'take.wav'), SampleOrigin.recorded);
      expect(origin(['Edits'], 'k.wav'), SampleOrigin.processed);
      expect(origin(['Freeze'], 'Synth.wav'), SampleOrigin.processed);
      expect(origin(['Samples', 'Processed', 'Consolidate'], 'x.wav'),
          SampleOrigin.processed);
      expect(origin(['Mixdown'], 'Song.wav'), SampleOrigin.processed);
    });

    test('names DAWs give rendered audio', () {
      expect(origin(['Audio'], 'Drums-glued.wav'), SampleOrigin.processed);
      expect(origin(['Audio'], 'Lead (Rendered).wav'), SampleOrigin.processed);
      expect(origin(['Audio'], 'Bass_bounce.wav'), SampleOrigin.processed);
    });

    test('a library folder named like a render folder is still a library',
        () {
      expect(origin(['Stems'], 'Bass.wav', root: library),
          SampleOrigin.library);
    });

    test('long audio is a stem or a full take, wherever it is', () {
      expect(
        origin(['Kicks'], 'k.wav',
            root: library, duration: const Duration(minutes: 3)),
        SampleOrigin.long,
      );
    });

    test('combinedOrigin: own audio anywhere wins, then a library', () {
      expect(
        combinedOrigin([SampleOrigin.project, SampleOrigin.recorded]),
        SampleOrigin.recorded,
      );
      expect(
        combinedOrigin([SampleOrigin.project, SampleOrigin.library]),
        SampleOrigin.library,
      );
      expect(combinedOrigin([SampleOrigin.project]), SampleOrigin.project);
      expect(SampleOrigin.long.isOwnAudio, isTrue);
      expect(SampleOrigin.library.isOwnAudio, isFalse);
    });
  });

  group('sampleCategoryOf', () {
    SampleCategory cat(String name,
            {List<String> folders = const [], double? seconds, String? dir}) =>
        sampleCategoryOf(
          p.joinAll([library, ...folders, name]),
          duration: seconds == null
              ? null
              : Duration(milliseconds: (seconds * 1000).round()),
          projectDir: dir,
        );

    test('from words in the name', () {
      expect(cat('eeth_drm_kick7.wav'), SampleCategory.kick);
      expect(cat('BassDrum 01.wav'), SampleCategory.kick);
      expect(cat('RIM15.wav'), SampleCategory.snare);
      expect(cat('Clap Basic.wav'), SampleCategory.clap);
      expect(cat('HIHAT233(CLSD).wav'), SampleCategory.hiHat);
      expect(cat('EHU_OpenHat_024.wav'), SampleCategory.hiHat);
      expect(cat('CRASH23.wav'), SampleCategory.cymbal);
      expect(cat('Prato 01.WAV'), SampleCategory.cymbal);
      expect(cat('SHAK49G21.wav'), SampleCategory.percussion);
      expect(cat('VVE2 Vocal FX 013.wav'), SampleCategory.vocal);
      expect(cat('upfilter 14.wav'), SampleCategory.fx);
      expect(cat('Sweep Con Crash.wav'), SampleCategory.fx);
      expect(cat('Psy Stab (47).wav'), SampleCategory.synth);
      expect(cat('Lezlie Piano.flac'), SampleCategory.keys);
      expect(cat('Hi String.flac'), SampleCategory.pad);
      expect(cat('Rolling Bassline.wav'), SampleCategory.bass);
      expect(cat('Atmosphere.wav'), SampleCategory.atmosphere);
    });

    test('from the folders a library keeps it in, closest first', () {
      expect(cat('RTW_Hit_3.wav', folders: ['RTW_DRUM_HITS', 'RTW_PERCS']),
          SampleCategory.percussion);
      expect(cat('Sound 04.wav', folders: ['Full On Bass']),
          SampleCategory.bass);
      expect(cat('Sound 04.wav', folders: ['Samples', 'Imported']),
          SampleCategory.other,
          reason: 'generic folders say nothing');
    });

    test("inside a project only its subfolders count, never the song's name",
        () {
      final song = p.join(library, 'MegaBeat - Save the Bass');
      expect(
        sampleCategoryOf(p.join(song, 'Sounds (82).wav'),
            duration: const Duration(seconds: 3), projectDir: song),
        SampleCategory.other,
      );
    });

    test('drum hits that say loop, or run long, are drum loops', () {
      expect(cat('RTW_145_Drums_9_Hats.wav', seconds: 6.6),
          SampleCategory.drumLoop);
      expect(cat('Clap Loop OK !.wav', seconds: 3), SampleCategory.drumLoop);
      expect(cat('Up snare vol.wav', seconds: 7), SampleCategory.drumLoop);
      expect(cat('Fill 140 BPM (41).wav', seconds: 3.4),
          SampleCategory.drumLoop);
      expect(cat('CRASH11.wav', seconds: 6), SampleCategory.cymbal,
          reason: 'a cymbal rings that long on its own');
    });

    test('a short hit from a "128BPM" kit is no loop', () {
      expect(cat('VDE2 128BPM Progressive Kick.wav', seconds: 0.5),
          SampleCategory.kick);
    });

    test('what the name does not say, the length does', () {
      expect(cat('Sounds (82).wav', seconds: 0.4), SampleCategory.oneShot);
      expect(cat('Sounds (82).wav', seconds: 8), SampleCategory.other);
      expect(cat('Sounds (82).wav'), SampleCategory.other);
      expect(cat('Clubby 128bpm.wav', seconds: 7.5), SampleCategory.loop);
    });
  });

  group('packFileName', () {
    test('kept when it already says what it is', () {
      expect(packFileName('eeth_drm_kick7.wav', SampleCategory.kick),
          'eeth_drm_kick7.wav');
      expect(packFileName('RIM15.wav', SampleCategory.snare), 'RIM15.wav');
      expect(packFileName('Clap Loop OK !.wav', SampleCategory.drumLoop),
          'Clap Loop OK !.wav');
    });

    test('given its category otherwise', () {
      expect(packFileName('VDUB2 Fill In 031.wav', SampleCategory.drumLoop),
          'Drum Loop - VDUB2 Fill In 031.wav');
      expect(packFileName('Sweeep Delirium.wav', SampleCategory.bass),
          'Bass - Sweeep Delirium.wav');
    });

    test('never after a category that only says what it is not', () {
      expect(packFileName('Sounds (82).wav', SampleCategory.oneShot),
          'Sounds (82).wav');
      expect(packFileName('x.wav', SampleCategory.other), 'x.wav');
    });

    test('characters a file name cannot hold become _', () {
      expect(packFileName('a:b?.wav', SampleCategory.other), 'a_b_.wav');
    });
  });
}
