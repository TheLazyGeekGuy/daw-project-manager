import 'package:audio_service/audio_service.dart' show MediaItem;

import '../models/music_project.dart';

/// What the Android media notification shows under the song when there is no
/// artist to name. The app's name, which is the same in every locale.
const kMediaNotificationFallbackArtist = 'DAW Project Manager';

/// The line under the song's name in the Android media notification: the
/// profile it belongs to, since a profile is an artist.
///
/// Never blank. An empty artist was drawn as "null" by Android's media
/// controls, under every song.
String mediaNotificationArtist(String? profileName) {
  final name = profileName?.trim() ?? '';
  return name.isEmpty ? kMediaNotificationFallbackArtist : name;
}

/// The [MediaItem] the phone player hands the Android media notification for
/// [project] playing [trackPath].
MediaItem mediaItemFor(
  MusicProject project,
  String trackPath, {
  required String? profileName,
  Uri? artUri,
}) =>
    MediaItem(
      id: trackPath,
      title: project.displayName,
      artist: mediaNotificationArtist(profileName),
      artUri: artUri,
    );
