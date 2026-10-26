import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/release_workflow_validator.dart';
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
      }
      final problems = _validator.validate(data);
      if (problems.isNotEmpty) {
        throw FormatException(problems.join('; '));
      }
      await widget.store.save(widget.releaseId, data);
      if (!mounted) return;
      setState(() => _next = _validator.nextSuggestedStep(data));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Cannot save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _artistController.dispose();
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
