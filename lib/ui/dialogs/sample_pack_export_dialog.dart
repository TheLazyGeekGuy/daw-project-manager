import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/sample_pack/sample_pack_exporter.dart';

/// A profile as the export dialog lists it.
class SamplePackProfileChoice {
  const SamplePackProfileChoice({required this.id, required this.name});

  final String id;
  final String name;
}

/// A project as the export dialog's picker lists it.
class SamplePackProjectChoice {
  const SamplePackProjectChoice({
    required this.id,
    required this.profileId,
    required this.name,
    this.detail = '',
  });

  final String id;
  final String profileId;
  final String name;

  /// Shown under the name and searched with it: the project's file name.
  final String detail;
}

/// What the person chose in [SamplePackExportDialog].
class SamplePackExportChoice {
  const SamplePackExportChoice({
    required this.profileIds,
    required this.libraryFolders,
    required this.includeOwnAudio,
    required this.includeMidi,
    required this.excludeMasterProjects,
    this.projectIds,
  });

  final List<String> profileIds;

  /// The projects picked, all in [profileIds]; null for every project in
  /// those profiles.
  final List<String>? projectIds;
  final List<String> libraryFolders;
  final bool includeOwnAudio;
  final bool includeMidi;
  final bool excludeMasterProjects;
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
    required this.projects,
    required this.initialProfileIds,
    this.initialOnlyPicked = false,
    this.initialPickedProjectIds = const {},
    required this.initialLibraryFolders,
    required this.initialIncludeOwnAudio,
    required this.initialIncludeMidi,
    required this.initialExcludeMasterProjects,
    required this.pickFolder,
  });

  final List<SamplePackProfileChoice> profiles;

  /// Every project of every profile, for the picker and the counts.
  final List<SamplePackProjectChoice> projects;

  /// Ticked when the dialog opens; ids no longer among [profiles] are
  /// ignored.
  final Set<String> initialProfileIds;

  /// Whether the picker is open, and what is ticked in it.
  final bool initialOnlyPicked;
  final Set<String> initialPickedProjectIds;
  final List<String> initialLibraryFolders;
  final bool initialIncludeOwnAudio;
  final bool initialIncludeMidi;
  final bool initialExcludeMasterProjects;

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
  late bool _excludeMasters = widget.initialExcludeMasterProjects;
  late bool _onlyPicked = widget.initialOnlyPicked;
  late final Set<String> _picked = {
    for (final pr in widget.projects)
      if (widget.initialPickedProjectIds.contains(pr.id)) pr.id,
  };
  String _search = '';

  int _projectCount(String profileId) =>
      widget.projects.where((pr) => pr.profileId == profileId).length;

  /// The selected profiles' projects, matching the search, by name.
  List<SamplePackProjectChoice> get _listed {
    final query = _search.trim().toLowerCase();
    return [
      for (final pr in widget.projects)
        if (_selected.contains(pr.profileId) &&
            (query.isEmpty ||
                pr.name.toLowerCase().contains(query) ||
                pr.detail.toLowerCase().contains(query)))
          pr,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Picked projects in profiles that are still selected.
  List<String> get _pickedIds => [
        for (final pr in widget.projects)
          if (_selected.contains(pr.profileId) && _picked.contains(pr.id)) pr.id,
      ];

  bool get _canExport =>
      _selected.isNotEmpty && (!_onlyPicked || _pickedIds.isNotEmpty);

  Future<void> _addFolder() async {
    final folder = await widget.pickFolder();
    if (folder == null || !mounted) return;
    setState(() {
      if (!_folders.contains(folder)) _folders.add(folder);
    });
  }

  /// All projects, or only the ones picked from a searchable list.
  List<Widget> _projectPicker(AppLocalizations l10n, ThemeData theme) {
    final listed = _onlyPicked ? _listed : const <SamplePackProjectChoice>[];
    final profileNames = {for (final pr in widget.profiles) pr.id: pr.name};
    final showProfile = _selected.length > 1;
    return [
      Text(l10n.samplePackProjects, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(l10n.samplePackAllProjects)),
          ButtonSegment(value: true, label: Text(l10n.samplePackPickedProjects)),
        ],
        selected: {_onlyPicked},
        onSelectionChanged: (v) => setState(() => _onlyPicked = v.first),
      ),
      if (_onlyPicked) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('samplePackProjectSearch'),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.samplePackSearchProjects,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            TextButton(
              key: const ValueKey('samplePackPickAll'),
              onPressed: listed.every((pr) => _picked.contains(pr.id))
                  ? null
                  : () => setState(
                        () => _picked.addAll(listed.map((pr) => pr.id)),
                      ),
              child: Text(l10n.samplePackSelectAll),
            ),
            TextButton(
              key: const ValueKey('samplePackPickNone'),
              onPressed: listed.any((pr) => _picked.contains(pr.id))
                  ? () => setState(
                        () => _picked.removeAll(listed.map((pr) => pr.id)),
                      )
                  : null,
              child: Text(l10n.samplePackSelectNone),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 260,
          child: listed.isEmpty
              ? Center(
                  child: Text(l10n.samplePackNoProjectsMatch,
                      style: theme.textTheme.bodySmall),
                )
              : ListView.builder(
                  itemCount: listed.length,
                  itemBuilder: (context, i) {
                    final pr = listed[i];
                    final subtitle = [
                      if (showProfile) profileNames[pr.profileId] ?? '',
                      pr.detail,
                    ].where((t) => t.isNotEmpty).join(' · ');
                    return CheckboxListTile(
                      key: ValueKey('samplePackProject-${pr.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _picked.contains(pr.id),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _picked.add(pr.id);
                        } else {
                          _picked.remove(pr.id);
                        }
                      }),
                      title: Text(pr.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: subtitle.isEmpty
                          ? null
                          : Text(subtitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                    );
                  },
                ),
        ),
        const SizedBox(height: 4),
        Text(l10n.samplePackPickedCount(_pickedIds.length),
            style: theme.textTheme.bodySmall),
      ],
    ];
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
                  subtitle: Text(
                      l10n.samplePackProjectCount(_projectCount(profile.id))),
                ),
              const Divider(height: 24),
              ..._projectPicker(l10n, theme),
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
                value: _excludeMasters,
                onChanged: (v) => setState(() => _excludeMasters = v ?? false),
                title: Text(l10n.samplePackExcludeMasters),
                subtitle: Text(l10n.samplePackExcludeMastersHelp),
              ),
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
          onPressed: !_canExport
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
                      excludeMasterProjects: _excludeMasters,
                      projectIds: _onlyPicked ? _pickedIds : null,
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
  SamplePackProgressUpdate? _update;
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
        (update) {
          if (mounted) setState(() => _update = update);
        },
        () => _stop,
      );
    } catch (e) {
      error = e;
    }
    if (mounted) Navigator.pop(context, result ?? error);
  }

  /// The project being read, or what is being written at the end.
  String _projectLine(AppLocalizations l10n, SamplePackProgressUpdate u) {
    switch (u.phase) {
      case SamplePackPhase.midi:
        return l10n.samplePackWritingMidi(u.done + 1, u.total, u.current);
      case SamplePackPhase.finishing:
        return l10n.samplePackFinishing;
      default:
        final n = u.project + 1 > u.projects ? u.projects : u.project + 1;
        return l10n.samplePackReading(n, u.projects, u.projectName);
    }
  }

  /// What is happening inside that project, if anything.
  String? _stepLine(AppLocalizations l10n, SamplePackProgressUpdate u) {
    final n = u.done + 1 > u.total ? u.total : u.done + 1;
    return switch (u.phase) {
      SamplePackPhase.locating => l10n.samplePackLocating(n, u.total, u.current),
      SamplePackPhase.measuring => l10n.samplePackMeasuring(n, u.total, u.current),
      SamplePackPhase.copying => l10n.samplePackCopying(n, u.total, u.current),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final u = _update;
    final step = u == null ? null : _stepLine(l10n, u);
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
              LinearProgressIndicator(value: u?.fraction),
              const SizedBox(height: 12),
              if (u != null)
                Text(_projectLine(l10n, u),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              if (step != null) ...[
                const SizedBox(height: 4),
                Text(
                  step,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
      if (result.masterProjectsLeftOut > 0)
        l10n.samplePackMastersLeftOut(result.masterProjectsLeftOut),
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
