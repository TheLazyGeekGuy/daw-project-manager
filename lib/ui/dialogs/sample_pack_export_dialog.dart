import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/sample_pack/sample_pack_exporter.dart';

/// A profile as the export dialog lists it.
class SamplePackProfileChoice {
  const SamplePackProfileChoice({
    required this.id,
    required this.name,
    required this.projectCount,
  });

  final String id;
  final String name;
  final int projectCount;
}

/// What the person chose in [SamplePackExportDialog].
class SamplePackExportChoice {
  const SamplePackExportChoice({
    required this.profileIds,
    required this.libraryFolders,
    required this.includeOwnAudio,
    required this.includeMidi,
  });

  final List<String> profileIds;
  final List<String> libraryFolders;
  final bool includeOwnAudio;
  final bool includeMidi;
}

/// Asks which profiles' projects to collect samples from, where else to look
/// for samples, and what else goes in the pack. Pops with a
/// [SamplePackExportChoice], or null when cancelled.
///
/// Takes plain values and a folder picker, no providers or Hive, so it can be
/// pumped on its own.
class SamplePackExportDialog extends StatefulWidget {
  const SamplePackExportDialog({
    super.key,
    required this.profiles,
    required this.initialProfileIds,
    required this.initialLibraryFolders,
    required this.initialIncludeOwnAudio,
    required this.initialIncludeMidi,
    required this.pickFolder,
  });

  final List<SamplePackProfileChoice> profiles;

  /// Ticked when the dialog opens; ids no longer among [profiles] are
  /// ignored.
  final Set<String> initialProfileIds;
  final List<String> initialLibraryFolders;
  final bool initialIncludeOwnAudio;
  final bool initialIncludeMidi;

  /// Asks for a library folder to add; null when cancelled.
  final Future<String?> Function() pickFolder;

  @override
  State<SamplePackExportDialog> createState() => _SamplePackExportDialogState();
}

class _SamplePackExportDialogState extends State<SamplePackExportDialog> {
  late final Set<String> _selected = {
    for (final pr in widget.profiles)
      if (widget.initialProfileIds.contains(pr.id)) pr.id,
  };
  late final List<String> _folders = [...widget.initialLibraryFolders];
  late bool _includeOwnAudio = widget.initialIncludeOwnAudio;
  late bool _includeMidi = widget.initialIncludeMidi;

  Future<void> _addFolder() async {
    final folder = await widget.pickFolder();
    if (folder == null || !mounted) return;
    setState(() {
      if (!_folders.contains(folder)) _folders.add(folder);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final allSelected = _selected.length == widget.profiles.length;
    return AlertDialog(
      title: Text(l10n.samplePackDialogTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(l10n.samplePackProfiles,
                        style: theme.textTheme.titleSmall),
                  ),
                  TextButton(
                    onPressed: allSelected
                        ? null
                        : () => setState(() => _selected
                          ..clear()
                          ..addAll(widget.profiles.map((pr) => pr.id))),
                    child: Text(l10n.samplePackSelectAll),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: Text(l10n.samplePackSelectNone),
                  ),
                ],
              ),
              for (final profile in widget.profiles)
                CheckboxListTile(
                  key: ValueKey('samplePackProfile-${profile.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(profile.id),
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _selected.add(profile.id);
                    } else {
                      _selected.remove(profile.id);
                    }
                  }),
                  title: Text(profile.name),
                  subtitle:
                      Text(l10n.samplePackProjectCount(profile.projectCount)),
                ),
              const Divider(height: 24),
              Text(l10n.samplePackLibraryFolders,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l10n.samplePackLibraryFoldersHelp,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              if (_folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l10n.samplePackNoLibraryFolders,
                      style: theme.textTheme.bodySmall),
                )
              else
                for (final folder in _folders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.folder_open),
                    title: Text(folder),
                    trailing: IconButton(
                      tooltip: l10n.remove,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _folders.remove(folder)),
                    ),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(l10n.addFolder),
                ),
              ),
              const Divider(height: 24),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeOwnAudio,
                onChanged: (v) => setState(() => _includeOwnAudio = v ?? false),
                title: Text(l10n.samplePackIncludeOwnAudio),
                subtitle: Text(l10n.samplePackIncludeOwnAudioHelp(
                  kOwnAudioFolder,
                )),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeMidi,
                onChanged: (v) => setState(() => _includeMidi = v ?? false),
                title: Text(l10n.samplePackIncludeMidi),
              ),
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
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    SamplePackExportChoice(
                      profileIds: [
                        for (final pr in widget.profiles)
                          if (_selected.contains(pr.id)) pr.id,
                      ],
                      libraryFolders: List.unmodifiable(_folders),
                      includeOwnAudio: _includeOwnAudio,
                      includeMidi: _includeMidi,
                    ),
                  ),
          child: Text(l10n.samplePackChooseDestination),
        ),
      ],
    );
  }
}

