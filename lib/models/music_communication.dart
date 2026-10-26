/// Promotional planning is local-first and provider-agnostic.
enum PromotionAssetType { video, image, teaser, pressKit, audioSnippet, text }
enum PromotionState { idea, planned, creating, ready, scheduled, published, cancelled, unknown }
class PromotionAsset {
  const PromotionAsset({required this.id, required this.collectionId, required this.type,
    required this.path, this.trackId});
  final String id, collectionId, path;
  final PromotionAssetType type;
  final String? trackId;
}
class PromotionPost {
  const PromotionPost({required this.id, required this.collectionId, required this.platform,
    required this.state, this.trackId, this.assetIds = const [],
    this.scheduledAt, this.publishedAt, this.url});
  final String id, collectionId, platform;
  final PromotionState state;
  final String? trackId, url;
  final List<String> assetIds;
  final DateTime? scheduledAt, publishedAt;
}
class PromotionPlan {
  const PromotionPlan({this.assets = const [], this.posts = const []});
  final List<PromotionAsset> assets;
  final List<PromotionPost> posts;
  List<String> validate() {
    final issues = <String>[];
    final assetIds = assets.map((e) => e.id).toSet();
    for (final post in posts) {
      for (final id in post.assetIds) {
        if (!assetIds.contains(id)) issues.add('Missing promotion asset: $id');
      }
      if (post.state == PromotionState.published && post.publishedAt == null) {
        issues.add('Published post lacks publication timestamp');
      }
    }
    return issues;
  }
  /// Coverage is an observation, not a generated campaign or automatic upload.
  Set<String> tracksWithoutPromotion(String collectionId, Iterable<String> trackIds) {
    final promoted = <String>{
      for (final asset in assets)
        if (asset.collectionId == collectionId && asset.trackId != null) asset.trackId!,
      for (final post in posts)
        if (post.collectionId == collectionId && post.trackId != null &&
            post.state != PromotionState.cancelled) post.trackId!,
    };
    return trackIds.where((id) => !promoted.contains(id)).toSet();
  }
}
