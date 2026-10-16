// The DAW project collection under test/fixtures/projects/<daw>/<name>/ —
// real projects, one folder each, with what was read from them recorded in
// <name>.expected.json beside the folder. Shared by the corpus test, which
// checks the readers against those records, and the flows in test/flows/,
// which run whole chains of the app's services over copies of the projects.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/midi_clip.dart';

final fixtureRoot = Directory(p.join('test', 'fixtures', 'projects'));

const _projectExtensions = {
  '.cpr', '.npr', '.als', '.flp', '.rpp', '.song', '.bwproject', '.dawproject', '.ptx',
};

/// One project of the collection.
class Fixture {
  Fixture(this.daw, this.folder, {Fixture? copyOf}) : _original = copyOf;

  final String daw;
  final Directory folder;

  /// For a copy, the checked-in fixture it was copied from.
  final Fixture? _original;

  String get name => p.basename(folder.path);

  /// `<daw>/<name>`, as [copyFixtures] takes it.
  String get id => '$daw/$name';

  /// Beside the checked-in folder, a copy's included.
  File get expectedFile => _original?.expectedFile ?? File('${folder.path}.expected.json');

  /// What was recorded for it: each project file's reading, by file name.
  Map<String, Object?> get expected =>
      jsonDecode(expectedFile.readAsStringSync()) as Map<String, Object?>;

  /// What was recorded for [project], one of [projectFiles].
  Map<String, Object?> expectedFor(File project) =>
      expected[p.basename(project.path)]! as Map<String, Object?>;

  /// The project files: every file in the folder with a DAW extension — one
  /// project, or a folder of one song's versions.
  List<File> get projectFiles => projectFilesIn(folder);

  @override
  String toString() => id;
}

List<File> projectFilesIn(Directory folder) => folder
    .listSync()
    .whereType<File>()
    .where((f) => _projectExtensions.contains(p.extension(f.path).toLowerCase()))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Every project in the collection, in a stable order.
List<Fixture> allFixtures() => [
      if (fixtureRoot.existsSync())
        for (final daw in fixtureRoot.listSync().whereType<Directory>())
          for (final folder in daw.listSync().whereType<Directory>())
            Fixture(p.basename(daw.path), folder),
    ]..sort((a, b) => a.id.compareTo(b.id));

Fixture fixture(String id) => allFixtures().singleWhere((f) => f.id == id);

/// Copies the collection — or only the projects named in [only] — into
/// [to], as `<to>/<daw>/<name>/`. Flows work on copies: a scan, a move or an
/// archive must never touch the checked-in files.
Future<List<Fixture>> copyFixtures(Directory to, {Iterable<String>? only}) async {
  final chosen = [
    for (final f in allFixtures())
      if (only == null || only.contains(f.id)) f,
  ];
  final copies = <Fixture>[];
  for (final f in chosen) {
    final target = Directory(p.join(to.path, f.daw, f.name));
    await _copyTree(f.folder, target);
    copies.add(Fixture(f.daw, target, copyOf: f));
  }
  return copies;
}

Future<void> _copyTree(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(followLinks: false)) {
    final target = p.join(to.path, p.basename(e.path));
    if (e is Directory) {
      await _copyTree(e, Directory(target));
    } else if (e is File) {
      await e.copy(target);
    }
  }
}

/// A clip's notes and events in a dozen characters — the `content` the
/// .expected.json files record — so two clips can be compared at a glance.
/// Order-blind: a reader and the clip store may list the notes starting at
/// one tick in different orders, and that is the same clip.
String clipContentHash(MidiClip c) => _hash([
      ...[for (final n in c.notes) '${n.startTick}:${n.lengthTicks}:${n.pitch}:${n.velocity}:${n.channel}']
        ..sort(),
      ...[for (final e in c.events) '$e']..sort(),
    ]);

String _hash(List<String> parts) =>
    sha1.convert(utf8.encode(parts.join('\n'))).toString().substring(0, 12);
