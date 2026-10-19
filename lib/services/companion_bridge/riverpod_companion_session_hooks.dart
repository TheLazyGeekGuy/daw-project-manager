import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'companion_bridge_service.dart';
import 'companion_protocol.dart';

/// A session the DAW ended, for telling the user — otherwise it would just
/// vanish from the dashboard and they might keep working without a clock.
class CompanionSessionEnded {
  final String projectName;
  final CompanionDeparture departure;
  final EndedSession session;

  const CompanionSessionEnded(this.projectName, this.departure, this.session);
}

/// The bridge's view of the app's work sessions: the active project is the
/// running session, clearing it ends one (the work timer saves it), setting
/// it starts one — the same moves the dashboard's buttons make.
class RiverpodCompanionSessionHooks implements CompanionSessionHooks {
  RiverpodCompanionSessionHooks(this.container, {this.onSessionEnded}) {
    // Kept alive from here on: the timer is what saves a session when the
    // active project is cleared, window open or not.
    container.listen(workTimerProvider, (_, _) {});
    container.listen(currentProfileProvider, (_, _) {});
    container.listen(companionEndSessionProvider, (_, _) {});
    container.listen(companionStartSessionProvider, (_, _) {});
  }

  final ProviderContainer container;

  /// Shows the user what happened (main.dart: a dialog, and a notification
  /// when the window isn't in front).
  final void Function(CompanionSessionEnded ended)? onSessionEnded;

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
  Future<void> endSession(CompanionDeparture departure) async {
    final project = container.read(activeProjectProvider);
    final session = container.read(workTimerProvider.notifier).endAt(departure.at);
    if (project != null && session != null) {
      onSessionEnded?.call(CompanionSessionEnded(project.displayName, departure, session));
    }
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
