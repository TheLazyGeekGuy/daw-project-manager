// The sample pack over the whole collection, stacked as a real library is:
// the samples its projects use are copied into one folder by category —
// each a byte-exact copy, none twice, versions of a song counted once —
// master sessions are left unread, the report and missing list are written,
// the projects themselves are never touched, and a second export adds
// nothing.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/sample_reference.dart';
import 'package:daw_project_manager/models/scan_mode.dart';
import 'package:daw_project_manager/services/sample_pack/sample_pack_exporter.dart';
import 'package:daw_project_manager/services/sample_pack/project_sample_reader.dart';
import 'package:daw_project_manager/services/sample_pack/sample_pack_projects.dart';

import 'flow_library.dart';

String _sha1(File f) => sha1.convert(f.readAsBytesSync()).toString();

Map<String, String> _contents(Directory dir) => {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: dir.path): '${f.lengthSync()}:${f.lastModifiedSync().millisecondsSinceEpoch}',
    };

/// The projects' references, minus any absolute path outside [within].
///
/// The collection's projects name where their samples were on the machine
/// they were made on — paths that exist on that machine and nowhere else.
/// Left in, a run there finds the originals, and one on CI the copies: the
/// same test seeing different files. Without them every run is CI's.
Future<List<SampleReference>> Function(String) _referencesWithin(Directory within) =>
    (path) async => [
          for (final r in await readProjectSampleReferences(path))
            SampleReference(
              fileName: r.fileName,
              candidates: [
                for (final c in r.candidates)
                  if (!p.isAbsolute(c) || p.isWithin(within.path, c)) c,
              ],
              use: r.use,
              kind: r.kind,
              sizeBytes: r.sizeBytes,
            ),
        ];

void main() {
  late FlowLibrary lib;
  late Directory pack;
  late List<SamplePackProject> projects;

  setUp(() async {
    lib = await FlowLibrary.open();
    await lib.repo.updateRootScanMode(lib.root.id, ScanMode.versionStack);
    await lib.scan();
    pack = Directory(p.join(lib.scratch.path, 'Pack'));
    projects = samplePackProjectsOf(lib.projects, profileName: 'Audio Crawler');
  });
  tearDown(() async => lib.close());

  test('a pack of exactly the samples the projects use', () async {
    final projectsBefore = _contents(lib.projectsDir);
    final result = await SamplePackExporter(
            destination: pack.path,
            excludeMasterProjects: true,
            readReferences: _referencesWithin(lib.scratch))
        .export(projects);

    expect(result.stopped, isFalse);
    expect(result.masterProjectsLeftOut, greaterThanOrEqualTo(2),
        reason: "B 138's Master set and the Cubase master project");
    expect(result.added, greaterThan(20));
    expect(_contents(lib.projectsDir), projectsBefore, reason: 'the projects are only ever read');

    // Each pack file is a byte-exact copy of a file a project uses.
    final hashes = <String>{};
    for (final s in result.samples.where((s) => s.packPath != null)) {
      final inPack = File(p.join(pack.path, s.packPath!));
      expect(inPack.existsSync(), isTrue, reason: s.packPath);
      final hash = _sha1(inPack);
      expect(_sha1(File(s.paths.first)), hash, reason: '${s.packPath} is a copy of ${s.paths.first}');
      expect(hashes.add(hash), isTrue, reason: '${s.packPath} is in the pack once');
      expect(p.isWithin(lib.projectsDir.path, s.paths.first), isTrue,
          reason: 'found among the projects, not anywhere else on this machine');
    }

    // Versions of one song are one use: the eight saves of one remix.
    final fts = lib.fixtures.singleWhere((f) => f.name.startsWith('Fuck The System'));
    final ftsSamples = result.samples
        .where((s) => s.paths.any((path) => p.isWithin(fts.folder.path, path)))
        .toList();
    expect(ftsSamples, isNotEmpty);
    final ftsStack = lib.projectOf(fts.projectFiles.first).stackId!;
    final ftsVersions = {for (final file in fts.projectFiles) lib.projectOf(file).id};
    for (final s in ftsSamples) {
      expect(s.songs.keys, contains(ftsStack), reason: '${s.packPath}: used by the song');
      expect(s.songs.keys.where(ftsVersions.contains), isEmpty,
          reason: '${s.packPath}: by the song, never once per version');
    }
    // A sample shared with another song counts that song too — and only it.
    expect(result.samples.map((s) => s.songs.length).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(projects.map((x) => x.songKey).toSet().length));

    // The samples left out of the collection (over 1 MB) are reported missing,
    // each naming a project that exists.
    expect(result.missing, greaterThan(0));
    final names = {for (final x in projects) x.name};
    for (final x in result.problems) {
      expect(names, contains(x.project), reason: x.sample);
    }

    // The report, the missing list and the tree are written.
    for (final name in [kSamplePackReport, kSamplePackProblems, kSamplePackTree, kSamplePackManifest]) {
      expect(File(p.join(pack.path, name)).existsSync(), isTrue, reason: name);
    }
    final reportRows = File(p.join(pack.path, kSamplePackReport)).readAsLinesSync().skip(1)
        .where((l) => l.trim().isNotEmpty);
    // A row per sample: own audio left out is listed too, with no pack file.
    expect(reportRows.length, result.samples.length);
    expect(reportRows.where((l) => l.startsWith(',')).length, result.leftOut);

    // Again into the same folder: nothing new.
    final packBefore = _contents(pack)..removeWhere((k, _) => k.startsWith('sample_pack_'));
    final again = await SamplePackExporter(
            destination: pack.path,
            excludeMasterProjects: true,
            readReferences: _referencesWithin(lib.scratch))
        .export(projects);
    expect(again.added, 0);
    expect(again.alreadyInPack, result.added);
    expect(_contents(pack)..removeWhere((k, _) => k.startsWith('sample_pack_')), packBefore);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('stopped after the first project, it keeps what it copied and says so', () async {
    var read = 0;
    final result = await SamplePackExporter(destination: pack.path, readReferences: _referencesWithin(lib.scratch)).export(
      projects,
      onProgress: (u) => read = u.project,
      shouldStop: () => read > 1,
    );
    expect(result.stopped, isTrue);
    expect(result.projectsRead, lessThan(projects.length));
    for (final s in result.samples.where((s) => s.packPath != null)) {
      expect(File(p.join(pack.path, s.packPath!)).existsSync(), isTrue);
    }
    expect(File(p.join(pack.path, kSamplePackReport)).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
