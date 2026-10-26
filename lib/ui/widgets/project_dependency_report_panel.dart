import 'dart:isolate';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';
import '../../services/project_repair/local_plugin_inventory.dart';
import '../../services/project_repair/cubase_preservation_service.dart';
import '../../services/project_repair/plugin_dependency_matcher.dart';

import '../../services/project_repair/project_dependency_inspector.dart';
import 'legacy_all_recovery_action.dart';

/// Read-only project dependency view. Unknown states must remain visible.
class ProjectDependencyReportPanel extends StatelessWidget {
  const ProjectDependencyReportPanel({
    super.key,
    required this.report,
    this.inventoryScanner,
    this.inventoryRoots,
  });

  final ProjectDependencyReport report;
  final LocalPluginInventoryReport Function(List<String> roots)?
  inventoryScanner;

  /// Override standard roots for a scoped inventory or temporary-file tests.
  /// User-entered additional roots are still included. Null uses OS defaults.
  final List<String>? inventoryRoots;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.projectInspectorDependencies,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l.projectInspectorFormat(report.formatId)),
        Text(
          l.projectInspectorTracks(report.trackCount?.toString() ?? l.unknown),
        ),
        if (report.formatId == 'cubase-all')
          LegacyAllRecoveryAction(path: report.path),
        if (report.dawProjectSummary case final summary?) ...[
          Text('DAWproject ${summary.version} · ${summary.applicationName}'),
          Text(
            l.projectInspectorTimeline(
              summary.clipCount,
              summary.noteCount,
              summary.automationPointCount,
            ),
          ),
          Text(
            l.projectInspectorReferences(
              summary.externalReferences.length,
              summary.missingReferences.length,
            ),
          ),
        ],
        if (report.savedDawVersion != null)
          Text(l.projectInspectorSavedVersion(report.savedDawVersion!)),
        if (report.cubaseContainer != null)
          Text(
            l.projectInspectorValidatedChunks(
              report.cubaseContainer!.chunks.length,
              report.cubaseContainer!.archiveCount,
            ),
          ),
        if (report.legacyConversionGuide case final guide?) ...[
          const SizedBox(height: 12),
          Text(
            l.projectInspectorLegacyTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(l.projectInspectorLegacyLosses),
          for (final step in (guide['steps'] as List? ?? const []))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $step'),
            ),
          SelectableText(guide['source_url'].toString()),
        ],
        if (report.cubaseContainer != null)
          _CprPreservationAction(path: report.path),
        if (report.pluginUidEvidence.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l.projectInspectorUidEvidence,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(l.projectInspectorUidCaution),
          for (final plugin in report.pluginUidEvidence.where(
            (p) => !p.internalDevice,
          ))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(plugin.name),
              subtitle: SelectableText(
                l.projectInspectorUidRecord(plugin.uid, plugin.occurrences),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          l.projectInspectorPlugins,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (report.pluginNames.isEmpty)
          Text(l.projectInspectorNoPlugins)
        else
          for (final name in report.pluginNames)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension_outlined),
              title: Text(name),
              subtitle: Text(l.projectInspectorLoadabilityUntested),
            ),
        if (report.dependencyRequests.isNotEmpty)
          _OptInPluginScan(
            requests: report.dependencyRequests,
            scanner: inventoryScanner,
            roots: inventoryRoots,
          ),
        const SizedBox(height: 8),
        Text(
          l.projectInspectorLimitations,
          style: Theme.of(context).textTheme.titleSmall,
        ),
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

/// The user selects when to scan. Binaries are not loaded by this inventory.
class _OptInPluginScan extends StatefulWidget {
  const _OptInPluginScan({required this.requests, this.scanner, this.roots});
  final List<PluginDependencyRequest> requests;
  final LocalPluginInventoryReport Function(List<String> roots)? scanner;
  final List<String>? roots;

  @override
  State<_OptInPluginScan> createState() => _OptInPluginScanState();
}

typedef _ScanResult = ({
  LocalPluginInventoryReport inventory,
  List<PluginDependencyMatch> matches,
});

// Only immutable request data and paths cross these worker boundaries.
// Closures declared inside a State method can retain its whole UI context.
Future<_ScanResult> _scanPluginsInBackground(
  List<PluginDependencyRequest> requests,
  List<String> roots,
) => Isolate.run(() {
  final inventory = LocalPluginInventory.scanReport(roots: roots);
  return _matchInventory(requests, inventory);
});

_ScanResult _matchInventory(
  List<PluginDependencyRequest> requests,
  LocalPluginInventoryReport inventory,
) => (
  inventory: inventory,
  matches: const PluginDependencyMatcher().compareRequests(
    requests,
    inventory.candidates,
  ),
);

Future<Map<String, Object?>> _preserveCprInBackground(String path) =>
    Isolate.run(() => CubasePreservationService().preserve(File(path)));

