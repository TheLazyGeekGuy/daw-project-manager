import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';
import '../../services/release_asset_verifier.dart';
import '../../services/release_catalog_store.dart';
import '../../services/release_native_bridge.dart';
import '../../services/release_workflow_engine.dart';
import '../../services/release_workflow_validator.dart';
import '../../services/release_workspace_store.dart';
import 'release_metadata_form.dart';

/// Profile-scoped native catalogue and release workflow editor.
/// External registrations and publications are manual records.
class ReleaseWorkflowEditor extends StatefulWidget {
  const ReleaseWorkflowEditor({
    super.key,
    required this.releaseId,
    required this.store,
    this.catalogStore,
    this.availableProjects = const [],
    this.initialTracks = const [],
    this.initialAssets = const [],
    this.initialTitle,
    this.initialDescription,
    this.initialReleaseDate,
    this.syncNativeRelease = false,
    this.beforeSave,
    this.onSaved,
  });
  final String releaseId;
  final ReleaseWorkspaceStore store;
  final ReleaseCatalogStore? catalogStore;
  final List<Map<String, dynamic>> availableProjects,
      initialTracks,
      initialAssets;
  final String? initialTitle, initialDescription, initialReleaseDate;
  final bool syncNativeRelease;
  final Future<void> Function()? beforeSave;
  final Future<void> Function(Map<String, dynamic>)? onSaved;
  @override
  State<ReleaseWorkflowEditor> createState() => _ReleaseWorkflowEditorState();
}

