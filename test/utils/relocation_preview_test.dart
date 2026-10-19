import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/utils/relocation_preview.dart';

import '../helpers/test_factories.dart';

void main() {
  final base = p.join(Directory.systemTemp.path, 'dpm_preview');
  final from = p.join(base, 'C', 'Music');
  final to = p.join(base, 'D', 'Music');

  final projects = [
    TestFactories.makeProject(id: 'a', filePath: p.join(from, 'A', 'A.als')),
    TestFactories.makeProject(id: 'b', filePath: p.join(from, 'B.flp')),
    TestFactories.makeProject(id: 'elsewhere', filePath: p.join(base, 'Other', 'X.als')),
    // Neither has a file expected at the new place.
    TestFactories.makeProject(id: 'stack', filePath: p.join(from, 'A'), isVirtual: true),
    TestFactories.makeProject(id: 'zip', filePath: p.join(from, 'Z.als'), archivePath: p.join(base, 'Z.zip')),
  ];

  test('counts the folder\'s projects and looks for each under the new folder', () {
    final looked = <String>[];
    final preview = previewRelocation(projects, from: from, to: to, exists: (path) {
      looked.add(path);
      return path == p.join(to, 'A', 'A.als');
    });

    expect(looked, [p.join(to, 'A', 'A.als'), p.join(to, 'B.flp')]);
    expect(preview.projects, 2);
    expect(preview.found, 1);
    expect(preview.allFound, isFalse);
    expect(preview.noneFound, isFalse);
  });

  test('all there, or none there', () {
    final all = previewRelocation(projects, from: from, to: to, exists: (_) => true);
    expect(all.allFound, isTrue);
    expect(all.noneFound, isFalse);

    final none = previewRelocation(projects, from: from, to: to, exists: (_) => false);
    expect(none.noneFound, isTrue);
  });

  test('an empty folder is neither missing anything nor finding nothing', () {
    final empty = previewRelocation(const [], from: from, to: to, exists: (_) => false);
    expect(empty.projects, 0);
    expect(empty.allFound, isTrue);
    expect(empty.noneFound, isFalse);
  });

  test('by default it asks the disk, files and bundle folders alike', () async {
    final dir = await Directory.systemTemp.createTemp('dpm_preview_disk_');
    addTearDown(() => dir.delete(recursive: true));
    final source = p.join(dir.path, 'old');
    final target = p.join(dir.path, 'new');
    await File(p.join(target, 'Song.als')).create(recursive: true);
    await Directory(p.join(target, 'Bundle.logicx')).create(recursive: true);

    final preview = previewRelocation([
      TestFactories.makeProject(id: 'f', filePath: p.join(source, 'Song.als')),
      TestFactories.makeProject(id: 'd', filePath: p.join(source, 'Bundle.logicx')),
      TestFactories.makeProject(id: 'm', filePath: p.join(source, 'Missing.als')),
    ], from: source, to: target);

    expect(preview.projects, 3);
    expect(preview.found, 2);
  });
}
