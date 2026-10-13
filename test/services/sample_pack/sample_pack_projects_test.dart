import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/sample_pack/sample_pack_prefs_store.dart';
import 'package:daw_project_manager/services/sample_pack/sample_pack_projects.dart';

import '../../helpers/test_factories.dart';

void main() {
  group('samplePackProjectsOf', () {
    test('reads real project files, not stacks or archived projects', () {
      final projects = samplePackProjectsOf([
        TestFactories.makeProject(id: 'a', filePath: '/m/a.als'),
        TestFactories.makeProject(
            id: 'stack', filePath: '/m/Song', isVirtual: true),
        TestFactories.makeProject(
          id: 'old',
          filePath: '/m/old.als',
          archivePath: '/archive/old.zip',
        ),
      ], profileName: 'Main');
      expect([for (final x in projects) x.filePath], ['/m/a.als']);
      expect(projects.single.profileName, 'Main');
      expect(projects.single.songKey, 'a');
    });

    test("a stack's versions are one song, under the stack's name", () {
      final projects = samplePackProjectsOf([
        TestFactories.makeProject(
          id: 'stack',
          filePath: '/m/Song',
          isVirtual: true,
          customDisplayName: 'Teardrop Remix',
        ),
        TestFactories.makeProject(
            id: 'v1', filePath: '/m/Song/v1.cpr', stackId: 'stack'),
        TestFactories.makeProject(
            id: 'v2', filePath: '/m/Song/v2.cpr', stackId: 'stack'),
      ], profileName: 'Main');
      expect(projects, hasLength(2));
      expect({for (final x in projects) x.songKey}, {'stack'});
      expect({for (final x in projects) x.name}, {'Teardrop Remix'});
    });
  });

  test('uniqueFolderNames numbers repeats, ignoring case', () {
    expect(uniqueFolderNames(['Leads', 'leads', 'Bass', 'Leads']),
        ['Leads', 'leads (2)', 'Bass', 'Leads (3)']);
  });

  group('SamplePackPrefs', () {
    test('round-trips through JSON', () {
      const prefs = SamplePackPrefs(
        libraryFolders: [r'D:\Samples', '/Volumes/Lib'],
        includeOwnAudio: true,
        includeMidi: false,
        profileIds: ['p1', 'p2'],
      );
      final back = SamplePackPrefs.fromJson(prefs.toJson());
      expect(back.libraryFolders, prefs.libraryFolders);
      expect(back.includeOwnAudio, isTrue);
      expect(back.includeMidi, isFalse);
      expect(back.profileIds, ['p1', 'p2']);
    });

    test('defaults: no folders, no own audio, MIDI in, every profile', () {
      final prefs = SamplePackPrefs.fromJson(null);
      expect(prefs.libraryFolders, isEmpty);
      expect(prefs.includeOwnAudio, isFalse);
      expect(prefs.includeMidi, isTrue);
      expect(prefs.profileIds, isNull);
      expect(SamplePackPrefs.fromJson({'libraryFolders': 'nonsense'})
          .libraryFolders, isEmpty);
    });
  });
}
