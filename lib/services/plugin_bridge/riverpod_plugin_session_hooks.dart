import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'plugin_bridge_service.dart';
import 'plugin_protocol.dart';

/// A session the DAW ended, for telling the user — otherwise it would just
/// vanish from the dashboard and they might keep working without a clock.
class DpmPluginSessionEnded {
  final String projectName;
  final DpmPluginDeparture departure;
  final EndedSession session;

  const DpmPluginSessionEnded(this.projectName, this.departure, this.session);
}

/// The bridge's view of the app's work sessions: the active project is the
/// running session, clearing it ends one (the work timer saves it), setting
/// it starts one — the same moves the dashboard's buttons make.
class RiverpodDpmPluginSessionHooks implements DpmPluginSessionHooks {
  RiverpodDpmPluginSessionHooks(this.container, {this.onSessionEnded}) {
    // Kept alive from here on: the timer is what saves a session when the
    // active project is cleared, window open or not.
    container.listen(workTimerProvider, (_, _) {});
    container.listen(currentProfileProvider, (_, _) {});
    container.listen(dpmPluginEndSessionProvider, (_, _) {});
    container.listen(dpmPluginStartSessionProvider, (_, _) {});
  }

  final ProviderContainer container;

  /// Shows the user what happened (main.dart: a dialog, and a notification
  /// when the window isn't in front).
  final void Function(DpmPluginSessionEnded ended)? onSessionEnded;

  String? get _profileId => container.read(currentProfileProvider).value?.id;

  @override
  DpmPluginProjectRef? activeSession() {
    final active = container.read(activeProjectProvider);
    final profileId = _profileId;
    if (active == null || profileId == null) return null;
    return DpmPluginProjectRef(profileId, active.id);
  }

  @override
  bool get endWhenDawCloses => container.read(dpmPluginEndSessionProvider);

  @override
  bool get startWhenDawOpens => container.read(dpmPluginStartSessionProvider);

  @override
  Future<void> endSession(DpmPluginDeparture departure) async {
    final project = container.read(activeProjectProvider);
    final session = container.read(workTimerProvider.notifier).endAt(departure.at);
    if (project != null && session != null) {
      onSessionEnded?.call(DpmPluginSessionEnded(project.displayName, departure, session));
    }
  }

  @override
  Future<void> startSession(DpmPluginProjectRef project) async {
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
