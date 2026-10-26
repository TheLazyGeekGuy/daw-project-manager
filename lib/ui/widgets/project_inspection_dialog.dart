import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';
import '../../services/project_repair/project_dependency_inspector.dart';
import '../app_snack_bar.dart';
import 'project_dependency_report_panel.dart';

/// Shows a read-only report for a selected project file.
class ProjectInspectionDialog extends StatefulWidget {
  const ProjectInspectionDialog({super.key, required this.projectFile});
  final File projectFile;

  @override
  State<ProjectInspectionDialog> createState() =>
      _ProjectInspectionDialogState();
}

class _ProjectInspectionDialogState extends State<ProjectInspectionDialog> {
  late final Future<ProjectDependencyReport> _report =
      ProjectDependencyInspector.inspect(widget.projectFile);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return AlertDialog(
      title: Text(l.projectInspectorTitle),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: FutureBuilder<ProjectDependencyReport>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return SelectableText(
                  l.projectInspectorFailed(snapshot.error.toString()),
                );
              }
              final report = snapshot.data;
              if (report == null) return Text(l.projectInspectorEmpty);
              return ProjectDependencyReportPanel(report: report);
            },
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l.projectInspectorCopyReport),
          onPressed: () async {
            try {
              final report = await _report;
              await Clipboard.setData(
                ClipboardData(
                  text: const JsonEncoder.withIndent(
                    '  ',
                  ).convert(report.toJson()),
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showAppSnackBar(
                  SnackBar(content: Text(l.projectInspectorCopied)),
                );
              }
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showAppSnackBar(
                  SnackBar(
                    content: Text(
                      l.projectInspectorCopyFailed(error.toString()),
                    ),
                  ),
                );
              }
            }
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
      ],
    );
  }
}
