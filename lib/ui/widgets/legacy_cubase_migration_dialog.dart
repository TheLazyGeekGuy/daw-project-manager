import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/project_repair/all_to_midi_bridge.dart';
import '../../services/project_repair/legacy_cubase_migration.dart';
import '../../services/project_repair/native_legacy_all_reader.dart';
import 'legacy_all_recovery_action.dart';

/// Read-only native preview, the shared guarded MIDI recovery action, and
/// operator-assisted legacy import routes. No external converter is bundled.
class LegacyCubaseMigrationDialog extends StatefulWidget {
  const LegacyCubaseMigrationDialog({super.key, this.pickFile, this.recover});

  /// Dialog boundary injection keeps widget tests inside their temporary files.
  final Future<File?> Function(List<String> extensions)? pickFile;
  final Future<Map<String, Object?>> Function(String path)? recover;

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
  LegacyAllSong? _nativePreview;
  String? _nativePreviewError;
  bool _busy = false;
  String? _error;

  AppLocalizations get l => AppLocalizations.of(context)!;

  Future<File?> _pick(List<String> extensions, {String? title}) async {
    if (widget.pickFile != null) return widget.pickFile!(extensions);
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      dialogTitle: title,
    );
    final path = files.firstOrNull?.path;
    return path == null ? null : File(path);
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseLegacy() => _perform(() async {
    final selected = await _pick(const ['all', 'arr']);
    if (selected == null || !mounted) return;
    setState(() {
      _validation = null;
      _intermediateValidation = null;
      _allToMidiResult = null;
      _nativePreview = null;
      _nativePreviewError = null;
      _preparation = null;
    });
    final preparation = await LegacyCubaseMigration.prepare(selected);
    if (!mounted) return;
    setState(() => _preparation = preparation);
    if (!preparation.legacyPath.toLowerCase().endsWith('.all')) return;
    try {
      final parsed = await _previewInBackground(preparation.backupPath);
      if (mounted) setState(() => _nativePreview = parsed);
    } catch (error) {
      if (mounted) setState(() => _nativePreviewError = error.toString());
    }
  });

  // Keep the isolate closure in a static scope: an async State method's
  // shared closure context can otherwise capture the entire widget tree.
  static Future<LegacyAllSong> _previewInBackground(String path) =>
      Isolate.run(() => _readPreview(path));

