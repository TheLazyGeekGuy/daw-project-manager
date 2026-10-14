import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/models/sample_reference.dart';

void main() {
  test('isSampleAudioFile knows the audio extensions, in any case', () {
    expect(isSampleAudioFile('kick.wav'), isTrue);
    expect(isSampleAudioFile(r'C:\x\Pad.AIFF'), isTrue);
    expect(isSampleAudioFile('loop.flac'), isTrue);
    expect(isSampleAudioFile('break.rx2'), isTrue);
    expect(isSampleAudioFile('kick.wav.asd'), isFalse);
    expect(isSampleAudioFile('lead.mid'), isFalse);
    expect(isSampleAudioFile('noextension'), isFalse);
  });

  test('sampleFileNameOf reads either separator', () {
    expect(sampleFileNameOf(r'C:\Samples\Kick\k.wav'), 'k.wav');
    expect(sampleFileNameOf('/Users/me/k.wav'), 'k.wav');
    expect(sampleFileNameOf('k.wav'), 'k.wav');
  });

  group('looksLikeRecording', () {
    const cubase = r'_\d{2,3}(-\d{2})?';

    test("a track's name plus the take suffix is a recording", () {
      expect(looksLikeRecording('Vocals_03.wav', ['Vocals'], cubase), isTrue);
      expect(looksLikeRecording('Audio 01_01-02.wav', ['Audio 01'], cubase),
          isTrue);
      expect(looksLikeRecording('vocals_03.WAV', ['Vocals'], cubase), isTrue);
    });

    test('an imported file named like the track is not', () {
      expect(looksLikeRecording('Kick 2013.wav', ['Kick'], cubase), isFalse);
      expect(looksLikeRecording('Kick_01.wav', ['Bass'], cubase), isFalse);
      expect(looksLikeRecording('Vocals_03.wav', [''], cubase), isFalse);
    });

    test('track names with regex characters are taken literally', () {
      expect(looksLikeRecording('Lead (2)_01.wav', ['Lead (2)'], cubase),
          isTrue);
      expect(looksLikeRecording('Lead 2_01.wav', ['Lead (2)'], cubase),
          isFalse);
    });
  });
}
