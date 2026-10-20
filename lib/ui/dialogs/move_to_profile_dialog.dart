import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';

/// A profile a song could move to, with the folders it scans.
class MoveTargetProfile {
  const MoveTargetProfile({
    required this.id,
    required this.name,
    required this.scanFolders,
  });
  final String id;
  final String name;
  final List<String> scanFolders;
}

/// What the user chose: where to, and — when the files move — into which
/// folder.
class MoveToProfileChoice {
  const MoveToProfileChoice({required this.profileId, this.destinationFolder});
  final String profileId;

  /// Null: the files stay where they are.
  final String? destinationFolder;
}

/// Asks where a song goes. Plain values and callbacks, so it can be tested
/// without Riverpod, Hive or a file picker.
class MoveToProfileDialog extends StatefulWidget {
  const MoveToProfileDialog({
    super.key,
    required this.songName,
    required this.sourceProfileName,
    required this.targets,
    required this.path,
    required this.pathIsScanned,
    required this.canMoveFiles,
    required this.releaseTitles,
    required this.versionCount,
    required this.sizeLabel,
    required this.pickFolder,
  });

  final String songName;
  final String sourceProfileName;
  final List<MoveTargetProfile> targets;

  /// What lives on disk for it (its folder, or its file).
  final String path;

  /// Whether the source profile scans [path] (so keeping the files means
  /// it stops scanning it).
  final bool pathIsScanned;

  /// False for a stack whose versions sit in several folders.
  final bool canMoveFiles;
  final List<String> releaseTitles;

  /// Versions in its stack; 0 for a song that isn't stacked.
  final int versionCount;

  /// "About N files (X MB) …", worked out on demand — counting a folder
  /// on a cloud drive can take a moment.
  final Future<String> Function() sizeLabel;
  final Future<String?> Function() pickFolder;

  @override
  State<MoveToProfileDialog> createState() => _MoveToProfileDialogState();
}

class _MoveToProfileDialogState extends State<MoveToProfileDialog> {
  late MoveTargetProfile _target = widget.targets.first;
  bool _moveFiles = false;
  String? _otherFolder;
  String? _chosenScanFolder;
  Future<String>? _size;

  String? get _destination => _otherFolder ?? _chosenScanFolder ?? _target.scanFolders.firstOrNull;

  void _setMoveFiles(bool value) {
    setState(() {
      _moveFiles = value;
      if (value) _size ??= widget.sizeLabel();
    });
  }

  Widget _option({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Key? key,
  }) =>
      ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        enabled: onTap != null,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final destination = _destination;
    final canConfirm = !_moveFiles || destination != null;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text(l10n.moveToProfileTitle(widget.songName)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.versionCount > 0) ...[
                Text(l10n.moveToProfileVersions(widget.versionCount)),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<String>(
                initialValue: _target.id,
                decoration: InputDecoration(labelText: l10n.moveToProfileTarget),
                items: [
                  for (final t in widget.targets)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                // Picking the profile already picked changes nothing. Another
                // one only resets the choice among its scan folders — they
                // are the old profile's — while "keep / move the files" and
                // a folder picked by hand stand.
                onChanged: (id) {
                  if (id == null || id == _target.id) return;
                  setState(() {
                    _target = widget.targets.firstWhere((t) => t.id == id);
                    _chosenScanFolder = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              _option(
                key: const ValueKey('move-keep-files'),
                selected: !_moveFiles,
                title: l10n.moveToProfileKeepFiles,
                subtitle: widget.pathIsScanned
                    ? l10n.moveToProfileKeepFilesHint(widget.sourceProfileName, widget.path)
                    : l10n.moveToProfileKeepFilesHintUnscanned,
                onTap: () => _setMoveFiles(false),
              ),
              _option(
                key: const ValueKey('move-files'),
                selected: _moveFiles,
                title: l10n.moveToProfileMoveFiles,
                subtitle: widget.canMoveFiles
                    ? widget.path
                    : l10n.moveToProfileCantMoveFiles,
                onTap: widget.canMoveFiles ? () => _setMoveFiles(true) : null,
              ),
              if (_moveFiles) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.moveToProfileInto, style: theme.textTheme.bodySmall),
                      for (final folder in _target.scanFolders)
                        _option(
                          selected: _otherFolder == null && destination == folder,
                          title: folder,
                          subtitle: _target.name,
                          onTap: () => setState(() {
                            _otherFolder = null;
                            _chosenScanFolder = folder;
                          }),
                        ),
                      if (_otherFolder != null)
                        _option(selected: true, title: _otherFolder!, subtitle: '', onTap: () {}),
                      if (_target.scanFolders.isEmpty && _otherFolder == null)
                        Text(l10n.moveToProfileNoFolder, style: theme.textTheme.bodySmall),
                      TextButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(l10n.moveToProfileOtherFolder),
                        onPressed: () async {
                          final picked = await widget.pickFolder();
                          if (picked != null && mounted) setState(() => _otherFolder = picked);
                        },
                      ),
                      FutureBuilder<String>(
                        future: _size,
                        builder: (context, snapshot) => Text(
                          snapshot.data ?? '…',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.releaseTitles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.moveToProfileReleases(
                          widget.sourceProfileName,
                          widget.releaseTitles.join(', '),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: canConfirm
              ? () => Navigator.pop(
                    context,
                    MoveToProfileChoice(
                      profileId: _target.id,
                      destinationFolder: _moveFiles ? destination : null,
                    ),
                  )
              : null,
          child: Text(l10n.moveToProfileConfirm),
        ),
      ],
    );
  }
}
