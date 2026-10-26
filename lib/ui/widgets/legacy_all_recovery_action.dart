import 'dart:io';
import 'dart:isolate';
import 'package:material_ui/material_ui.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';
import '../../services/project_repair/legacy_all_conversion_service.dart';

// Build the worker closure outside State so its captured context contains
// only the path, never widget elements, callbacks or the Flutter test zone.
Future<Map<String, Object?>> _recoverLegacyAllInBackground(String path) =>
    Isolate.run(
      () => LegacyAllConversionService.convert(
        original: File(path),
        acknowledgeFidelityRisks: true,
      ),
    );

/// Native DPM action. Heavy parsing runs outside the Flutter UI isolate.
class LegacyAllRecoveryAction extends StatefulWidget {
  const LegacyAllRecoveryAction({super.key, required this.path, this.recover});
  final String path;
  final Future<Map<String, Object?>> Function(String path)? recover;
  @override
  State<LegacyAllRecoveryAction> createState() =>
      _LegacyAllRecoveryActionState();
}

class _LegacyAllRecoveryActionState extends State<LegacyAllRecoveryAction> {
  bool _busy = false;
  Map<String, Object?>? _result;
  String? _error;
  AppLocalizations get l =>
      AppLocalizations.of(context) ?? AppLocalizationsEn();
  Future<void> _run() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.projectRepairRecoveryTitle),
        content: Text(l.projectRepairRecoveryConsent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.projectRepairRecoverAction),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final path = widget.path;
      final result = widget.recover != null
          ? await widget.recover!(path)
          : await _recoverLegacyAllInBackground(path);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.projectRepairNativeAllHint),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.music_note),
            label: Text(
              _busy ? l.projectRepairWorking : l.projectRepairRecoverMidi,
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText([l.projectRepairFailed, _error!].join('\n')),
          if (_result != null) ...[
            Text(l.projectRepairRecoveryCreated),
            Text(
              _result!['status'] == 'partial_recovery_unverified'
                  ? l.projectRepairPartialRecovery
                  : l.projectRepairUnverifiedRecovery,
            ),
            SelectableText(
              [
                l.projectRepairRecoveryStatus,
                _result!['status']?.toString() ?? 'unknown',
              ].join(': '),
              key: const ValueKey('recovery-status'),
            ),
            Text(
              [
                l.projectRepairRecoveredTracks,
                _result!['track_count']?.toString() ?? '?',
              ].join(': '),
              key: const ValueKey('recovery-track-count'),
            ),
            Text(
              [
                l.projectRepairRecoveredNotes,
                _result!['note_count']?.toString() ?? '?',
              ].join(': '),
              key: const ValueKey('recovery-note-count'),
            ),
            Text(
              [
                l.projectRepairSkippedParts,
                _result!['skipped_parts']?.toString() ?? '?',
              ].join(': '),
              key: const ValueKey('recovery-skipped-parts'),
            ),
            SelectableText(_result!['output'].toString()),
            SelectableText(_result!['report'].toString()),
            for (final limitation
                in _result!['limitations'] as List? ?? const [])
              Text(limitation.toString()),
          ],
        ],
      ),
    ),
  );
}
