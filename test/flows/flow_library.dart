// A library for the flows: a real Hive database in a temp folder, one scan
// folder holding copies of DAW projects from the collection, and the scans
// the app runs — through the same services, with no window. Each flow
// drives a whole feature through it and checks what comes out the far end
// against what went in.

import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/models/music_project.dart';
import 'package:daw_project_manager/models/scan_root.dart';
import 'package:daw_project_manager/models/stored_midi_clips.dart';
import 'package:daw_project_manager/repository/project_repository.dart';
import 'package:daw_project_manager/services/scan_import_service.dart';
import 'package:daw_project_manager/services/scanner_service.dart';

import '../fixtures/fixture_collection.dart';
import '../helpers/hive_test_helper.dart';

class FlowLibrary {
  FlowLibrary._(this._hiveDir, this.scratch, this.projectsDir, this.fixtures, this.profileId);

  final Directory _hiveDir;

  /// Somewhere of the flow's own for anything it writes (exports, archives,
  /// backups), deleted with the library.
  final Directory scratch;

  /// The scan folder: `<daw>/<name>/` copies of [fixtures].
  final Directory projectsDir;

  /// The copies, in the scan folder.
  final List<Fixture> fixtures;

  final String profileId;
  late ProjectRepository repo;
  late ScanRoot root;

  /// A fresh library scanning copies of the collection — or of the projects
  /// named in [only] (`'<daw>/<name>'`) — not yet scanned.
  static Future<FlowLibrary> open({Iterable<String>? only, String profileId = 'flow'}) async {
    final hiveDir = await HiveTestHelper.setUp();
    final scratch = await Directory.systemTemp.createTemp('dpm_flow_');
    final projectsDir = Directory(p.join(scratch.path, 'Projects'));
    final copies = await copyFixtures(projectsDir, only: only);
    final lib = FlowLibrary._(hiveDir, scratch, projectsDir, copies, profileId);
    lib.repo = await HiveTestHelper.createRepository(profileId: profileId);
    lib.root = await lib.repo.addRoot(projectsDir.path);
    return lib;
  }

  /// The scan the app runs when a folder is added or rescanned: finds the
  /// projects, reads their tempo and key, not their contents.
  Future<int> scan() => importProjectsFromRoot(repo, root.id, root.path);

  /// Deep Scan: the same walk, reading every project's contents too —
  /// stats, MIDI clips — as the dashboard's button does.
  Future<void> deepScan() async {
    final ignored = repo.getIgnoredPaths().map((e) => e.path).toList();
    final entities = await ScannerService()
        .scanDirectory(root.path, ignoredPaths: ignored)
        .toList();
    await repo.upsertManyFromFileSystemEntities(entities, fullMetadata: true);
    await repo.autoStackFolders();
  }

  /// Every project row (stacks included).
  List<MusicProject> get projects => repo.getAllProjects();

  /// Every project file of the copies, with the fixture it belongs to.
  List<(Fixture, File)> get projectFiles => [
        for (final f in fixtures)
          for (final file in f.projectFiles) (f, file),
      ];

  /// The row for [file], a project file in the scan folder.
  MusicProject projectOf(File file) {
    final path = p.normalize(file.path);
    return projects.singleWhere((r) => !r.isVirtual && p.normalize(r.filePath) == path);
  }

  Future<StoredMidiClips?> clipsOf(File file) => repo.midiClips.get(projectOf(file).id);

  /// Closes the database and opens it again, as quitting and relaunching
  /// the app does: whatever a flow checks after this was really stored.
  Future<void> reopen() async {
    await Hive.close();
    repo = await HiveTestHelper.createRepository(profileId: profileId);
    root = repo.getRoots().single;
  }

  Future<void> close() async {
    await HiveTestHelper.tearDown(_hiveDir);
    if (await scratch.exists()) await scratch.delete(recursive: true);
  }
}
