import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../services/project_repair/local_plugin_inventory.dart';
import '../../services/project_repair/plugin_dependency_matcher.dart';

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
        if (report.savedDawVersion != null)
          Text('Saved with DAW version: ${report.savedDawVersion}'),
        if (report.cubaseContainer != null)
          Text('Validated CPR chunks: ${report.cubaseContainer!.chunks.length} '
              '(ARCH blocks: ${report.cubaseContainer!.archiveCount})'),
        if (report.pluginUidEvidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Serialized plug-in UID evidence',
              style: Theme.of(context).textTheme.titleSmall),
          const Text(
            'Declared identifiers only. No vendor identity, plug-in state, '
            'licence or loadability has been verified.',
          ),
          for (final plugin
              in report.pluginUidEvidence.where((p) => !p.internalDevice))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(plugin.name),
              subtitle: SelectableText(
                'UID ${plugin.uid}; ${plugin.occurrences} serialized record(s)',
              ),
            ),
        ],
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
        if (report.pluginNames.isNotEmpty)
          _OptInPluginScan(pluginNames: report.pluginNames),
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


/// Passive filesystem scan only, launched at the user's request in an isolate.
/// A filename match cannot establish that a VST is licensed or loadable.
class _OptInPluginScan extends StatefulWidget {
  const _OptInPluginScan({required this.pluginNames});
  final List<String> pluginNames;

  @override
  State<_OptInPluginScan> createState() => _OptInPluginScanState();
}

class _OptInPluginScanState extends State<_OptInPluginScan> {
  Future<List<PluginDependencyMatch>>? _scan;

  void _start() {
    final names = widget.pluginNames.toSet().toList(growable: false);
    setState(() {
      _scan = Isolate.run(() {
        final candidates = LocalPluginInventory.scan();
        return const PluginDependencyMatcher().compare(names, candidates);
      });
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.search),
        onPressed: _scan == null ? _start : null,
        label: const Text('Scan local plug-in candidates (optional)'),
      ),
      if (_scan != null)
        FutureBuilder<List<PluginDependencyMatch>>(
          future: _scan,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Local scan failed: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filesystem names only. No plug-ins were executed; '
                  'a missing name is not proof that the plug-in is absent.',
                ),
                for (final match in snapshot.data!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(match.requestedName),
                    subtitle: Text(switch (match.status) {
                      PluginDependencyStatus.candidatePresent =>
                        '${match.candidates.length} name candidate(s); '
                        'identity and loadability untested',
                      PluginDependencyStatus.notFoundByName =>
                        'Not found in default scanned locations',
                      PluginDependencyStatus.unknown =>
                        'No usable plug-in name in the project',
                    }),
                  ),
              ],
            );
          },
        ),
    ],
  );
}
