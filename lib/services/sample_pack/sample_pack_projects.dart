import '../../models/music_project.dart';
import 'sample_pack_exporter.dart';

/// The project files of one profile a sample pack reads.
///
/// A version stack is left out — it has no file of its own, its versions
/// are read instead — and so is an archived project, whose files are zipped
/// away. Versions of one stack are one song: they share the stack's name and
/// count as one use of a sample, however many of them use it.
List<SamplePackProject> samplePackProjectsOf(
  List<MusicProject> projects, {
  required String profileName,
}) {
  final byId = {for (final project in projects) project.id: project};
  return [
    for (final project in projects)
      if (!project.isVirtual && !project.isArchived)
        SamplePackProject(
          filePath: project.filePath,
          name: byId[project.stackId]?.displayName ?? project.displayName,
          profileName: profileName,
          songKey: project.stackId ?? project.id,
        ),
  ];
}

/// [names] made unique case-insensitively, a repeat becoming "Name (2)" —
/// two MIDI collections with one name must not write into one folder.
List<String> uniqueFolderNames(List<String> names) {
  final taken = <String>{};
  return [
    for (final name in names)
      () {
        var candidate = name;
        for (var n = 2; !taken.add(candidate.toLowerCase()); n++) {
          candidate = '$name ($n)';
        }
        return candidate;
      }(),
  ];
}