class _OptInPluginScanState extends State<_OptInPluginScan> {
  final _additionalRoots = TextEditingController();
  Future<_ScanResult>? _scan;
  bool _scanning = false;

  @override
  void dispose() {
    _additionalRoots.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final requests = List<PluginDependencyRequest>.unmodifiable(
      widget.requests,
    );
    final roots = [
      ...widget.roots ?? LocalPluginInventory.defaultRoots(),
      ..._additionalRoots.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty),
    ];
    final scanner = widget.scanner;
    setState(() {
      _scanning = true;
      _scan = scanner == null
          ? _scanPluginsInBackground(requests, roots)
          : Future(() => _matchInventory(requests, scanner(roots)));
    });
    try {
      await _scan;
    } catch (_) {
      // The FutureBuilder renders the error; the button still allows a retry.
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _description(PluginDependencyMatch match) => switch (match.status) {
    PluginDependencyStatus.identifierPresent =>
      l.projectInspectorStatusIdentifierPresent,
    PluginDependencyStatus.compatibilityCandidate =>
      l.projectInspectorStatusReplacement,
    PluginDependencyStatus.ambiguous => l.projectInspectorStatusAmbiguous(
      match.candidates.length,
    ),
    PluginDependencyStatus.identifierNotFound =>
      l.projectInspectorStatusIdentifierNotFound,
    PluginDependencyStatus.candidatePresent =>
      l.projectInspectorStatusNameCandidate,
    PluginDependencyStatus.notFoundByName =>
      l.projectInspectorStatusNameNotFound,
    PluginDependencyStatus.unknown => l.projectInspectorStatusUnknown,
  };

  AppLocalizations get l =>
      AppLocalizations.of(context) ?? AppLocalizationsEn();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _additionalRoots,
        minLines: 1,
        maxLines: 3,
        enabled: !_scanning,
        decoration: InputDecoration(
          labelText: l.projectInspectorAdditionalFolders,
          helperText: l.projectInspectorAdditionalFoldersHelp,
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.search),
        onPressed: _scanning ? null : _start,
        label: Text(l.projectInspectorScanButton),
      ),
      if (_scan != null)
        FutureBuilder<_ScanResult>(
          future: _scan,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                l.projectInspectorScanFailed(snapshot.error.toString()),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final inventory = snapshot.data!.inventory;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.projectInspectorScanSummary(
                    inventory.candidates.length,
                    inventory.scannedRoots.length,
                  ),
                ),
                Text(l.projectInspectorPassiveScan),
                if (inventory.truncated) Text(l.projectInspectorScanIncomplete),
                if (inventory.warnings.isNotEmpty)
                  ExpansionTile(
                    title: Text(
                      l.projectInspectorScanWarnings(inventory.warnings.length),
                    ),
                    children: [
                      for (final warning in inventory.warnings)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(warning),
                        ),
                    ],
                  ),
                for (final match in snapshot.data!.matches)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(match.requestedName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_description(match)),
                        if (match.requestedIdentifier != null)
                          SelectableText(
                            l.projectInspectorRequestedId(
                              match.requestedIdentifier!,
                            ),
                          ),
                        for (final candidate in match.candidates)
                          SelectableText(
                            '${candidate.name} · ${candidate.format}'
                            '${candidate.version == null ? "" : " · ${candidate.version}"}'
                            '${candidate.vendor == null ? "" : " · ${candidate.vendor}"}\n'
                            '${candidate.path}',
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

/// Creates an unchanged project copy plus opaque chunk evidence on request.
class _CprPreservationAction extends StatefulWidget {
  const _CprPreservationAction({required this.path});
  final String path;

  @override
  State<_CprPreservationAction> createState() => _CprPreservationActionState();
}

class _CprPreservationActionState extends State<_CprPreservationAction> {
  Future<Map<String, Object?>>? _operation;
  AppLocalizations get l =>
      AppLocalizations.of(context) ?? AppLocalizationsEn();

  void _preserve() {
    final path = widget.path;
    setState(() {
      _operation = _preserveCprInBackground(path);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Text(l.projectInspectorPreservationIntro),
      OutlinedButton.icon(
        icon: const Icon(Icons.inventory_2_outlined),
        label: Text(l.projectInspectorPreserveButton),
        onPressed: _operation == null ? _preserve : null,
      ),
      if (_operation != null)
        FutureBuilder<Map<String, Object?>>(
          future: _operation,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                l.projectInspectorPreserveFailed(snapshot.error.toString()),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final result = snapshot.data!;
            return SelectableText(
              '${l.projectInspectorPreserveSummary(result['status'].toString(), result['workspace_path'].toString(), result['backup_path'].toString())}\n${l.projectInspectorPreserveLimit}',
            );
          },
        ),
    ],
  );
}
