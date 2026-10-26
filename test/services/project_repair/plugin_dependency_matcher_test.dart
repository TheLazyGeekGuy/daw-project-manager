import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/local_plugin_inventory.dart';
import 'package:daw_project_manager/services/project_repair/plugin_dependency_matcher.dart';

void main() {
  test('name matches remain unverified candidates', () {
    const inventory = [
      LocalPluginCandidate(
        path: '/plugins/Serum.vst3', name: 'Serum', format: 'VST3',
      ),
    ];
    final results = const PluginDependencyMatcher().compare(
      ['Serum_x64', 'Uninstalled Synth'],
      inventory,
    );
    expect(results.first.status, PluginDependencyStatus.candidatePresent);
    expect(results.first.toJson()['identity_verified'], false);
    expect(results.first.toJson()['loadability'], 'untested');
    expect(results.last.status, PluginDependencyStatus.notFoundByName);
  });
}
