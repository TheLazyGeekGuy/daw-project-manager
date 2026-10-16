import 'package:daw_project_manager/utils/media_notification.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_factories.dart';

void main() {
  group('mediaNotificationArtist', () {
    test('is the profile name, since a profile is an artist', () {
      expect(mediaNotificationArtist('Audio Crawler'), 'Audio Crawler');
    });

    test('trims the profile name', () {
      expect(mediaNotificationArtist('  Audio Crawler '), 'Audio Crawler');
    });

    test('falls back to the app name when there is no profile name', () {
      // Regression: the artist used to be '', which Android's media controls
      // drew as "null" under every song.
      expect(mediaNotificationArtist(null), kMediaNotificationFallbackArtist);
      expect(mediaNotificationArtist(''), kMediaNotificationFallbackArtist);
      expect(mediaNotificationArtist('   '), kMediaNotificationFallbackArtist);
    });
  });

  group('mediaItemFor', () {
    final project = TestFactories.makeProject(
      filePath: '/music/Teardrop.cpr',
      fileName: 'Teardrop.cpr',
    );

    test('never hands the notification a blank artist', () {
      final item = mediaItemFor(project, '/music/Teardrop.wav',
          profileName: null);
      expect(item.artist, isNotNull);
      expect(item.artist!.trim(), isNotEmpty);
    });

    test('carries the song, the profile and the artwork', () {
      final art = Uri.file('/covers/teardrop.png');
      final item = mediaItemFor(project, '/music/Teardrop.wav',
          profileName: 'Audio Crawler', artUri: art);
      expect(item.id, '/music/Teardrop.wav');
      expect(item.title, project.displayName);
      expect(item.artist, 'Audio Crawler');
      expect(item.artUri, art);
    });
  });
}
