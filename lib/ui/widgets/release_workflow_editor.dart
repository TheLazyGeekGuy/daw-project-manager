import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/release_workflow_validator.dart';
import '../../services/release_record_editor.dart';
import '../../services/release_workspace_store.dart';

/// A native, manual metadata editor; no Katsu or distributor API connection.
///
/// Fields are JSON until the domain-specific form migrations are completed.
class ReleaseWorkflowEditor extends StatefulWidget {
  const ReleaseWorkflowEditor({
    super.key,
    required this.releaseId,
    required this.store,
  });

  final String releaseId;
  final ReleaseWorkspaceStore store;

  @override
  State<ReleaseWorkflowEditor> createState() => _ReleaseWorkflowEditorState();
}

class _ReleaseWorkflowEditorState extends State<ReleaseWorkflowEditor> {
  final _controller = TextEditingController();
  final _validator = const ReleaseWorkflowValidator();
  String _collectionType = 'album';
  final _artistController = TextEditingController();
  bool _advancedJson = false;
  final _organization = TextEditingController();
  final _rightsStatus = TextEditingController(text: 'draft');
  final _distributor = TextEditingController();
  final _deliveryStatus = TextEditingController(text: 'draft');
  final _promotionPlatform = TextEditingController();
  final _promotionStatus = TextEditingController(text: 'planned');
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _next;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.store.read(widget.releaseId);
      if (!mounted) return;
      setState(() {
        _controller.text = const JsonEncoder.withIndent('  ').convert(data);
        _collectionType = data['collection_type'] as String? ?? 'album';
        _artistController.text = ((data['artist_ids'] as List?) ?? []).join(', ');
        final rights = (data['rights_filings'] as List?) ?? [];
        final distribution = (data['distribution'] as List?) ?? [];
        final communication = (data['communications'] as List?) ?? [];
        if (rights.isNotEmpty && rights.first is Map) {
          _organization.text = rights.first['organization']?.toString() ?? '';
          _rightsStatus.text = rights.first['status']?.toString() ?? 'draft';
        }
        if (distribution.isNotEmpty && distribution.first is Map) {
          _distributor.text = distribution.first['distributor']?.toString() ?? '';
          _deliveryStatus.text = distribution.first['status']?.toString() ?? 'draft';
        }
        if (communication.isNotEmpty && communication.first is Map) {
          _promotionPlatform.text = communication.first['platform']?.toString() ?? '';
          _promotionStatus.text = communication.first['status']?.toString() ?? 'planned';
        }
        _next = _validator.nextSuggestedStep(data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load release metadata: $error';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final data = jsonDecode(_controller.text);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Root must be a JSON object');
      }
      if (!_advancedJson) {
        data['collection_type'] = _collectionType;
        data['artist_ids'] = _artistController.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
        void updateFirst(String key, Map<String, String> values, String primary) {
          final entries = List<dynamic>.from((data[key] as List?) ?? []);
          if (values[primary]!.isNotEmpty) {
            if (entries.isEmpty) entries.add(<String, dynamic>{});
            if (entries.first is! Map) throw FormatException('Invalid $key entry');
            entries[0] = {...Map<String, dynamic>.from(entries.first as Map), ...values};
            data[key] = entries;
          }
        }
        updateFirst('rights_filings', {'organization': _organization.text.trim(), 'status': _rightsStatus.text.trim()}, 'organization');
        updateFirst('distribution', {'distributor': _distributor.text.trim(), 'status': _deliveryStatus.text.trim()}, 'distributor');
        updateFirst('communications', {'platform': _promotionPlatform.text.trim(), 'status': _promotionStatus.text.trim()}, 'platform');
      }
      final problems = _validator.validate(data);
      if (problems.isNotEmpty) {
        throw FormatException(problems.join('; '));
      }
      await widget.store.save(widget.releaseId, data);
      _controller.text = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      setState(() => _next = _validator.nextSuggestedStep(data));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Cannot save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _editEntry(String section, [int? index]) async {
    final fields = ReleaseRecordEditor.sections[section]!;
    final source = jsonDecode(_controller.text) as Map<String, dynamic>;
    final entries = (source[section] as List?) ?? [];
    final entry = index == null ? <String, dynamic>{} :
        Map<String, dynamic>.from(entries[index] as Map);
    final name = TextEditingController(text: entry[fields.$1]?.toString() ?? '');
    final existing = entry[fields.$2]?.toString() ?? '';
    final statuses = section == 'rights_filings'
        ? ReleaseWorkflowValidator.rightsStatuses
        : section == 'distribution'
            ? ReleaseWorkflowValidator.deliveryStatuses
            : ReleaseWorkflowValidator.promotionStatuses;
    String selected = statuses.contains(existing) ? existing :
        section == 'communications' ? 'planned' : 'draft';
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Add record' : 'Edit record'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(
                labelText: fields.$1,
              )),
              DropdownButtonFormField<String>(
                value: selected,
                items: [
                  for (final status in statuses)
                    DropdownMenuItem(value: status, child: Text(status)),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => selected = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, {
              fields.$1: name.text.trim(),
              fields.$2: selected,
            }), child: const Text('Apply')),
          ],
        ),
      ),
    );
    name.dispose();
    if (values == null || !mounted) return;
    try {
      final changed = ReleaseRecordEditor.update(source, section, index, values);
      setState(() {
        _controller.text = const JsonEncoder.withIndent('  ').convert(changed);
        _syncFirst(changed);
        _error = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _syncFirst(Map<String, dynamic> source) {
    void sync(String key, TextEditingController name,
        TextEditingController status, String label) {
      final values = (source[key] as List?) ?? [];
      final first = values.isEmpty ? null : values.first as Map?;
      name.text = first?[label]?.toString() ?? '';
      status.text = first?['status']?.toString() ??
          (key == 'communications' ? 'planned' : 'draft');
    }
    sync('rights_filings', _organization, _rightsStatus, 'organization');
    sync('distribution', _distributor, _deliveryStatus, 'distributor');
    sync('communications', _promotionPlatform, _promotionStatus, 'platform');
  }

  void _removeEntry(String section, int index) {
    try {
      final source = jsonDecode(_controller.text) as Map<String, dynamic>;
      final changed = ReleaseRecordEditor.remove(source, section, index);
      setState(() {
        _controller.text = const JsonEncoder.withIndent('  ').convert(changed);
        _syncFirst(changed);
        _error = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Widget _sectionRecords(String section) {
    final fields = ReleaseRecordEditor.sections[section]!;
    final data = jsonDecode(_controller.text) as Map<String, dynamic>;
    final entries = (data[section] as List?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < entries.length; index++)
          ListTile(
            dense: true,
            title: Text((entries[index] as Map)[fields.$1]?.toString() ?? ''),
            subtitle: Text((entries[index] as Map)['status']?.toString() ?? ''),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Edit record',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editEntry(section, index),
              ),
              IconButton(
                tooltip: 'Remove record',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _removeEntry(section, index),
              ),
            ]),
          ),
        TextButton.icon(
          onPressed: () => _editEntry(section),
          icon: const Icon(Icons.add),
          label: Text('Add ${fields.$1}'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _artistController.dispose();
    for (final controller in [_organization, _rightsStatus, _distributor, _deliveryStatus, _promotionPlatform, _promotionStatus]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Release workflow', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text(
        'Native DPM metadata: artists, tracks, rights, distribution and promotion. '
        'No automatic external submissions are performed.',
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_next != null) Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Suggested next step: $_next'),
      ),
      if (_error != null) Text(_error!, style: TextStyle(
        color: Theme.of(context).colorScheme.error,
      )),
      if (!_loading) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _collectionType,
          decoration: const InputDecoration(labelText: 'Release type'),
          items: const [
            DropdownMenuItem(value: 'album', child: Text('Album')),
            DropdownMenuItem(value: 'ep', child: Text('EP')),
            DropdownMenuItem(value: 'single', child: Text('Single')),
            DropdownMenuItem(value: 'compilation', child: Text('Compilation')),
            DropdownMenuItem(value: 'playlist', child: Text('Playlist')),
          ],
          onChanged: _advancedJson ? null : (value) {
            if (value != null) setState(() => _collectionType = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _artistController,
          enabled: !_advancedJson,
          decoration: const InputDecoration(
            labelText: 'Artist IDs',
            helperText: 'Comma-separated stable identifiers; titles are not IDs.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Rights filing', style: Theme.of(context).textTheme.titleSmall),
        TextField(controller: _organization, enabled: !_advancedJson,
          decoration: const InputDecoration(labelText: 'Rights organization (e.g. SACEM, BMI, PRS)')),
        DropdownButtonFormField<String>(
          value: ReleaseWorkflowValidator.rightsStatuses.contains(_rightsStatus.text)
              ? _rightsStatus.text : 'draft',
          decoration: const InputDecoration(labelText: 'Rights filing status'),
          items: ReleaseWorkflowValidator.rightsStatuses
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: _advancedJson ? null : (value) {
            if (value != null) setState(() => _rightsStatus.text = value);
          },
        ),
        const SizedBox(height: 12),
        Text('Distribution', style: Theme.of(context).textTheme.titleSmall),
        TextField(controller: _distributor, enabled: !_advancedJson,
          decoration: const InputDecoration(labelText: 'Distributor')),
        DropdownButtonFormField<String>(
          value: ReleaseWorkflowValidator.deliveryStatuses.contains(_deliveryStatus.text)
              ? _deliveryStatus.text : 'draft',
          decoration: const InputDecoration(labelText: 'Delivery status'),
          items: ReleaseWorkflowValidator.deliveryStatuses
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: _advancedJson ? null : (value) {
            if (value != null) setState(() => _deliveryStatus.text = value);
          },
        ),
        const SizedBox(height: 12),
        Text('Communication', style: Theme.of(context).textTheme.titleSmall),
        TextField(controller: _promotionPlatform, enabled: !_advancedJson,
          decoration: const InputDecoration(labelText: 'Promotion platform')),
        DropdownButtonFormField<String>(
          value: ReleaseWorkflowValidator.promotionStatuses.contains(_promotionStatus.text)
              ? _promotionStatus.text : 'planned',
          decoration: const InputDecoration(labelText: 'Promotion status'),
          items: ReleaseWorkflowValidator.promotionStatuses
              .map((status) => DropdownMenuItem(value: status, child: Text(status)))
              .toList(),
          onChanged: _advancedJson ? null : (value) {
            if (value != null) setState(() => _promotionStatus.text = value);
          },
        ),
        const Divider(),
        _sectionRecords('rights_filings'),
        _sectionRecords('distribution'),
        _sectionRecords('communications'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Advanced JSON editor'),
          subtitle: const Text('Edit tracks, rights filings, distribution and communication details.'),
          value: _advancedJson,
          onChanged: (value) => setState(() => _advancedJson = value),
        ),
        if (_advancedJson)
          TextField(
            controller: _controller,
            minLines: 8,
            maxLines: 18,
            decoration: const InputDecoration(
              labelText: 'Release workflow JSON',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Validate and save'),
        ),
      ],
    ],
  );
}