/// Runs the export through [run] while showing how far it is, and closes
/// with its result. Its one button stops it; what was copied stays.
class SamplePackProgressDialog extends StatefulWidget {
  const SamplePackProgressDialog({super.key, required this.run});

  final Future<SamplePackResult> Function(
    SamplePackProgress onProgress,
    bool Function() shouldStop,
  ) run;

  @override
  State<SamplePackProgressDialog> createState() =>
      _SamplePackProgressDialogState();
}

class _SamplePackProgressDialogState extends State<SamplePackProgressDialog> {
  SamplePackPhase _phase = SamplePackPhase.reading;
  int _done = 0;
  int _total = 0;
  String _current = '';
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    Object? error;
    SamplePackResult? result;
    try {
      result = await widget.run(
        (phase, done, total, current) {
          if (!mounted) return;
          setState(() {
            _phase = phase;
            _done = done;
            _total = total;
            _current = current;
          });
        },
        () => _stop,
      );
    } catch (e) {
      error = e;
    }
    if (mounted) Navigator.pop(context, result ?? error);
  }

  String _line(AppLocalizations l10n) {
    final n = _done + 1 > _total ? _total : _done + 1;
    return switch (_phase) {
      SamplePackPhase.reading => l10n.samplePackReading(n, _total, _current),
      SamplePackPhase.locating => l10n.samplePackLocating(n, _total, _current),
      SamplePackPhase.measuring => l10n.samplePackMeasuring(n, _total, _current),
      SamplePackPhase.copying => l10n.samplePackCopying(n, _total, _current),
      SamplePackPhase.midi => l10n.samplePackWritingMidi(n, _total, _current),
      SamplePackPhase.finishing => l10n.samplePackFinishing,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.samplePackProgressTitle),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
              ),
              const SizedBox(height: 12),
              Text(_line(l10n), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _stop ? null : () => setState(() => _stop = true),
            child: Text(l10n.stop),
          ),
        ],
      ),
    );
  }
}

/// What the export did, with a way into the folder.
class SamplePackResultDialog extends StatelessWidget {
  const SamplePackResultDialog({
    super.key,
    required this.result,
    required this.onOpenFolder,
  });

  final SamplePackResult result;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = [
      l10n.samplePackAdded(result.added),
      if (result.alreadyInPack > 0) l10n.samplePackAlreadyThere(result.alreadyInPack),
      if (result.leftOut > 0) l10n.samplePackLeftOut(result.leftOut),
      if (result.midiFiles > 0) l10n.samplePackMidiWritten(result.midiFiles),
      if (result.missing > 0)
        l10n.samplePackMissing(result.missing, kSamplePackProblems),
      if (result.projectsNotRead > 0)
        l10n.samplePackNotRead(result.projectsNotRead, kSamplePackProblems),
    ];
    return AlertDialog(
      title: Text(result.stopped
          ? l10n.samplePackStoppedTitle
          : l10n.samplePackDoneTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $line'),
              ),
            const SizedBox(height: 6),
            Text(
              l10n.samplePackReportHint(kSamplePackReport),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
        FilledButton.icon(
          onPressed: onOpenFolder,
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.openFolder),
        ),
      ],
    );
  }
}
