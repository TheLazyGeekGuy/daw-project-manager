import 'package:flutter/material.dart';

import '../../services/project_repair/project_dependency_inspector.dart';

/// Read-only project dependency view. Unknown states must remain visible.
class ProjectDependencyReportPanel extends StatelessWidget {
  const ProjectDependencyReportPanel({super.key, required this.report});

  final ProjectDependencyReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Project dependencies', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Format: ${report.formatId}'),
        Text('Tracks: ${report.trackCount?.toString() ?? "Unknown"}'),
        const SizedBox(height: 8),
        Text('Plug-ins', style: Theme.of(context).textTheme.titleSmall),
        if (report.pluginNames.isEmpty)
          const Text('No plug-ins decoded (not evidence of an empty session).')
        else
          for (final name in report.pluginNames)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension_outlined),
              title: Text(name),
              subtitle: const Text('Installation and loadability: not tested'),
            ),
        const SizedBox(height: 8),
        Text('Inspection limitations', style: Theme.of(context).textTheme.titleSmall),
        for (final limitation in report.limitations)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(limitation)),
              ],
            ),
          ),
      ],
    );
  }
}
