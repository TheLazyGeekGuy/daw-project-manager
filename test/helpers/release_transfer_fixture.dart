import 'package:daw_project_manager/services/release_workspace_migration.dart';

const releaseTransferTime = '2026-01-01T12:00:00.000Z';

Map<String, dynamic> transferCatalog(
  String profileId, {
  String? updatedAt = releaseTransferTime,
  List<Map<String, dynamic>> artists = const [],
}) => {
  'schema_version': 1,
  'revision': 0,
  'profile_id': profileId,
  'updated_at': ?updatedAt,
  'artists': artists,
  'holders': <Object>[],
  'works': <Object>[],
  'tracks': <Object>[],
  'playlists': <Object>[],
};

Map<String, dynamic> transferWorkspace(
  String profileId, {
  String releaseId = 'release-1',
  String? updatedAt = releaseTransferTime,
  List<Map<String, dynamic>> tracks = const [],
}) => {
  ...ReleaseWorkspaceMigration.empty(releaseId, profileId: profileId),
  'updated_at': ?updatedAt,
  'tracks': tracks,
};

Map<String, dynamic> transferBundle(
  String profileId, {
  Map<String, dynamic>? catalog,
  Map<String, dynamic> workspaces = const {},
}) => {
  'schema_version': 1,
  'profile_id': profileId,
  'catalog': catalog ?? transferCatalog(profileId),
  'workspaces': workspaces,
};
