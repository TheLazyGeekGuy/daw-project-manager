import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  LegacyCubaseValidation? _intermediateValidation;
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
      _intermediateValidation = null;
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

  Future<void> _chooseDawProject() async {
    final preparation = _preparation;
    if (preparation == null) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['dawproject'],
    );
    if (selected == null || selected.files.single.path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _intermediateValidation = null;
    });
    try {
      final verified = await LegacyCubaseMigration.validateDawProject(
        preparation, File(selected.files.single.path!),
      );
      if (!mounted) return;
      setState(() => _intermediateValidation = verified);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'DAWproject inspection failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openConverter() async {
    try {
      final opened = await launchUrl(
        Uri.parse(LegacyCubaseMigration.atariConverter),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error = 'Could not open the converter website');
      }
    } catch (error) {
      if (mounted) setState(
        () => _error = 'Could not open converter: $error',
      );
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
            Text('Two independent paths are available. '
              'Neither can certify native plug-in presets or mix fidelity.'),
            const SizedBox(height: 12),
            Text('Route A: official Cubase 3 import',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Use licensed Cubase SE/SL/SX 3: File > Import > Cubase Song, '
              'then save a separate CPR. Steinberg documents losses to VST '
              'instruments, effects and mixer settings.',
            ),
            const SelectableText(
              LegacyCubaseMigration.steinbergGuide,
            ),
            const SizedBox(height: 12),
            Text('Route B: Atari conversion without Cubase 3',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'atari2cubase converts classic Atari ALL/ARR to DAWproject '
              '(or MIDI). This third-party web converter is not bundled in '
              'DPM; support for Cubase VST PC songs is experimental. '
              'Download the file yourself, then import DAWproject into '
              'Cubase/Nuendo 14+ and save as CPR.',
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openConverter,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open atari2cubase in browser'),
            ),
            const Text(
              'Author states files are processed locally in the browser. '
              'DPM has not independently audited this third-party website.',
            ),
            const SizedBox(height: 12),
            Text('Known official-route losses',
                style: Theme.of(context).textTheme.titleSmall),
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
                '2A. Legacy official route: import with Cubase SE/SL/SX 3 '
                'and save a separate CPR.',
              ),
              const SizedBox(height: 8),
              const Text(
                '2B. Modern route: convert using atari2cubase, '
                'download the DAWproject, then select it below.',
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDawProject,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Check intermediate DAWproject'),
              ),
              if (_intermediateValidation case final intermediate?) ...[
                const Text(
                  'DAWproject ZIP signature recognized. Musical content '
                  'and import fidelity have not been verified.',
                ),
                Text('Format: ${intermediate.converted.formatId}'),
                const Text(
                  'Import it into Cubase/Nuendo 14+ using File > Import > '
                  'DAWproject, then save a new CPR.',
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseConverted,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('3. Check resulting CPR (either route)'),
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
