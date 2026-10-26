import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/project_repair/project_dependency_inspector.dart';
import 'project_dependency_report_panel.dart';

/// Shows a read-only report for a selected project file.
class ProjectInspectionDialog extends StatefulWidget {
  const ProjectInspectionDialog({super.key, required this.projectFile});
  final File projectFile;

  @override
  State<ProjectInspectionDialog> createState() => _ProjectInspectionDialogState();
}

class _ProjectInspectionDialogState extends State<ProjectInspectionDialog> {
  late final Future<ProjectDependencyReport> _report =
      ProjectDependencyInspector.inspect(widget.projectFile);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project inspection'),
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
                return SelectableText('Inspection failed: ${snapshot.error}');
              }
              final report = snapshot.data;
              if (report == null) return const Text('No report available');
              return ProjectDependencyReportPanel(report: report);
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
