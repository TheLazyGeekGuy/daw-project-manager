import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/project_repair/legacy_cubase_migration.dart';

/// Guides a licensed Cubase 3 conversion; DPM does not translate ALL/ARR.
class LegacyCubaseMigrationDialog extends StatefulWidget {
  const LegacyCubaseMigrationDialog({super.key});

  @override
  State<LegacyCubaseMigrationDialog> createState() =>
      _LegacyCubaseMigrationDialogState();
}

class _LegacyCubaseMigrationDialogState
    extends State<LegacyCubaseMigrationDialog> {
  LegacyCubasePreparation? _preparation;
  LegacyCubaseValidation? _validation;
  bool _busy = false;
  String? _error;

  Future<void> _chooseLegacy() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['all', 'arr'],
    );
    if (selected == null || selected.files.single.path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
      _preparation = null;
    });
    try {
      final prep = await LegacyCubaseMigration.prepare(
        File(selected.files.single.path!),
      );
      if (!mounted) return;
      setState(() => _preparation = prep);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Cannot prepare legacy project: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseConverted() async {
    final preparation = _preparation;
    if (preparation == null) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cpr'],
    );
    if (selected == null || selected.files.single.path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
    });
    try {
      final verified = await LegacyCubaseMigration.validate(
        preparation, File(selected.files.single.path!),
      );
      if (!mounted) return;
      setState(() => _validation = verified);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'CPR validation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Classic Cubase migration (.ALL/.ARR)'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Official method: use Cubase SE 3 (recommended), SL 3 or SX 3 '
              'with a compatible licence. Import via File > Import > Cubase '
              'Song, then save as CPR in a new folder with all audio assets.',
            ),
            const SizedBox(height: 10),
            const SelectableText(
              LegacyCubaseMigration.steinbergGuide,
            ),
            const SizedBox(height: 12),
            const Text(
              'Important: Steinberg reports that the official migration '
              'preserves audio/MIDI parts but loses original VST instruments, '
              'VST effects and mixer settings. DPM cannot recover them.',
            ),
            for (final issue in LegacyCubaseMigration.documentedLossRisks)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $issue'),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseLegacy,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('1. Choose .ALL / .ARR and verify backup'),
            ),
            if (_preparation case final preparation?) ...[
              SelectableText('Legacy source: ${preparation.legacyPath}'),
              SelectableText('SHA-256: ${preparation.legacySha256}'),
              SelectableText('Verified backup: ${preparation.backupPath}'),
              const SizedBox(height: 10),
              const Text(
                '2. Open the legacy file manually with compatible Cubase 3. '
                'Use Save Project to New Folder to gather audio. '
                'Do not overwrite the source.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseConverted,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('3. Check the resulting .CPR'),
              ),
            ],
            if (_validation case final validation?) ...[
              const SizedBox(height: 8),
              const Text('CPR structure recognized; NOT certified lossless.'),
              Text('Cubase version: ${validation.converted.savedDawVersion ?? "unknown"}'),
              Text('Tracks decoded: ${validation.converted.trackCount ?? 0}'),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              )),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}
