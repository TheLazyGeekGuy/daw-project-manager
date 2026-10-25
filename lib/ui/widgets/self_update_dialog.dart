import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../services/self_updater.dart';
import '../../services/update_download.dart';
import '../app_snack_bar.dart';

enum _Stage { fetching, downloading, verifying, cancelling, ready, error }

/// Drives a self-update — the AppImage's or the Windows installer's copy
/// ([SelfUpdater]): download, verify, offer a restart — after the user picks
/// "Update Now" in [UpdateAvailableDialog]. Kept as a separate dialog/widget
/// so the parent dialog can stay a simple StatelessWidget.
class SelfUpdateDialog extends StatefulWidget {
  final String version;

  /// Makes a fresh updater for each attempt (Retry makes another).
  final SelfUpdater Function() createUpdater;

  const SelfUpdateDialog({super.key, required this.version, required this.createUpdater});

  static void show(BuildContext context, String version, SelfUpdater Function() createUpdater) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => SelfUpdateDialog(version: version, createUpdater: createUpdater),
    );
  }

  @override
  State<SelfUpdateDialog> createState() => _SelfUpdateDialogState();
}

class _SelfUpdateDialogState extends State<SelfUpdateDialog> {
  _Stage _stage = _Stage.fetching;
  double? _progress;
  String? _errorDetails;
  UpdateCancelToken? _cancelToken;

  /// The updater of the attempt that got ready; it restarts into the update.
  SelfUpdater? _ready;
  String _reportName = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _stage = _Stage.fetching;
      _progress = null;
      _errorDetails = null;
    });
    final cancelToken = UpdateCancelToken();
    _cancelToken = cancelToken;
    final updater = widget.createUpdater();
    _reportName = updater.reportName;
    var keep = false;
    try {
      await updater.prepare(
        widget.version,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _stage = progress == null ? _Stage.verifying : _Stage.downloading;
            _progress = progress;
          });
        },
      );
      if (!mounted) return;
      keep = true;
      _ready?.close();
      _ready = updater;
      setState(() => _stage = _Stage.ready);
    } on UpdateCancelledException {
      // Cleanup already happened inside prepare before this was thrown —
      // just close the dialog, this isn't a failure the user needs to see.
      if (mounted) Navigator.of(context).pop();
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorDetails = '$e\n\n$stackTrace';
      });
    } finally {
      if (!keep) updater.close();
    }
  }

  @override
  void dispose() {
    _ready?.close();
    super.dispose();
  }

  void _cancel() {
    if (_stage == _Stage.cancelling) return;
    setState(() => _stage = _Stage.cancelling);
    _cancelToken?.cancel();
  }

  Future<void> _restartNow() async {
    await _ready?.restart();
    exit(0);
  }

  Future<void> _copyErrorDetails(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: _errorDetails ?? ''));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showAppSnackBar(
      SnackBar(
        content: Text(l10n.appImageUpdateErrorDetailsCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openNewIssue() async {
    final uri = Uri(
      scheme: 'https',
      host: 'github.com',
      path: '/bandpassrecords/daw-project-manager/issues/new',
      queryParameters: {
        'template': 'issue.yml',
        'type': 'Bug report',
        'actual': 'The in-app $_reportName update failed with:\n\n${_errorDetails ?? ''}',
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return PopScope(
      canPop: _stage == _Stage.ready || _stage == _Stage.error,
      child: AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_titleFor(l10n)),
        content: SizedBox(
          width: 380,
          child: _buildBody(context, l10n, theme),
        ),
        actions: _buildActions(context, l10n),
      ),
    );
  }

  String _titleFor(AppLocalizations l10n) {
    switch (_stage) {
      case _Stage.ready:
        return l10n.appImageUpdateReadyTitle;
      case _Stage.error:
        return l10n.appImageUpdateFailedTitle;
      case _Stage.fetching:
      case _Stage.downloading:
      case _Stage.verifying:
      case _Stage.cancelling:
        return l10n.updateNowButtonLabel;
    }
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    switch (_stage) {
      case _Stage.fetching:
        return _ProgressRow(label: l10n.appImageUpdateFetching, progress: null);
      case _Stage.downloading:
        final percent = _progress == null ? null : (_progress! * 100).round();
        return _ProgressRow(
          label: percent == null
              ? l10n.appImageUpdateDownloading
              : l10n.appImageUpdateDownloadingProgress(percent),
          progress: _progress,
        );
      case _Stage.verifying:
        return _ProgressRow(label: l10n.appImageUpdateVerifying, progress: null);
      case _Stage.cancelling:
        return _ProgressRow(label: l10n.cancelling, progress: null);
      case _Stage.ready:
        return Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.appImageUpdateReadyMessage(widget.version))),
          ],
        );
      case _Stage.error:
        return _buildErrorBody(context, l10n, theme);
    }
  }

  Widget _buildErrorBody(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    final details = _errorDetails;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.appImageUpdateErrorMessage)),
            ],
          ),
          if (details != null) ...[
            const SizedBox(height: 4),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(l10n.appImageUpdateErrorDetailsLabel, style: theme.textTheme.bodyMedium),
                children: [
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        details,
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _copyErrorDetails(l10n),
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: Text(l10n.appImageUpdateCopyErrorDetails),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, AppLocalizations l10n) {
    switch (_stage) {
      case _Stage.fetching:
      case _Stage.downloading:
      case _Stage.verifying:
        return [
          TextButton(
            onPressed: _cancel,
            child: Text(l10n.cancel),
          ),
        ];
      case _Stage.cancelling:
        return const [];
      case _Stage.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.dismiss),
          ),
          FilledButton(
            onPressed: _restartNow,
            child: Text(l10n.appImageUpdateRestartNow),
          ),
        ];
      case _Stage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
          OutlinedButton.icon(
            onPressed: _openNewIssue,
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: Text(l10n.reportIssue),
          ),
          FilledButton(
            onPressed: _run,
            child: Text(l10n.appImageUpdateRetry),
          ),
        ];
    }
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double? progress;

  const _ProgressRow({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: progress),
      ],
    );
  }
}
