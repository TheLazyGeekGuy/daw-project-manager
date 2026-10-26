import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/music_communication.dart';
void main() {
  test('reports missing promotion coverage and unknown evidence', () {
    const plan = PromotionPlan(
      assets: [PromotionAsset(id: 'video1', collectionId: 'album',
        trackId: 'song1', type: PromotionAssetType.video, path: 'teaser.mp4')],
      posts: [PromotionPost(id: 'post', collectionId: 'album', platform: 'YouTube',
        state: PromotionState.planned, assetIds: ['video1'])]);
    expect(plan.validate(), isEmpty);
    expect(plan.tracksWithoutPromotion('album', ['song1', 'song2']), {'song2'});
  });
}
