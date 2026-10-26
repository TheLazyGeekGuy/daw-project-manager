import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/project_repair/legacy_cubase_migration.dart';
import '../../services/project_repair/all_to_midi_bridge.dart';
import '../../services/project_repair/native_legacy_all_conversion.dart';
import '../../services/project_repair/native_legacy_all_reader.dart';

/// Offers licensed/manual legacy routes and a guarded Windows AllToMidi CLI.
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
  AllToMidiConversionResult? _allToMidiResult;
  NativeLegacyAllResult? _nativeResult;
  LegacyAllSong? _nativePreview;
  String? _nativePreviewError;
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
      _allToMidiResult = null;
      _nativeResult = null;
      _nativePreview = null;
      _nativePreviewError = null;
      _preparation = null;
    });
    try {
      final prep = await LegacyCubaseMigration.prepare(
        File(selected.files.single.path!),
      );
      if (!mounted) return;
      setState(() => _preparation = prep);
      if (prep.legacyPath.toLowerCase().endsWith('.all')) {
        try {
          final backupPath = prep.backupPath;
          final parsed = await Isolate.run(() async {
            final input = await File(backupPath).readAsBytes();
            return const NativeLegacyAllReader().read(input);
          });
          if (mounted) setState(() => _nativePreview = parsed);
        } catch (error) {
          if (mounted) {
            setState(() => _nativePreviewError =
                'This ALL variant is not recognized by the native reader: $error');
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Cannot prepare legacy project: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertNatively() async {
    final preparation = _preparation;
    if (_busy || preparation == null ||
        !preparation.legacyPath.toLowerCase().endsWith('.all')) return;
    if (_nativePreview == null) {
      setState(() => _error =
          'This ALL layout is not recognized. No unverified MIDI will be written.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Native .ALL MIDI recovery'),
        content: const Text(
          'DPM will produce a new MIDI file without Cubase 3 or an external '
          'executable. This is experimental: audio, VST instruments, presets, '
          'mixer states and SysEx are not recovered, and later tempo changes '
          'may be incomplete. Your original and verified backup stay intact.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate MIDI copy')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _nativeResult = null;
    });
    try {
      final sourcePath = preparation.legacyPath;
      final result = await Isolate.run(() =>
          const NativeLegacyAllConversion().convert(
            original: File(sourcePath),
          ));
      if (!mounted) return;
      setState(() => _nativeResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = 'Native MIDI recovery failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertWithAllToMidi() async {
    final preparation = _preparation;
    if (preparation == null || _busy || !Platform.isWindows) return;
    if (!preparation.legacyPath.toLowerCase().endsWith('.all')) {
      setState(() => _error = 'AllToMidi accepts .ALL songs only, not .ARR');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recover MIDI with AllToMidi?'),
        content: const Text(
          'This extracts only MIDI data from the selected .ALL file. '
          'Audio, VST instruments, effect presets and mixer states are not '
          'converted. Tempo changes and SysEx may be incomplete. '
          'The external executable is not sandboxed. '
          'Use only the application you installed and trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept MIDI-only conversion'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['exe'],
      dialogTitle: 'Select your installed AllToMidi.exe',
    );
    if (selected == null || selected.files.single.path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _allToMidiResult = null;
    });
    try {
      final result = await AllToMidiBridge().convert(
        original: File(preparation.legacyPath),
        executable: File(selected.files.single.path!),
        acknowledgeLosses: true,
      );
      if (!mounted) return;
      setState(() => _allToMidiResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'MIDI recovery failed: $error');
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
            Text('Primary route: native DPM .ALL reader on Apple Silicon, '
                'Intel Mac, Windows and Linux',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Reads supported Cubase VST .ALL MIDI tracks and arrangements '
              'directly in Dart, then exports a new standard MIDI type 1 file. '
              'No Cubase 3 installation, Windows executable, Python runtime '
              'or upload is required. Format coverage remains experimental. '
              'The .ARR format is not yet supported by the native reader.',
            ),
            const SizedBox(height: 12),
            Text('Alternative A: official Cubase 3 import',
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
            Text('Alternative B: Atari conversion without Cubase 3',
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
            Text('Alternative C: separate Windows AllToMidi executable',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'MIT-licensed AllToMidi 1.0 recovers MIDI type 1 (480 PPQ), '
              'with names, notes and many channel events. It does not '
              'support ARR, audio, VST presets or original mixer settings. '
              'Install the executable yourself. On macOS/Linux, run it '
              'separately on Windows or wait for a reviewed cross-platform port.',
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
              const SizedBox(height: 12),
              Text('Native DPM MIDI preview',
                  style: Theme.of(context).textTheme.titleSmall),
              if (_nativePreview case final song?) ...[
                Text('Recovered: ${song.tracks.length} MIDI tracks, '
                    '${song.noteCount} notes, ${song.eventCount} events'),
                Text('Initial tempo: '
                    '${(60000000 / song.microsecondsPerQuarter).toStringAsFixed(2)} BPM'),
                for (final track in song.tracks.take(20))
                  ListTile(
                    dense: true,
                    title: Text(track.name),
                    subtitle: Text(
                      'Channel ${track.channel} · '
                      '${track.partCount} part(s) · '
                      '${track.noteCount} note(s) · '
                      '${track.layout}',
                    ),
                  ),
                if (song.tracks.length > 20)
                  Text('${song.tracks.length - 20} more tracks not displayed'),
                FilledButton.icon(
                  onPressed: _busy ? null : _convertNatively,
                  icon: const Icon(Icons.piano),
                  label: const Text('Convert natively to MIDI (macOS/Windows)'),
                ),
              ],
              if (_nativePreviewError != null)
                Text(_nativePreviewError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (preparation.legacyPath.toLowerCase().endsWith('.arr'))
                const Text('Native .ARR decoding not available yet. '
                    'Use the external migration paths below.'),
              if (_nativeResult case final result?) ...[
                SelectableText('Native MIDI file: ${result.outputPath}'),
                Text('${result.trackCount} tracks · '
                    '${result.noteCount} notes · 480 PPQ'),
                SelectableText('Report: ${result.reportPath}'),
                const Text('Import into Cubase and save as a new CPR. '
                    'VST/mixer/audio restoration is not claimed.'),
              ],
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
              const SizedBox(height: 8),
              const Text(
                '2C. Windows: recover a standard MIDI file from a .ALL '
                'song using a separately installed AllToMidi.exe.',
              ),
              OutlinedButton.icon(
                onPressed: Platform.isWindows && !_busy &&
                        preparation.legacyPath.toLowerCase().endsWith('.all')
                    ? _convertWithAllToMidi : null,
                icon: const Icon(Icons.piano_outlined),
                label: const Text('Convert .ALL to MIDI with AllToMidi'),
              ),
              if (_allToMidiResult case final result?) ...[
                SelectableText('MIDI output: ${result.outputPath}'),
                Text('Tracks: ${result.trackCount} · '
                    'Notes decoded: ${result.noteCount} · '
                    'Resolution: ${result.ppq} PPQ'),
                SelectableText('Verified backup: ${result.backupPath}'),
                const Text(
                  'Import the MIDI into a recent Cubase project, then save '
                  'as CPR. The result is not certified musically equivalent.',
                ),
              ],
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
