import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/music_catalog.dart';
void main() {
  test('a playlist and album independently reference stable track IDs', () {
    const catalog = MusicCatalog(
      tracks: [CatalogTrack(id: '1', title: 'Same'), CatalogTrack(id: '2', title: 'Same')],
      collections: [MusicCollection(id: 'a', title: 'Album', type: MusicCollectionType.album,
        trackIds: ['1', '2']), MusicCollection(id: 'p', title: 'Playlist',
        type: MusicCollectionType.playlist, trackIds: ['2', '1'])],
    );
    expect(catalog.validate(), isEmpty);
    expect(catalog.collections.last.trackIds.first, '2');
  });
  test('verified WAV master is preferred to MP3 preview', () {
    const catalog = MusicCatalog(tracks: [CatalogTrack(id: '1', title: 'Track')],
      assets: [MusicAsset(id: 'm', trackId: '1', path: 'a.wav', codec: 'wav',
        role: MusicAssetRole.master, validation: MusicAssetValidation.verified),
        MusicAsset(id: 'p', trackId: '1', path: 'a.mp3', codec: 'mp3',
          role: MusicAssetRole.preview, validation: MusicAssetValidation.verified)]);
    expect(catalog.preferredAudioFor('1')?.id, 'm');
  });
}