  static Future<LegacyAllSong> _readPreview(String path) async {
    final file = File(path);
    if (await file.length() > NativeLegacyAllReader.maxInputBytes) {
      throw const FormatException('Legacy preview exceeds its size limit');
    }
    // The stream bound also holds if the file grows after its initial stat.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(
      0,
      NativeLegacyAllReader.maxInputBytes + 1,
    )) {
      if (bytes.length + chunk.length > NativeLegacyAllReader.maxInputBytes) {
        throw const FormatException('Legacy preview exceeds its size limit');
      }
      bytes.add(chunk);
    }
    return const NativeLegacyAllReader().read(bytes.takeBytes());
  }

  Future<void> _convertWithAllToMidi() async {
    final preparation = _preparation;
    if (preparation == null ||
        !Platform.isWindows ||
        !preparation.legacyPath.toLowerCase().endsWith('.all')) {
      return;
    }
    final labels = l;
    await _perform(() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels.legacyMigrationAllToMidiTitle),
          content: Text(labels.legacyMigrationExternalConsent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(labels.legacyMigrationRunExternal),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final executable = await _pick(const [
        'exe',
      ], title: labels.legacyMigrationSelectExecutable);
      if (executable == null || !mounted) return;
      setState(() => _allToMidiResult = null);
      final result = await AllToMidiBridge().convert(
        original: File(preparation.legacyPath),
        executable: executable,
        acknowledgeLosses: true,
      );
      if (mounted) setState(() => _allToMidiResult = result);
    });
  }

  Future<void> _chooseOutput({required bool dawProject}) async {
    final preparation = _preparation;
    if (preparation == null) return;
    await _perform(() async {
      final selected = await _pick([dawProject ? 'dawproject' : 'cpr']);
      if (selected == null || !mounted) return;
      setState(() {
        if (dawProject) {
          _intermediateValidation = null;
        } else {
          _validation = null;
        }
      });
      final result = dawProject
          ? await LegacyCubaseMigration.validateDawProject(
              preparation,
              selected,
            )
          : await LegacyCubaseMigration.validate(preparation, selected);
      if (!mounted) return;
      setState(() {
        if (dawProject) {
          _intermediateValidation = result;
        } else {
          _validation = result;
        }
      });
    });
  }

  Future<void> _openConverter() => _perform(() async {
    final opened = await launchUrl(
      Uri.parse(LegacyCubaseMigration.atariConverter),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => _error = l.legacyMigrationOpenFailed);
    }
  });

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final preparation = _preparation;
    final song = _nativePreview;
    final isAll =
        preparation?.legacyPath.toLowerCase().endsWith('.all') ?? false;
    final previewMetadata = song?.toJson();
    return AlertDialog(
      title: Text(l.legacyMigrationTitle),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.legacyMigrationIntro),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('legacy-migration-choose'),
                onPressed: _busy ? null : _chooseLegacy,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l.legacyMigrationChooseLegacy),
              ),
              if (_busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                Text(l.projectRepairWorking),
              ],
              if (_error != null)
                SelectableText(
                  '${l.projectRepairFailed}\n$_error',
                  key: const ValueKey('legacy-migration-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (preparation != null) ...[
                SelectableText(l.legacyMigrationSource(preparation.legacyPath)),
                SelectableText(
                  l.legacyMigrationSourceHash(preparation.legacySha256),
                ),
                SelectableText(l.legacyMigrationBackup(preparation.backupPath)),
              ],
              _heading(l.legacyMigrationNativeTitle),
              Text(l.legacyMigrationNativeBody),
              if (song != null && preparation != null) ...[
                _heading(l.legacyMigrationPreviewTitle),
                Text(
                  l.legacyMigrationPreviewSummary(
                    song.tracks.length,
                    song.noteCount,
                    song.eventCount,
                  ),
                ),
                Text(
                  l.legacyMigrationInitialTempo(
                    (60000000 / song.microsecondsPerQuarter).toStringAsFixed(2),
                  ),
                ),
                if (previewMetadata?['initial_tempo_defaulted'] == true)
                  Text(
                    l.legacyMigrationTempoDefaulted(
                      (60000000 / song.microsecondsPerQuarter).toStringAsFixed(
                        2,
                      ),
                    ),
                  ),
                if ((previewMetadata?['skipped_parts'] as int? ?? 0) > 0)
                  Text(
                    '${l.projectRepairSkippedParts}: ${previewMetadata!['skipped_parts']}',
                  ),
                for (final track in song.tracks.take(20))
                  ListTile(
                    dense: true,
                    title: Text(track.name),
                    subtitle: Text(
                      l.legacyMigrationTrackSummary(
                        track.channel,
                        track.partCount,
                        track.noteCount,
                      ),
                    ),
                  ),
                if (song.tracks.length > 20)
                  Text(l.legacyMigrationMoreTracks(song.tracks.length - 20)),
                IgnorePointer(
                  ignoring: _busy,
                  child: LegacyAllRecoveryAction(
                    key: ValueKey(preparation.legacyPath),
                    path: preparation.legacyPath,
                    recover: widget.recover,
                  ),
                ),
              ],
              if (_nativePreviewError != null) ...[
                Text(l.legacyMigrationUnsupportedPreview),
                SelectableText(_nativePreviewError!),
              ],
              if (preparation != null && !isAll)
                Text(l.legacyMigrationArrUnsupported),
              _heading(l.legacyMigrationOfficialTitle),
              Text(l.legacyMigrationOfficialBody),
              Text(l.projectInspectorLegacyLosses),
              const SelectableText(LegacyCubaseMigration.steinbergGuide),
              _heading(l.legacyMigrationAtariTitle),
              Text(l.legacyMigrationAtariBody),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openConverter,
                icon: const Icon(Icons.open_in_new),
                label: Text(l.legacyMigrationOpenConverter),
              ),
              _heading(l.legacyMigrationAllToMidiTitle),
              Text(l.legacyMigrationAllToMidiBody),
              OutlinedButton.icon(
                onPressed: Platform.isWindows && !_busy && isAll
                    ? _convertWithAllToMidi
                    : null,
                icon: const Icon(Icons.piano_outlined),
                label: Text(l.legacyMigrationRunExternal),
              ),
              if (_allToMidiResult case final result?) ...[
                SelectableText(l.legacyMigrationMidiOutput(result.outputPath)),
                Text(
                  l.legacyMigrationMidiSummary(
                    result.trackCount,
                    result.noteCount,
                    result.ppq,
                  ),
                ),
                SelectableText(l.legacyMigrationBackup(result.backupPath)),
                Text(l.projectRepairUnverifiedRecovery),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('legacy-migration-dawproject'),
                onPressed: preparation != null && !_busy
                    ? () => _chooseOutput(dawProject: true)
                    : null,
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(l.legacyMigrationCheckDawProject),
              ),
              if (_intermediateValidation case final intermediate?) ...[
                Text(l.legacyMigrationDawProjectChecked),
                Text(l.projectInspectorFormat(intermediate.converted.formatId)),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('legacy-migration-cpr'),
                onPressed: preparation != null && !_busy
                    ? () => _chooseOutput(dawProject: false)
                    : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l.legacyMigrationCheckCpr),
              ),
              if (_validation case final validation?) ...[
                Text(l.legacyMigrationCprChecked),
                Text(
                  l.projectInspectorSavedVersion(
                    validation.converted.savedDawVersion ?? l.unknown,
                  ),
                ),
                Text(
                  l.projectInspectorTracks(
                    validation.converted.trackCount?.toString() ?? l.unknown,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
      ],
    );
  }
}
