import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'companion_bridge_service.dart';
import 'companion_protocol.dart';

/// The bridge's view of the app's work sessions: the active project is the
/// running session, clearing it ends one (the work timer saves it), setting
/// it starts one — the same moves the dashboard's buttons make.
class RiverpodCompanionSessionHooks implements CompanionSessionHooks {
  RiverpodCompanionSessionHooks(this.container) {
    // Kept alive from here on: the timer is what saves a session when the
    // active project is cleared, window open or not.
    container.listen(workTimerProvider, (_, _) {});
    container.listen(currentProfileProvider, (_, _) {});
    container.listen(companionEndSessionProvider, (_, _) {});
    container.listen(companionStartSessionProvider, (_, _) {});
  }

  final ProviderContainer container;

  String? get _profileId => container.read(currentProfileProvider).value?.id;

  @override
  CompanionProjectRef? activeSession() {
    final active = container.read(activeProjectProvider);
    final profileId = _profileId;
    if (active == null || profileId == null) return null;
    return CompanionProjectRef(profileId, active.id);
  }

  @override
  bool get endWhenDawCloses => container.read(companionEndSessionProvider);

  @override
  bool get startWhenDawOpens => container.read(companionStartSessionProvider);

  @override
  Future<void> endSession(DateTime at) async {
    container.read(workTimerProvider.notifier).endAt(at);
  }

  @override
  Future<void> startSession(CompanionProjectRef project) async {
    // Sessions belong to the active profile: a project of another artist
    // never switches profiles behind the user's back.
    if (project.profileId != _profileId) return;
    if (container.read(activeProjectProvider) != null) return;

    final repo = await container.read(repositoryProvider.future);
    final row = repo.getById(project.projectId);
    if (row == null || row.isVirtual) return;
    container.read(activeProjectProvider.notifier).set(row);
  }
}
