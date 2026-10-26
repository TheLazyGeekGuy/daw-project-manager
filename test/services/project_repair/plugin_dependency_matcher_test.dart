import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/local_plugin_inventory.dart';
import 'package:daw_project_manager/services/project_repair/plugin_dependency_matcher.dart';

void main() {
  test('name matches remain unverified candidates', () {
    const inventory = [
      LocalPluginCandidate(
        path: '/plugins/Serum.vst3',
        name: 'Serum',
        format: 'VST3',
      ),
    ];
    final results = const PluginDependencyMatcher().compare([
      'Serum_x64',
      'Uninstalled Synth',
    ], inventory);
    expect(results.first.status, PluginDependencyStatus.candidatePresent);
    expect(results.first.toJson()['identity_verified'], false);
    expect(results.first.toJson()['loadability'], 'untested');
    expect(results.last.status, PluginDependencyStatus.notFoundByName);
  });

  const id = '0123456789ABCDEF0123456789ABCDEF';
  const other = '11111111111111111111111111111111';
  const declared = LocalPluginCandidate(
    path: '/plugins/Synth.vst3',
    name: 'Synth',
    format: 'VST3',
    identifier: id,
    vendor: 'Vendor',
    version: '1.2',
  );
  const matcher = PluginDependencyMatcher();

  test('CID matches despite renamed project display name', () {
    final result = matcher
        .compareRequests(
          [
            const PluginDependencyRequest(
              name: 'Renamed Synth',
              identifier: '{01234567-89ab-cdef-0123-456789abcdef}',
              source: 'cubase_serialized_guid',
            ),
          ],
          [declared],
        )
        .single;
    expect(result.status, PluginDependencyStatus.identifierPresent);
    expect(result.toJson()['identity_verified'], false);
    expect(result.toJson()['loadability'], 'untested');
  });

  test('same name with conflicting CID does not establish presence', () {
    final result = matcher
        .compareRequests(
          [const PluginDependencyRequest(name: 'Synth', identifier: other)],
          [declared],
        )
        .single;
    expect(result.status, PluginDependencyStatus.identifierNotFound);
    expect(result.candidates, [declared]);
    expect(result.toJson()['absence_is_conclusive'], false);
  });

  test('same ID in multiple installations remains ambiguous', () {
    const second = LocalPluginCandidate(
      path: '/alternate/Synth.vst3',
      name: 'Synth',
      format: 'VST3',
      identifier: id,
      version: '2',
    );
    final result = matcher
        .compareRequests(
          [const PluginDependencyRequest(name: 'Synth', identifier: id)],
          [declared, second],
        )
        .single;
    expect(result.status, PluginDependencyStatus.ambiguous);
    expect(result.candidates, hasLength(2));
  });

  test('declared replacement is never an exact or tested-state match', () {
    const replacement = LocalPluginCandidate(
      path: '/plugins/New.vst3',
      name: 'New',
      format: 'VST3',
      identifier: other,
      compatibleIdentifiers: [id],
    );
    final result = matcher
        .compareRequests(
          [const PluginDependencyRequest(name: 'Old', identifier: id)],
          [replacement],
        )
        .single;
    expect(result.status, PluginDependencyStatus.compatibilityCandidate);
    expect(result.evidence, 'manifest_compatibility_declaration');
  });

  test('format conflicts and unsupported identifiers remain unresolved', () {
    final results = matcher.compareRequests(
      [
        const PluginDependencyRequest(
          name: 'Synth',
          identifier: id,
          format: 'AU',
        ),
        const PluginDependencyRequest(
          name: 'Synth',
          identifier: 'not-a-known-id',
        ),
      ],
      [declared],
    );
    expect(results.first.status, PluginDependencyStatus.identifierNotFound);
    expect(results.first.candidates, isEmpty);
    expect(results.last.status, PluginDependencyStatus.unknown);
  });

  test('multiple same-name candidates are ambiguous, not installed proof', () {
    const au = LocalPluginCandidate(
      path: '/plugins/Synth.component',
      name: 'Synth',
      format: 'AU',
    );
    expect(
      matcher.compare(['Synth'], [declared, au]).single.status,
      PluginDependencyStatus.ambiguous,
    );
  });
}
