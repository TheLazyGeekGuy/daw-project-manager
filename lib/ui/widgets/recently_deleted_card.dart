import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../repository/project_trash.dart';
import '../../utils/drive_sync_format.dart' show syncAgoLabel;

/// Settings > Project folders > Recently deleted: the profile's deleted
/// projects, each restorable or deletable for good. Plain values and
/// callbacks, so it can be tested without Riverpod or Hive.
class RecentlyDeletedCard extends StatelessWidget {
  const RecentlyDeletedCard({
    super.key,
    required this.items,
    required this.now,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onEmpty,
    this.busy = false,
  });

  final List<TrashedProject> items;
  final DateTime now;
  final ValueChanged<TrashedProject> onRestore;
  final ValueChanged<TrashedProject> onDeleteForever;
  final VoidCallback onEmpty;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.delete_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.recentlyDeletedTitle, style: theme.textTheme.titleMedium),
                ),
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: busy ? null : onEmpty,
                    child: Text(l10n.recentlyDeletedEmptyAll),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.recentlyDeletedSubtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.recentlyDeletedNothing,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                ),
              )
            else
              for (final item in items)
                ListTile(
                  key: ValueKey('trashed-${item.project.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.project.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${l10n.recentlyDeletedWhen(syncAgoLabel(l10n, item.deletedAt, now, locale: locale))}'
                    ' · ${l10n.recentlyDeletedExpires(_daysLeft(item))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => onRestore(item),
                        child: Text(l10n.recentlyDeletedRestore),
                      ),
                      IconButton(
                        tooltip: l10n.recentlyDeletedDeleteForever,
                        icon: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                        onPressed: busy ? null : () => onDeleteForever(item),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  int _daysLeft(TrashedProject item) {
    final left = item.expiresAt.difference(now).inHours / 24;
    return left <= 1 ? 1 : left.ceil();
  }
}
