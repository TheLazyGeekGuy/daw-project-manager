/// Separate compositions, recordings, release delivery and rights filings.
enum RightsOrganizationType { collectiveManagement, neighboringRights, publisher, other }
enum RightsFilingStatus { draft, ready, submitted, acknowledged, accepted, rejected, needsReview }
enum DistributionStatus { draft, prepared, submitted, inReview, accepted, delivered, live, rejected, takenDown, unknown }
class RightsHolder {
  const RightsHolder({required this.id, required this.name, this.ipi, this.isni});
  final String id, name;
  final String? ipi, isni;
}
class WorkShare {
  const WorkShare({required this.holderId, required this.role, required this.percentage});
  final String holderId, role;
  final double percentage;
}
class MusicalWork {
  const MusicalWork({required this.id, required this.title, this.iswc, this.shares = const []});
  final String id, title;
  final String? iswc;
  final List<WorkShare> shares;
}
class RightsOrganization {
  const RightsOrganization({required this.id, required this.name, required this.type, this.country});
  final String id, name;
  final RightsOrganizationType type;
  final String? country;
}
class RightsFiling {
  const RightsFiling({required this.id, required this.workId, required this.organizationId,
    required this.status, this.reference, this.evidencePaths = const []});
  final String id, workId, organizationId;
  final RightsFilingStatus status;
  final String? reference;
  final List<String> evidencePaths;
}
class PlatformDelivery {
  const PlatformDelivery({required this.platform, required this.status, this.url});
  final String platform;
  final DistributionStatus status;
  final String? url;
}
class DistributionDelivery {
  const DistributionDelivery({required this.id, required this.collectionId,
    required this.distributor, required this.status, this.platforms = const []});
  final String id, collectionId, distributor;
  final DistributionStatus status;
  final List<PlatformDelivery> platforms;
}
class MusicRightsRegistry {
  const MusicRightsRegistry({this.holders = const [], this.works = const [],
    this.organizations = const [], this.filings = const [], this.distributions = const [],
    this.collectionIds = const []});
  final List<RightsHolder> holders;
  final List<MusicalWork> works;
  final List<RightsOrganization> organizations;
  final List<RightsFiling> filings;
  final List<DistributionDelivery> distributions;
  final List<String> collectionIds;
  List<String> validate() {
    final issues = <String>[];
    final holdersById = holders.map((e) => e.id).toSet();
    final worksById = works.map((e) => e.id).toSet();
    final orgsById = organizations.map((e) => e.id).toSet();
    for (final work in works) {
      var total = 0.0;
      for (final share in work.shares) {
        if (!holdersById.contains(share.holderId)) issues.add('Missing rights holder');
        if (!share.percentage.isFinite || share.percentage < 0 || share.percentage > 100) {
          issues.add('Invalid share');
        } else { total += share.percentage; }
      }
      if (work.shares.isNotEmpty && (total - 100).abs() > 0.001) issues.add('Shares must total 100%');
    }
    for (final filing in filings) {
      if (!worksById.contains(filing.workId)) issues.add('Unknown work');
      if (!orgsById.contains(filing.organizationId)) issues.add('Unknown organization');
    }
    for (final distribution in distributions) {
      if (!collectionIds.contains(distribution.collectionId)) issues.add('Unknown collection');
    }
    return issues;
  }
}
