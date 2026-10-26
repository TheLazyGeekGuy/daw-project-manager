import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/models/music_rights_distribution.dart';
void main() {
  test('rights work and distribution are independent', () {
    const data = MusicRightsRegistry(
      holders: [RightsHolder(id: 'h', name: 'Composer')],
      works: [MusicalWork(id: 'w', title: 'Work', shares: [
        WorkShare(holderId: 'h', role: 'composer', percentage: 100)])],
      organizations: [RightsOrganization(id: 's', name: 'SACEM',
        type: RightsOrganizationType.collectiveManagement)],
      filings: [RightsFiling(id: 'f', workId: 'w', organizationId: 's',
        status: RightsFilingStatus.submitted)],
      distributions: [DistributionDelivery(id: 'd', collectionId: 'album',
        distributor: 'Distributor', status: DistributionStatus.delivered,
        platforms: [PlatformDelivery(platform: 'Spotify', status: DistributionStatus.unknown)])],
      collectionIds: ['album']);
    expect(data.validate(), isEmpty);
  });
}
