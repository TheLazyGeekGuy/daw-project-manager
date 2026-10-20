import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/companion_bridge/companion_protocol.dart';
import '../../services/companion_bridge/riverpod_companion_session_hooks.dart';

/// "1h 5m", "12m", "< 1m" — the end-session dialog's format.
String formatSessionLength(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '< 1m';
}

/// Why the session ended, in a sentence: the DAW closed the project, or the
/// plugin stopped answering (a crash, most likely).
String companionSessionEndedReason(AppLocalizations l10n, CompanionSessionEnded ended) {
  final daw = ended.departure.hostName.trim().isEmpty ? l10n.companionUnknownDaw : ended.departure.hostName.trim();
  return switch (ended.departure.reason) {
    CompanionDepartureReason.closed => l10n.companionSessionEndedClosed(daw, ended.projectName),
    CompanionDepartureReason.stoppedResponding => l10n.companionSessionEndedNoResponse(daw, ended.projectName),
  };
}

/// "12:51–13:42 · 51m"
String companionSessionSummary(AppLocalizations l10n, CompanionSessionEnded ended) {
  final time = DateFormat('HH:mm');
  return l10n.companionSessionEndedSummary(
    time.format(ended.session.start),
    time.format(ended.session.end),
    formatSessionLength(ended.session.seconds),
  );
}

/// Tells the user the DAW ended their work session, with its summary — so a
/// session doesn't silently vanish from the dashboard.
Future<void> showCompanionSessionEndedDialog(BuildContext context, CompanionSessionEnded ended) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.companionSessionEndedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ended.projectName,
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 6),
              Text(companionSessionSummary(l10n, ended), style: Theme.of(ctx).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 12),
          Text(companionSessionEndedReason(l10n, ended), style: Theme.of(ctx).textTheme.bodySmall),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
