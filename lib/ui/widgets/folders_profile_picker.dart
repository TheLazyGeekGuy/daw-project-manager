import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';

/// Settings > Project folders: which profile's folders, excluded folders and
/// Recently deleted are shown and edited — the active one by default. When
/// another is picked, says so, so a change never lands somewhere unexpected.
class FoldersProfilePicker extends StatelessWidget {
  const FoldersProfilePicker({
    super.key,
    required this.profiles,
    required this.selectedId,
    required this.onChanged,
  });

  final List<({String id, String name, bool active})> profiles;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selected = profiles.where((p) => p.id == selectedId).firstOrNull;
    final editingOther = selected != null && !selected.active;
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
                const Icon(Icons.person_outline),
                const SizedBox(width: 8),
                Text(l10n.foldersProfilePickerLabel, style: theme.textTheme.titleMedium),
                const SizedBox(width: 16),
                Flexible(
                  child: DropdownButton<String>(
                    value: selectedId,
                    isExpanded: true,
                    items: [
                      for (final p in profiles)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.active ? l10n.foldersProfileActive(p.name) : p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null && id != selectedId) onChanged(id);
                    },
                  ),
                ),
              ],
            ),
            if (editingOther) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('editing-other-profile'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.foldersEditingOtherProfile(selected.name),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
