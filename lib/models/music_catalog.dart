/// DAW-independent catalog. IDs, not display names, identify entities.
enum MusicCollectionType { album, ep, single, compilation, playlist }
enum MusicAssetRole { master, mix, preview, stem, artwork, lyrics, midi, document }
enum MusicAssetValidation { verified, missing, unverified }
class MusicArtist {
  const MusicArtist({required this.id, required this.name, this.sortName});
  final String id;
  final String name;
  final String? sortName;
}
class MusicCredit {
  const MusicCredit({required this.artistId, required this.role});
  final String artistId;
  final String role;
}
class MusicAsset {
  const MusicAsset({required this.id, required this.trackId, required this.path, required this.role,
    this.codec, this.parentAssetId, this.validation = MusicAssetValidation.unverified});
  final String id, trackId, path;
  final MusicAssetRole role;
  final String? codec, parentAssetId;
  final MusicAssetValidation validation;
}
class CatalogTrack {
  const CatalogTrack({required this.id, required this.title, this.projectId,
    this.credits = const [], this.isrc, this.workId, this.originId});
  final String id, title;
  final String? projectId, isrc, workId, originId;
  final List<MusicCredit> credits;
}
class MusicCollection {
  const MusicCollection({required this.id, required this.title, required this.type,
    this.trackIds = const [], this.credits = const [], this.upc});
  final String id, title;
  final MusicCollectionType type;
  final List<String> trackIds;
  final List<MusicCredit> credits;
  final String? upc;
}
class MusicCatalog {
  const MusicCatalog({this.artists = const [], this.tracks = const [],
    this.collections = const [], this.assets = const []});
  final List<MusicArtist> artists;
  final List<CatalogTrack> tracks;
  final List<MusicCollection> collections;
  final List<MusicAsset> assets;
  List<String> validate() {
    final problems = <String>[];
    final artistIds = artists.map((a) => a.id).toSet();
    final trackIds = tracks.map((t) => t.id).toSet();
    final assetIds = assets.map((a) => a.id).toSet();
    for (final track in tracks) {
      for (final credit in track.credits) {
        if (!artistIds.contains(credit.artistId)) problems.add('Unknown artist: ${credit.artistId}');
      }
    }
    for (final asset in assets) {
      if (!trackIds.contains(asset.trackId)) problems.add('Unknown asset track: ${asset.trackId}');
      if (asset.parentAssetId != null && !assetIds.contains(asset.parentAssetId)) {
        problems.add('Unknown parent asset: ${asset.parentAssetId}');
      }
    }
    for (final collection in collections) {
      for (final id in collection.trackIds) {
        if (!trackIds.contains(id)) problems.add('Unknown collection track: $id');
      }
    }
    return problems;
  }
  /// Only verified media can be preferred; masters win over previews.
  MusicAsset? preferredAudioFor(String trackId) {
    final matches = assets.where((a) => a.trackId == trackId &&
        a.validation == MusicAssetValidation.verified &&
        const {MusicAssetRole.master, MusicAssetRole.mix, MusicAssetRole.preview}.contains(a.role)).toList();
    if (matches.isEmpty) return null;
    int priority(MusicAsset a) => (a.role == MusicAssetRole.master ? 100 :
        a.role == MusicAssetRole.mix ? 50 : 0) +
        (const {'wav', 'flac', 'aiff', 'alac'}.contains(a.codec?.toLowerCase()) ? 20 : 0);
    matches.sort((a, b) => priority(b).compareTo(priority(a)));
    return matches.first;
  }
}
