import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/music_project.dart';
import '../../providers/providers.dart';
import 'plugin_bridge_service.dart';
import 'plugin_protocol.dart';

/// The bridge's view of the real library: every profile, each through
/// [repositoryForProfileProvider] — the active profile's own repository when
/// it is the active one, so an edit made for the plugin shows at once.
///
/// Opening a profile's repository keeps its boxes resident for the session,
/// the same accepted tradeoff Settings > Project folders makes.
class RepositoryDpmPluginLibrary implements DpmPluginLibrary {
  RepositoryDpmPluginLibrary(this.container);

  final ProviderContainer container;

  @override
  Future<List<DpmPluginProfileProjects>> load() async {
    final profiles = await container.read(profileRepositoryProvider.future);
    final result = <DpmPluginProfileProjects>[];
    for (final profile in profiles.getAllProfiles()) {
      final repo = await container.read(repositoryForProfileProvider(profile.id).future);
      result.add(DpmPluginProfileProjects(profile, repo.getAllProjects()));
    }
    return result;
  }

  @override
  Future<void> saveProject(String profileId, MusicProject project) async {
    final repo = await container.read(repositoryForProfileProvider(profileId).future);
    await repo.updateProject(project);
  }
}
