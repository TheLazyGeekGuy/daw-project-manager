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
