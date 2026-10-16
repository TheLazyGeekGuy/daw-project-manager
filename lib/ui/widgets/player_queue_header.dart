import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';

/// The desktop music player's queue header: its title and count, the
/// library's actions (auto-queue by key, shuffle, repeat) and the queue's
/// (previous, next, clear).
///
/// The pane is narrow (about 260 px), and with a queue all six buttons
/// show: written as a plain row it overflowed by 14 px in English, more in
/// German ("Warteschlange"). The buttons are compact and the title gives way,
/// shortened with an ellipsis, rather than pushing them out.
class PlayerQueueHeader extends StatelessWidget {
  const PlayerQueueHeader({
    super.key,
    required this.count,
    required this.libraryActions,
    required this.queueActions,
    required this.shuffleOn,
    required this.repeatOn,
    required this.onAutoQueue,
    required this.onShuffle,
    required this.onRepeat,
    required this.onPrevious,
    required this.onNext,
    required this.onClear,
  });

  /// Tracks in the queue.
  final int count;

  /// Whether the library has tracks, so auto-queue, shuffle and repeat apply.
  final bool libraryActions;

  /// Whether the queue has tracks, so previous, next and clear apply.
  final bool queueActions;
  final bool shuffleOn;
  final bool repeatOn;
  final VoidCallback onAutoQueue;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dim = cs.onSurface.withValues(alpha: 0.35);

    Widget button(IconData icon, String tooltip, VoidCallback onPressed,
            {double size = 18, Color? color}) =>
        IconButton(
          icon: Icon(icon, size: size, color: color),
          tooltip: tooltip,
          // Material 3 keeps a 48 px tap target unless the style says
          // otherwise; `constraints` alone is ignored.
          style: IconButton.styleFrom(
            minimumSize: const Size(30, 30),
            fixedSize: const Size(30, 30),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
        );

    return Row(
      children: [
        Icon(Icons.queue_music, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  l10n.playerQueueTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        if (libraryActions) ...[
          button(Icons.auto_awesome, l10n.camelotGenerateButton, onAutoQueue,
              size: 16, color: dim),
          button(Icons.shuffle, l10n.playerShuffle, onShuffle,
              size: 16, color: shuffleOn ? cs.primary : dim),
          button(Icons.repeat, l10n.playerRepeatAll, onRepeat,
              size: 16, color: repeatOn ? cs.primary : dim),
        ],
        if (queueActions) ...[
          button(Icons.skip_previous, l10n.playerPrev, onPrevious),
          button(Icons.skip_next, l10n.playerNext, onNext),
          button(Icons.clear_all, l10n.playerClearQueue, onClear),
        ],
      ],
    );
  }
}