class _ReleaseWorkflowEditorState extends State<ReleaseWorkflowEditor> {
  final _validator = const ReleaseWorkflowValidator();
  Map<String, dynamic>? _workspace, _catalog, _catalogBaseline;
  bool _busy = true, _dirty = false;
  String? _message, _error;
  int _workspaceRevision = 0, _catalogRevision = 0;
  AppLocalizations get l =>
      AppLocalizations.of(context) ?? AppLocalizationsEn();
  ReleaseCatalogStore get _catalogStore =>
      widget.catalogStore ??
      ReleaseCatalogStore(
        widget.store.directory,
        profileId: widget.store.profileId,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  List<Map<String, dynamic>> _records(
    Map<String, dynamic> source,
    String key,
  ) => (source[key] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> _rows(String key, {bool catalog = false}) =>
      _records(catalog ? _catalog! : _workspace!, key);
  Map<String, String> _options(String key, {bool catalog = false}) => {
    for (final row in _rows(key, catalog: catalog))
      row['id'] as String: (row['name'] ?? row['title'] ?? row['id'])
          .toString(),
  };
  Map<String, String> _statuses(Iterable<String> values) => {
    for (final value in values) value: value.replaceAll('_', ' '),
  };

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var workspace = await widget.store.read(widget.releaseId);
      final persistedWorkspace = _copy(workspace);
      final catalog = await _catalogStore.read();
      _catalogBaseline = _copy(catalog);
      if (workspace['revision'] == 0) {
        workspace.putIfAbsent('title', () => widget.initialTitle ?? '');
        if (widget.initialDescription != null) {
          workspace.putIfAbsent('description', () => widget.initialDescription);
        }
        if (widget.initialReleaseDate != null) {
          workspace.putIfAbsent(
            'release_date',
            () => widget.initialReleaseDate,
          );
        }
        if ((workspace['tracks'] as List).isEmpty) {
          workspace['tracks'] = widget.initialTracks.map(_copy).toList();
        }
        if ((workspace['assets'] as List).isEmpty) {
          workspace['assets'] = widget.initialAssets.map(_copy).toList();
        }
      }
      final known = {
        for (final track in _records(catalog, 'tracks')) track['id']: track,
      };
      for (final track in _records(workspace, 'tracks')) {
        known.putIfAbsent(track['id'], () => track);
      }
      catalog['tracks'] = known.values.toList();
      // Profile catalogue records are canonical; ordering belongs to a release.
      workspace['tracks'] = [
        for (final track in _records(workspace, 'tracks'))
          {...track, ...known[track['id']]!},
      ];
      if (widget.syncNativeRelease) {
        workspace = ReleaseNativeBridge.mergeWorkspace(
          workspace: workspace,
          nativeTracks: widget.initialTracks,
          nativeAssets: widget.initialAssets,
          title: widget.initialTitle ?? '',
          description: widget.initialDescription,
          releaseDate: widget.initialReleaseDate,
        );
        for (final track in _records(workspace, 'tracks')) {
          known[track['id']] = track;
        }
        catalog['tracks'] = known.values.toList();
      }
      final now = DateTime.now().toUtc().toIso8601String();
      _stampChanges(workspace, persistedWorkspace, now);
      _stampChanges(catalog, _catalogBaseline!, now);
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _catalog = catalog;
        _workspaceRevision = workspace['revision'] as int? ?? 0;
        _catalogRevision = catalog['revision'] as int? ?? 0;
        _dirty = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _problems(
    Map<String, dynamic> workspace,
    Map<String, dynamic> catalog,
  ) => [
    ..._validator.validateCatalog(catalog),
    ..._validator.validate(workspace, catalog: catalog),
  ];

  void _accept(Map<String, dynamic> workspace, Map<String, dynamic> catalog) {
    // Legacy invalid records can be repaired incrementally, without allowing
    // an edit to introduce another dangling reference or invalid value.
    final before = _problems(_workspace!, _catalog!).toSet();
    final added = _problems(
      workspace,
      catalog,
    ).where((v) => !before.contains(v)).toList();
    if (added.isNotEmpty) throw FormatException(added.join('\n'));
    final now = DateTime.now().toUtc().toIso8601String();
    _stampChanges(workspace, _workspace!, now);
    _stampChanges(catalog, _catalog!, now);
    setState(() {
      _workspace = workspace;
      _catalog = catalog;
      _dirty = true;
      _error = null;
      _message = null;
    });
  }

  static void _stampChanges(
    Map<String, dynamic> value,
    Map<String, dynamic> previous,
    String now,
  ) {
    final deleted = Map<String, dynamic>.from(
      value['deleted_records'] as Map? ?? {},
    );
    for (final key in previous.keys.toSet().union(value.keys.toSet())) {
      if (value[key] is! List || previous[key] is! List) continue;
      final oldRows = <String, Map>{
        for (final row in (previous[key] as List).whereType<Map>())
          if (row['id'] is String) row['id'] as String: row,
      };
      final newIds = <String>{};
      for (final row in (value[key] as List).whereType<Map>()) {
        final id = row['id'];
        if (id is! String) continue;
        newIds.add(id);
        if (!const DeepCollectionEquality().equals(oldRows[id], row)) {
          row['updated_at'] = now;
        } else if (!row.containsKey('updated_at')) {
          // A later document save must not make an untouched legacy row newer.
          // Explicit null is an unknown clock, not an absent fallback clock.
          row['updated_at'] = previous['updated_at'];
        }
      }
      final removed = oldRows.keys.where((id) => !newIds.contains(id));
      if (removed.isNotEmpty) {
        deleted[key] = {
          ...?deleted[key] as Map?,
          for (final id in removed) id: now,
        };
      }
    }
    if (deleted.isNotEmpty) value['deleted_records'] = deleted;
  }

  Future<void> _save() async {
    if (_busy || _workspace == null || _catalog == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final errors = _problems(_workspace!, _catalog!);
      if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
      await widget.beforeSave?.call();
      final persisted = await widget.store.read(widget.releaseId);
      final actualRevision = persisted['revision'] as int? ?? 0;
      if (actualRevision != _workspaceRevision) {
        throw ReleaseRevisionConflict(_workspaceRevision, actualRevision);
      }
      await _validateOtherReleases(_catalog!);
      // If the second write fails, extra catalogue records remain harmless.
      // Never point a saved release at records that were not persisted first.
      await _catalogStore.save(_catalog!, expectedRevision: _catalogRevision);
      _catalog = await _catalogStore.read();
      _catalogRevision = _catalog!['revision'] as int;
      _catalogBaseline = _copy(_catalog!);
      await widget.store.save(
        widget.releaseId,
        _workspace!,
        expectedRevision: _workspaceRevision,
      );
      _workspace = await widget.store.read(widget.releaseId);
      _workspaceRevision = _workspace!['revision'] as int;
      await widget.onSaved?.call(_copy(_workspace!));
      if (mounted) {
        setState(() {
          _dirty = false;
          _message = l.releaseManagerSaved;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _validateOtherReleases(Map<String, dynamic> catalog) async {
    for (final releaseId in await widget.store.listReleaseIds()) {
      if (releaseId == widget.releaseId) continue;
      final other = await widget.store.read(releaseId);
      final before = _validator
          .validate(other, catalog: _catalogBaseline)
          .toSet();
      final added = _validator
          .validate(other, catalog: catalog)
          .where((error) => !before.contains(error))
          .toList();
      if (added.isNotEmpty) {
        throw StateError(
          "This record is used by release $releaseId: ${added.join('; ')}",
        );
      }
    }
  }

  Future<bool> _confirm(String title, String help, {String? action}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(help),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action ?? l.remove),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _reload() async {
    if (_dirty &&
        !await _confirm(
          l.releaseManagerLeaveQuestion,
          l.releaseManagerDiscard,
          action: l.releaseManagerDiscard,
        )) {
      return;
    }
    if (mounted) await _load();
  }

  Future<void> _importLegacy() async {
    List<PlatformFile> selection;
    try {
      selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    final path = selection.firstOrNull?.path;
    if (path == null || !mounted) return;
    if (_dirty &&
        !await _confirm(
          l.releaseManagerLeaveQuestion,
          l.releaseManagerDiscard,
          action: l.releaseManagerDiscard,
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.importLegacy(
        File(path),
        releaseId: widget.releaseId,
        destinationProfileId: widget.store.directory.uri.pathSegments
            .where((e) => e.isNotEmpty)
            .last,
        expectedRevision: _workspaceRevision,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ReleaseMetadataField> _fields(String section) {
    switch (section) {
      case 'artists':
        return [
          ReleaseMetadataField('name', l.name, required: true),
          ReleaseMetadataField('sort_name', l.releaseManagerSortName),
          ReleaseMetadataField(
            'aliases',
            l.releaseManagerAliases,
            kind: ReleaseFieldKind.stringList,
          ),
          ReleaseMetadataField(
            'roles',
            l.releaseManagerRoles,
            kind: ReleaseFieldKind.stringList,
          ),
        ];
      case 'holders':
        return [
          ReleaseMetadataField('name', l.name, required: true),
          const ReleaseMetadataField('ipi', 'IPI'),
          const ReleaseMetadataField('isni', 'ISNI'),
        ];
      case 'works':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          const ReleaseMetadataField('iswc', 'ISWC'),
        ];
      case 'playlists':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          ReleaseMetadataField(
            'track_ids',
            l.releaseManagerPlaylistTracks,
            kind: ReleaseFieldKind.references,
            choices: _options('tracks', catalog: true),
          ),
        ];
      case 'tracks':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          ReleaseMetadataField(
            'project_id',
            l.releaseManagerProject,
            kind: ReleaseFieldKind.choice,
            choices: {
              for (final project in widget.availableProjects)
                project['id'] as String: project['title'].toString(),
            },
          ),
          const ReleaseMetadataField('isrc', 'ISRC'),
          ReleaseMetadataField(
            'work_id',
            l.releaseManagerWork,
            kind: ReleaseFieldKind.choice,
            choices: _options('works', catalog: true),
          ),
        ];
      case 'assets':
        return [
          ReleaseMetadataField('title', l.title),
          ReleaseMetadataField(
            'role',
            l.releaseManagerAssetRole,
            kind: ReleaseFieldKind.choice,
            required: true,
            defaultValue: 'master',
            choices: _statuses([
              'master',
              'mix',
              'preview',
              'stem',
              'artwork',
              'lyrics',
              'midi',
              'document',
            ]),
          ),
          ReleaseMetadataField(
            'path',
            l.releaseManagerPath,
            required: true,
            kind: ReleaseFieldKind.path,
          ),
          ReleaseMetadataField(
            'track_id',
            l.releaseManagerTrack,
            kind: ReleaseFieldKind.choice,
            choices: _options('tracks'),
          ),
          ReleaseMetadataField(
            'parent_asset_id',
            l.releaseManagerParentAsset,
            kind: ReleaseFieldKind.choice,
            choices: _options('assets'),
          ),
          const ReleaseMetadataField('codec', 'Codec'),
        ];
      case 'rights_filings':
        return [
          ReleaseMetadataField(
            'organization',
            l.releaseManagerOrganization,
            required: true,
          ),
          ReleaseMetadataField(
            'work_id',
            l.releaseManagerWork,
            kind: ReleaseFieldKind.choice,
            choices: _options('works', catalog: true),
          ),
          ReleaseMetadataField(
            'status',
            l.status,
            required: true,
            kind: ReleaseFieldKind.choice,
            defaultValue: 'draft',
            choices: _statuses(ReleaseWorkflowValidator.rightsStatuses),
          ),
          ReleaseMetadataField('reference', l.releaseManagerReference),
          ReleaseMetadataField(
            'submitted_at',
            l.releaseManagerSubmittedAt,
            kind: ReleaseFieldKind.dateTime,
          ),
          ReleaseMetadataField(
            'evidence_asset_ids',
            l.releaseManagerEvidence,
            kind: ReleaseFieldKind.references,
            choices: _options('assets'),
          ),
        ];
      case 'distribution':
        return [
          ReleaseMetadataField(
            'distributor',
            l.releaseManagerDistributor,
            required: true,
          ),
          ReleaseMetadataField(
            'status',
            l.status,
            required: true,
            kind: ReleaseFieldKind.choice,
            defaultValue: 'draft',
            choices: _statuses(ReleaseWorkflowValidator.deliveryStatuses),
          ),
          const ReleaseMetadataField('upc', 'UPC / EAN'),
          ReleaseMetadataField('reference', l.releaseManagerReference),
        ];
      case 'campaigns':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          ReleaseMetadataField(
            'start_at',
            l.releaseManagerStartAt,
            kind: ReleaseFieldKind.dateTime,
          ),
          ReleaseMetadataField(
            'end_at',
            l.releaseManagerEndAt,
            kind: ReleaseFieldKind.dateTime,
          ),
          ReleaseMetadataField(
            'track_ids',
            l.releaseManagerTracks,
            kind: ReleaseFieldKind.references,
            choices: _options('tracks'),
          ),
        ];
      case 'communications':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          ReleaseMetadataField(
            'platform',
            l.releaseManagerPlatform,
            required: true,
          ),
          ReleaseMetadataField(
            'status',
            l.status,
            required: true,
            kind: ReleaseFieldKind.choice,
            defaultValue: 'planned',
            choices: _statuses(ReleaseWorkflowValidator.promotionStatuses),
          ),
          ReleaseMetadataField(
            'campaign_id',
            l.releaseManagerCampaign,
            kind: ReleaseFieldKind.choice,
            choices: _options('campaigns'),
          ),
          ReleaseMetadataField(
            'track_id',
            l.releaseManagerTrack,
            kind: ReleaseFieldKind.choice,
            choices: _options('tracks'),
          ),
          ReleaseMetadataField(
            'asset_ids',
            l.releaseManagerAssets,
            kind: ReleaseFieldKind.references,
            choices: _options('assets'),
          ),
          ReleaseMetadataField(
            'scheduled_at',
            l.releaseManagerScheduledAt,
            kind: ReleaseFieldKind.dateTime,
          ),
          ReleaseMetadataField(
            'published_at',
            l.releaseManagerPublishedAt,
            kind: ReleaseFieldKind.dateTime,
          ),
          ReleaseMetadataField('url', l.releaseManagerUrl),
          ReleaseMetadataField(
            'text',
            l.releaseManagerText,
            kind: ReleaseFieldKind.multiline,
          ),
        ];
      case 'tasks':
        return [
          ReleaseMetadataField('title', l.title, required: true),
          ReleaseMetadataField(
            'status',
            l.status,
            required: true,
            kind: ReleaseFieldKind.choice,
            defaultValue: 'todo',
            choices: _statuses(['todo', 'doing', 'done', 'blocked']),
          ),
          ReleaseMetadataField(
            'due_at',
            l.releaseManagerDueAt,
            kind: ReleaseFieldKind.date,
          ),
          ReleaseMetadataField(
            'depends_on',
            l.releaseManagerDependsOn,
            kind: ReleaseFieldKind.references,
            choices: _options('tasks'),
          ),
        ];
      default:
        throw ArgumentError.value(section);
    }
  }

  Future<void> _edit(
    String section,
    String title, {
    bool catalog = false,
    int? index,
  }) async {
    final entries = _rows(section, catalog: catalog);
    final initial = index == null
        ? <String, dynamic>{'id': const Uuid().v4()}
        : entries[index];
    final value = await showReleaseMetadataForm(
      context: context,
      title: title,
      initial: initial,
      fields: _fields(section),
    );
    if (value == null || !mounted) return;
    try {
      if (section == 'assets' &&
          (index == null || value['path'] != initial['path'])) {
        value['validation'] = 'unverified';
        for (final key in ['sha256', 'bytes', 'verified_at']) {
          value.remove(key);
        }
      }
      if (initial['status'] != value['status'] && value['status'] != null) {
        value['history'] = [
          ...?initial['history'] as List?,
          {
            'from': initial['status'],
            'to': value['status'],
            'at': DateTime.now().toUtc().toIso8601String(),
            'source': 'manual',
          },
        ];
      }
      index == null ? entries.add(value) : entries[index] = value;
      final workspace = _copy(_workspace!), library = _copy(_catalog!);
      (catalog ? library : workspace)[section] = entries;
      if (section == 'tracks') {
        final all = _records(library, 'tracks');
        final at = all.indexWhere((track) => track['id'] == value['id']);
        at < 0 ? all.add(value) : all[at] = value;
        library['tracks'] = all;
      }
      _accept(workspace, library);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _remove(
    String section,
    int index, {
    bool catalog = false,
  }) async {
    if (!await _confirm(
          l.releaseManagerRemoveQuestion,
          l.releaseManagerRemoveHelp,
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final workspace = _copy(_workspace!), library = _copy(_catalog!);
      final source = catalog ? library : workspace;
      source[section] = _records(source, section)..removeAt(index);
      if (catalog) {
        await _validateOtherReleases(library);
      }
      if (!mounted) return;
      _accept(workspace, library);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExistingTrack() async {
    final present = _rows('tracks').map((row) => row['id']).toSet();
    final choices = _options('tracks', catalog: true)
      ..removeWhere((id, _) => present.contains(id));
    final result = await showReleaseMetadataForm(
      context: context,
      title: l.releaseManagerTrack,
      initial: const {},
      fields: [
        ReleaseMetadataField(
          'id',
          l.releaseManagerTrack,
          required: true,
          kind: ReleaseFieldKind.choice,
          choices: choices,
        ),
      ],
    );
    if (result == null || !mounted) return;
    try {
      final row = _rows(
        'tracks',
        catalog: true,
      ).firstWhere((row) => row['id'] == result['id']);
      _accept({
        ..._workspace!,
        'tracks': [..._rows('tracks'), row],
      }, _copy(_catalog!));
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _moveTrack(int from, int to) {
    final tracks = _rows('tracks');
    tracks.insert(to, tracks.removeAt(from));
    _accept({..._workspace!, 'tracks': tracks}, _copy(_catalog!));
  }

  Future<void> _verifyAsset(int index) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final assets = _rows('assets');
      final verified = await ReleaseAssetVerifier().verify(assets[index]);
      if (!mounted) return;
      assets[index] = verified;
      _accept({..._workspace!, 'assets': assets}, _copy(_catalog!));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ReleaseMetadataField> _nestedFields(String key) {
    switch (key) {
      case 'shares':
        return [
          ReleaseMetadataField(
            'holder_id',
            l.releaseManagerHolder,
            required: true,
            kind: ReleaseFieldKind.choice,
            choices: _options('holders', catalog: true),
          ),
          ReleaseMetadataField('role', l.releaseManagerRole, required: true),
          ReleaseMetadataField(
            'percentage',
            l.releaseManagerPercentage,
            kind: ReleaseFieldKind.number,
            required: true,
          ),
        ];
      case 'credits':
        return [
          ReleaseMetadataField(
            'artist_id',
            l.releaseManagerArtist,
            required: true,
            kind: ReleaseFieldKind.choice,
            choices: _options('artists', catalog: true),
          ),
          ReleaseMetadataField('role', l.releaseManagerRole, required: true),
        ];
      case 'platforms':
        return [
          ReleaseMetadataField(
            'platform',
            l.releaseManagerPlatform,
            required: true,
          ),
          ReleaseMetadataField(
            'status',
            l.status,
            required: true,
            defaultValue: 'draft',
            kind: ReleaseFieldKind.choice,
            choices: _statuses(ReleaseWorkflowValidator.deliveryStatuses),
          ),
          ReleaseMetadataField('url', l.releaseManagerUrl),
          ReleaseMetadataField(
            'published_at',
            l.releaseManagerPublishedAt,
            kind: ReleaseFieldKind.dateTime,
          ),
        ];
      default:
        throw ArgumentError.value(key);
    }
  }

  Future<void> _nested(
    String section,
    int index,
    String key,
    String title, {
    bool catalog = false,
  }) async {
    final parent = _rows(section, catalog: catalog)[index];
    final initial = _records(parent, key);
    final values = initial.map(_copy).toList();
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var row = 0; row < values.length; row++)
                      ListTile(
                        title: Text(_nestedTitle(key, values[row])),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: l.edit,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final value = await showReleaseMetadataForm(
                                  context: context,
                                  title: title,
                                  initial: values[row],
                                  fields: _nestedFields(key),
                                );
                                if (value != null && context.mounted) {
                                  updateDialog(() => values[row] = value);
                                }
                              },
                            ),
                            IconButton(
                              tooltip: l.remove,
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () =>
                                  updateDialog(() => values.removeAt(row)),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(l.add),
                      onPressed: () async {
                        final value = await showReleaseMetadataForm(
                          context: context,
                          title: title,
                          initial: {'id': const Uuid().v4()},
                          fields: _nestedFields(key),
                        );
                        if (value != null && context.mounted) {
                          updateDialog(() => values.add(value));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, values),
                child: Text(l.apply),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    try {
      final workspace = _copy(_workspace!), library = _copy(_catalog!);
      final target = catalog ? library : workspace,
          parents = _records(catalog ? library : workspace, section);
      if (key == 'platforms') {
        for (final value in result) {
          final prior = initial
              .where((row) => row['id'] == value['id'])
              .firstOrNull;
          if (prior?['status'] != value['status'] && value['status'] != null) {
            value['history'] = [
              ...?prior?['history'] as List?,
              {
                'from': prior?['status'],
                'to': value['status'],
                'at': DateTime.now().toUtc().toIso8601String(),
                'source': 'manual',
              },
            ];
          }
        }
      }
      parents[index][key] = result;
      target[section] = parents;
      if (section == 'tracks') {
        final all = _records(library, 'tracks');
        final at = all.indexWhere((t) => t['id'] == parents[index]['id']);
        if (at >= 0) all[at] = parents[index];
        library['tracks'] = all;
      }
      _accept(workspace, library);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  String _nestedTitle(String key, Map<String, dynamic> row) {
    if (key == 'shares') {
      return '${_options('holders', catalog: true)[row['holder_id']] ?? row['holder_id'].toString()} · ${row['role']} · ${row['percentage']}%';
    }
    if (key == 'credits') {
      return '${_options('artists', catalog: true)[row['artist_id']] ?? row['artist_id'].toString()} · ${row['role']}';
    }
    return '${row['platform']} · ${row['status']}';
  }

  Widget _playlistOrder(int index, Map<String, dynamic> record) {
    final ids = List<String>.from(record['track_ids'] as List? ?? []),
        names = _options('tracks', catalog: true);
    return Column(
      children: [
        for (var position = 0; position < ids.length; position++)
          ListTile(
            dense: true,
            title: Text(
              '${position + 1}. ${names[ids[position]] ?? ids[position]}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: l.releaseManagerMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _busy || position == 0
                      ? null
                      : () => _movePlaylist(index, position, position - 1),
                ),
                IconButton(
                  tooltip: l.releaseManagerMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: _busy || position == ids.length - 1
                      ? null
                      : () => _movePlaylist(index, position, position + 1),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _movePlaylist(int index, int from, int to) {
    final library = _copy(_catalog!), rows = _rows('playlists', catalog: true);
    final ids = List<String>.from(rows[index]['track_ids'] as List);
    ids.insert(to, ids.removeAt(from));
    rows[index]['track_ids'] = ids;
    library['playlists'] = rows;
    _accept(_copy(_workspace!), library);
  }

  Widget _history(Map<String, dynamic> row) {
    final history = row['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      dense: true,
      title: Text(l.releaseManagerHistory),
      children: [
        for (final item in history.whereType<Map>())
          ListTile(
            dense: true,
            title: Text('${item['from'] ?? '—'} → ${item['to']}'),
            subtitle: Text(item['at'].toString()),
          ),
      ],
    );
  }

  Widget _section(
    String section,
    String title,
    IconData icon, {
    bool catalog = false,
  }) {
    final rows = _rows(section, catalog: catalog);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ExpansionTile(
        key: ValueKey('section-$section'),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(rows.length.toString()),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          if (rows.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.releaseManagerEmpty),
            ),
          for (var index = 0; index < rows.length; index++)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (rows[index]['name'] ??
                            rows[index]['title'] ??
                            rows[index]['organization'] ??
                            rows[index]['distributor'] ??
                            rows[index]['path'] ??
                            rows[index]['id'])
                        .toString(),
                  ),
                  subtitle: Text(
                    [
                      if (rows[index]['status'] != null) rows[index]['status'],
                      if (rows[index]['isrc'] != null) rows[index]['isrc'],
                      if (rows[index]['validation'] != null)
                        rows[index]['validation'],
                    ].join(' · '),
                  ),
                  trailing: Wrap(
                    children: [
                      if (section == 'tracks') ...[
                        IconButton(
                          tooltip: l.releaseManagerMoveUp,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _busy || index == 0
                              ? null
                              : () => _moveTrack(index, index - 1),
                        ),
                        IconButton(
                          tooltip: l.releaseManagerMoveDown,
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: _busy || index == rows.length - 1
                              ? null
                              : () => _moveTrack(index, index + 1),
                        ),
                      ],
                      IconButton(
                        tooltip: l.edit,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy
                            ? null
                            : () => _edit(
                                section,
                                title,
                                catalog: catalog,
                                index: index,
                              ),
                      ),
                      IconButton(
                        tooltip: l.remove,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _busy
                            ? null
                            : () => _remove(section, index, catalog: catalog),
                      ),
                    ],
                  ),
                ),
                if (section == 'works')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _nested(
                            section,
                            index,
                            'shares',
                            l.releaseManagerShares,
                            catalog: true,
                          ),
                    child: Text(
                      '${l.releaseManagerShares} (${(rows[index]['shares'] as List?)?.length ?? 0})',
                    ),
                  ),
                if (section == 'tracks')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _nested(
                            section,
                            index,
                            'credits',
                            l.releaseManagerCredits,
                          ),
                    child: Text(
                      '${l.releaseManagerCredits} (${(rows[index]['credits'] as List?)?.length ?? 0})',
                    ),
                  ),
                if (section == 'distribution')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _nested(
                            section,
                            index,
                            'platforms',
                            l.releaseManagerPlatforms,
                          ),
                    child: Text(
                      '${l.releaseManagerPlatforms} (${(rows[index]['platforms'] as List?)?.length ?? 0})',
                    ),
                  ),
                if (section == 'assets')
                  TextButton.icon(
                    onPressed: _busy ? null : () => _verifyAsset(index),
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(l.releaseManagerVerify),
                  ),
                if (section == 'playlists') _playlistOrder(index, rows[index]),
                _history(rows[index]),
                const Divider(),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: ValueKey('add-$section'),
                icon: const Icon(Icons.add),
                label: Text(l.add),
                onPressed: _busy
                    ? null
                    : () => _edit(section, title, catalog: catalog),
              ),
              if (section == 'tracks')
                TextButton.icon(
                  key: const ValueKey('reuse-track'),
                  icon: const Icon(Icons.library_music_outlined),
                  onPressed: _busy ? null : _addExistingTrack,
                  label: Text(l.releaseManagerPlaylistTracks),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calendar() {
    final posts =
        _rows('communications')
            .where(
              (row) =>
                  row['scheduled_at'] != null || row['published_at'] != null,
            )
            .toList()
          ..sort(
            (a, b) => (a['scheduled_at'] ?? a['published_at'])
                .toString()
                .compareTo((b['scheduled_at'] ?? b['published_at']).toString()),
          );
    return Card(
      child: ExpansionTile(
        key: const ValueKey('promotion-calendar'),
        leading: const Icon(Icons.calendar_month),
        title: Text(l.releaseManagerCalendar),
        children: [
          if (posts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.releaseManagerEmpty),
            ),
          for (final row in posts)
            ListTile(
              title: Text(row['title'].toString()),
              subtitle: Text(
                '${row['platform']} · ${DateTime.tryParse((row['scheduled_at'] ?? row['published_at']).toString())?.toLocal().toString() ?? ''} · ${row['status']}',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editSummary() async {
    final result = await showReleaseMetadataForm(
      context: context,
      title: l.releaseManagerWorkflow,
      initial: _workspace!,
      fields: [
        ReleaseMetadataField(
          'title',
          l.title,
          required: widget.syncNativeRelease,
        ),
        ReleaseMetadataField(
          'description',
          l.description,
          kind: ReleaseFieldKind.multiline,
        ),
        ReleaseMetadataField(
          'release_date',
          l.releaseManagerReleaseDate,
          kind: ReleaseFieldKind.date,
        ),
        const ReleaseMetadataField('upc', 'UPC / EAN'),
        ReleaseMetadataField(
          'artist_ids',
          l.releaseManagerSelectedArtists,
          kind: ReleaseFieldKind.references,
          choices: _options('artists', catalog: true),
        ),
      ],
    );
    if (result == null || !mounted) return;
    try {
      _accept(result, _copy(_catalog!));
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _workspace != null && _catalog != null;
    final evaluation = ready
        ? ReleaseWorkflowEngine().evaluate(_workspace!, catalog: _catalog)
        : null;
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_dirty || _busy) return;
        if (await _confirm(
              l.releaseManagerLeaveQuestion,
              l.releaseManagerDiscard,
              action: l.releaseManagerDiscard,
            ) &&
            context.mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.releaseManagerIntro),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText(
              _error!,
              key: const ValueKey('release-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_message != null)
            Text(_message!, key: const ValueKey('release-message')),
          if (ready) ...[
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('save-workspace'),
                  icon: const Icon(Icons.save_outlined),
                  onPressed: _busy ? null : _save,
                  label: Text(
                    _busy ? l.releaseManagerSaving : l.releaseManagerSave,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: Text(l.releaseManagerReload),
                ),
                if (_dirty) Text(l.releaseManagerUnsaved),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('release-type-${_workspace!['collection_type']}'),
              initialValue:
                  const {
                    'album',
                    'ep',
                    'single',
                    'compilation',
                    'playlist',
                  }.contains(_workspace!['collection_type'])
                  ? _workspace!['collection_type'] as String
                  : null,
              decoration: InputDecoration(
                labelText: l.releaseManagerCollectionType,
              ),
              items: [
                for (final entry in const {
                  'album': 'Album',
                  'ep': 'EP',
                  'single': 'Single',
                  'compilation': 'Compilation',
                  'playlist': 'Playlist',
                }.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        _accept({
                          ..._workspace!,
                          'collection_type': value,
                        }, _copy(_catalog!));
                      }
                    },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                (_workspace!['title'] ?? l.releaseManagerWorkflow).toString(),
              ),
              subtitle: Text(
                ((_workspace!['artist_ids'] as List?) ?? [])
                    .map(
                      (id) =>
                          _options('artists', catalog: true)[id] ??
                          '${l.releaseManagerUnexpectedStatus}: $id',
                    )
                    .join(', '),
              ),
              trailing: IconButton(
                key: const ValueKey('edit-release-summary'),
                tooltip: l.edit,
                onPressed: _busy ? null : _editSummary,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (evaluation != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.releaseManagerCoverage,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(evaluation.nextAction),
                      if (evaluation.tracksWithoutPromotion.isNotEmpty)
                        Text(
                          '${l.releaseManagerUnpromoted}: ${evaluation.tracksWithoutPromotion.map((id) => _options('tracks')[id] ?? id).join(', ')}',
                        ),
                      for (final issue in evaluation.issues)
                        Text(issue.message),
                    ],
                  ),
                ),
              ),
            _section(
              'artists',
              l.releaseManagerArtists,
              Icons.person_outline,
              catalog: true,
            ),
            _section(
              'tracks',
              l.releaseManagerTracks,
              Icons.music_note_outlined,
            ),
            _section(
              'playlists',
              l.releaseManagerPlaylists,
              Icons.queue_music,
              catalog: true,
            ),
            _section(
              'assets',
              l.releaseManagerAssets,
              Icons.audio_file_outlined,
            ),
            _section(
              'holders',
              l.releaseManagerHolders,
              Icons.groups_outlined,
              catalog: true,
            ),
            _section(
              'works',
              l.releaseManagerWorks,
              Icons.library_books_outlined,
              catalog: true,
            ),
            _section(
              'rights_filings',
              l.releaseManagerFilings,
              Icons.verified_user_outlined,
            ),
            _section(
              'distribution',
              l.releaseManagerDistribution,
              Icons.store_outlined,
            ),
            _section(
              'campaigns',
              l.releaseManagerCampaigns,
              Icons.campaign_outlined,
            ),
            _section(
              'communications',
              l.releaseManagerCommunications,
              Icons.forum_outlined,
            ),
            _calendar(),
            _section('tasks', l.releaseManagerTasks, Icons.checklist),
            TextButton.icon(
              onPressed: _busy ? null : _importLegacy,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l.releaseManagerImportLegacy),
            ),
          ] else if (!_busy)
            TextButton(onPressed: _load, child: Text(l.releaseManagerReload)),
        ],
      ),
    );
  }
}
