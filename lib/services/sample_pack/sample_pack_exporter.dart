import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../models/sample_reference.dart';
import '../../utils/audio_file_info.dart';
import '../midi/midi_clip_service.dart';
import '../midi/midi_file_writer.dart';
import 'project_sample_reader.dart';
import 'sample_classifier.dart';
import 'sample_locator.dart';

/// One project to collect samples from.
class SamplePackProject {
  const SamplePackProject({
    required this.filePath,
    required this.name,
    required this.profileName,
    required this.songKey,
  });

  final String filePath;

  /// What the report calls the song this project is.
  final String name;
  final String profileName;

  /// Projects with the same key are one song — the versions in a version
  /// stack — and count as one use of a sample.
  final String songKey;
}

/// A folder of `.mid` files to write under the pack's `MIDI` folder.
class SamplePackMidiFolder {
  const SamplePackMidiFolder(this.name, this.exports);
  final String name;
  final List<MidiExport> exports;
}

/// What the export is doing, for its progress line.
enum SamplePackPhase { reading, locating, measuring, copying, midi, finishing }

typedef SamplePackProgress = void Function(
  SamplePackPhase phase,
  int done,
  int total,
  String current,
);

/// One distinct sound, however many projects and folders hold a copy.
class PackSample {
  PackSample(this.identity);

  /// Content identity: files with the same one are the same sound.
  final String identity;

  /// Every located copy, the one copied into the pack first.
  final List<String> paths = [];
  int sizeBytes = 0;
  Duration? duration;
  SampleCategory category = SampleCategory.other;
  SampleOrigin origin = SampleOrigin.project;

  /// Songs using it, by [SamplePackProject.songKey], with their names.
  final Map<String, String> songs = {};
  final Set<String> profiles = {};

  /// Where it is in the pack (forward slashes), or null when left out.
  String? packPath;

  /// Whether this export copied it in (false: it was there already, or it
  /// was left out).
  bool added = false;
}

/// A reference that couldn't be followed, or a project that couldn't be
/// read, for the report.
class SamplePackProblem {
  const SamplePackProblem({
    required this.project,
    required this.profile,
    required this.problem,
    this.sample = '',
    this.where = '',
  });

  final String project;
  final String profile;
  final SamplePackProblemKind problem;
  final String sample;
  final String where;
}

enum SamplePackProblemKind {
  sampleNotFound('sample_not_found'),
  projectNotFound('project_not_found'),
  projectUnreadable('project_unreadable'),
  formatNotSupported('format_not_supported');

  const SamplePackProblemKind(this.code);

  /// How the report writes it.
  final String code;
}

class SamplePackResult {
  const SamplePackResult({
    required this.samples,
    required this.problems,
    required this.projectsRead,
    required this.midiFiles,
    required this.stopped,
  });

  final List<PackSample> samples;
  final List<SamplePackProblem> problems;
  final int projectsRead;
  final int midiFiles;
  final bool stopped;

  int get added => samples.where((s) => s.added).length;
  int get alreadyInPack =>
      samples.where((s) => s.packPath != null && !s.added).length;

  /// Own audio left out because the export wasn't asked to include it.
  int get leftOut => samples.where((s) => s.packPath == null).length;
  int get missing => problems
      .where((x) => x.problem == SamplePackProblemKind.sampleNotFound)
      .length;
  int get projectsNotRead => problems
      .where((x) => x.problem != SamplePackProblemKind.sampleNotFound)
      .length;
}

/// The files the export writes beside the samples.
const kSamplePackManifest = 'sample_pack_manifest.json';
const kSamplePackReport = 'sample_pack_report.csv';
const kSamplePackProblems = 'sample_pack_missing.csv';

/// The folder own audio goes in when it is included, so it stays apart from
/// the samples.
const kOwnAudioFolder = 'Recordings, Bounces & Stems';
const kMidiFolder = 'MIDI';

/// Collects the samples a set of projects use into one folder, sorted into
/// category folders, with a report of how often each is used.
///
/// Running it again on the same folder only adds what isn't there yet: every
/// sample is compared by content with what the folder holds — wherever the
/// user has moved or renamed it since — so nothing is copied twice.
/// `sample_pack_manifest.json` remembers each pack file's size, date and
/// hash so the comparison doesn't re-read the whole pack every time.
class SamplePackExporter {
  SamplePackExporter({
    required this.destination,
    this.includeOwnAudio = false,
    SampleLocator? locator,
    this.readReferences = readProjectSampleReferences,
    this.canRead = canReadSampleReferences,
    this.readDuration = readAudioDuration,
    this.hashFile = sha1OfFile,
  }) : locator = locator ?? SampleLocator();

  final String destination;

  /// Whether recordings, bounces and stems go into the pack too.
  final bool includeOwnAudio;
  final SampleLocator locator;

  final Future<List<SampleReference>> Function(String filePath) readReferences;
  final bool Function(String filePath) canRead;
  final Future<Duration?> Function(String path) readDuration;
  final Future<String> Function(String path) hashFile;

  Future<SamplePackResult> export(
    List<SamplePackProject> projects, {
    List<SamplePackMidiFolder> midi = const [],
    SamplePackProgress? onProgress,
    bool Function()? shouldStop,
  }) async {
    void progress(SamplePackPhase phase, int done, int total, String current) =>
        onProgress?.call(phase, done, total, current);
    bool stop() => shouldStop?.call() ?? false;

    final problems = <SamplePackProblem>[];
    var stopped = false;

    // One project file in two profiles is read once and belongs to both.
    final byFile = <String, (SamplePackProject, Set<String>)>{};
    for (final project in projects) {
      final key = _pathKey(project.filePath);
      byFile.putIfAbsent(key, () => (project, <String>{}))
          .$2
          .add(project.profileName);
    }

    // 1. Read every project's references.
    final read = <(SamplePackProject, Set<String>, List<SampleReference>)>[];
    var done = 0;
    for (final (project, profiles) in byFile.values) {
      if (stop()) {
        stopped = true;
        break;
      }
      progress(SamplePackPhase.reading, done++, byFile.length, project.name);
      SamplePackProblem problem(SamplePackProblemKind kind) =>
          SamplePackProblem(
            project: project.name,
            profile: profiles.join(', '),
            problem: kind,
            where: project.filePath,
          );
      if (!canRead(project.filePath)) {
        problems.add(problem(SamplePackProblemKind.formatNotSupported));
        continue;
      }
      if (!await File(project.filePath).exists()) {
        problems.add(problem(SamplePackProblemKind.projectNotFound));
        continue;
      }
      try {
        read.add((project, profiles, await readReferences(project.filePath)));
      } catch (_) {
        problems.add(problem(SamplePackProblemKind.projectUnreadable));
      }
    }

    // 2. Find each referenced file. Grouped by path: two projects using the
    // same library file share one entry.
    final located = <String, _Located>{};
    final total = read.fold<int>(0, (n, r) => n + r.$3.length);
    done = 0;
    outer:
    for (final (project, profiles, refs) in read) {
      final projectDir = p.dirname(project.filePath);
      final seen = <String>{};
      for (final ref in refs) {
        if (stop()) {
          stopped = true;
          break outer;
        }
        progress(SamplePackPhase.locating, done++, total, ref.fileName);
        final path = await locator.locate(ref, projectDir: projectDir);
        if (path == null) {
          if (seen.add('missing:${ref.fileName.toLowerCase()}')) {
            problems.add(SamplePackProblem(
              project: project.name,
              profile: profiles.join(', '),
              problem: SamplePackProblemKind.sampleNotFound,
              sample: ref.fileName,
              where: ref.candidates.firstOrNull ?? '',
            ));
          }
          continue;
        }
        final key = _pathKey(path);
        final entry = located.putIfAbsent(key, () => _Located(path));
        entry.uses.add((project, profiles, ref, projectDir));
      }
    }

    // 3. Measure: size, length and where it came from.
    done = 0;
    for (final entry in located.values) {
      if (stop()) {
        stopped = true;
        break;
      }
      progress(SamplePackPhase.measuring, done++, located.length,
          p.basename(entry.path));
      try {
        entry.size = await File(entry.path).length();
      } catch (_) {
        continue; // Gone since it was found.
      }
      entry.duration = await readDuration(entry.path);
      entry.measured = true;
    }
    if (stopped) {
      // Stopped before anything was copied: leave the folder as it was.
      return SamplePackResult(
        samples: const [],
        problems: problems,
        projectsRead: read.length,
        midiFiles: 0,
        stopped: true,
      );
    }
    located.removeWhere((_, e) => !e.measured);

    // 4. What the pack folder already holds, and content identities for
    // both sides: files are told apart by size, and only those sharing a
    // size with another are hashed.
    final manifest = await _Manifest.read(destination);
    final packFiles = await _packAudioFiles(destination);
    final sizes = <String, int>{
      for (final e in located.values) e.path: e.size,
      for (final f in packFiles) f.path: f.size,
    };
    final hashCache = <String, String>{
      for (final f in packFiles) f.path: ?manifest.hashFor(f),
    };
    final identities = await contentIdentities(
      sizes,
      (path) async => hashCache[path] ??= await hashFile(path),
    );

    final inPack = <String, String>{}; // identity -> relative path
    for (final f in packFiles) {
      inPack.putIfAbsent(identities[f.path]!, () => f.relative);
    }

    // 5. One sample per identity.
    final samples = <String, PackSample>{};
    for (final entry in located.values) {
      final id = identities[entry.path]!;
      final sample = samples.putIfAbsent(id, () => PackSample(id));
      sample.paths.add(entry.path);
      sample.sizeBytes = entry.size;
      sample.duration ??= entry.duration;
      for (final (project, profiles, _, _) in entry.uses) {
        sample.songs.putIfAbsent(project.songKey, () => project.name);
        sample.profiles.addAll(profiles);
      }
    }
    for (final sample in samples.values) {
      final origins = [
        for (final path in sample.paths)
          for (final (_, _, ref, projectDir) in located[_pathKey(path)]!.uses)
            sampleOriginOf(
              path: path,
              projectDir: projectDir,
              kind: ref.kind,
              duration: sample.duration,
            ),
      ];
      sample.origin = combinedOrigin(origins);
      final first = sample.paths.first;
      final home = located[_pathKey(first)]!
          .uses
          .map((u) => u.$4)
          .where((dir) => p.isWithin(dir, first))
          .firstOrNull;
      sample.category = sampleCategoryOf(
        first,
        duration: sample.duration,
        projectDir: home,
      );
    }

    // 6. Copy what isn't in the pack yet.
    final taken = <String>{
      for (final f in packFiles) f.relative.toLowerCase(),
    };
    final ordered = samples.values.toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));
    final toCopy = <PackSample>[];
    for (final sample in ordered) {
      final existing = inPack[sample.identity];
      if (existing != null) {
        sample.packPath = existing;
        continue;
      }
      if (sample.origin.isOwnAudio && !includeOwnAudio) continue;
      final folder = [
        if (sample.origin.isOwnAudio) kOwnAudioFolder,
        sample.category.folder,
      ].join('/');
      final name = packFileName(p.basename(sample.paths.first), sample.category);
      sample.packPath = _unique('$folder/$name', taken);
      toCopy.add(sample);
    }

    final written = <_PackFile>[...packFiles];
    done = 0;
    for (final sample in toCopy) {
      if (stop()) {
        stopped = true;
        sample.packPath = null;
        continue;
      }
      progress(SamplePackPhase.copying, done++, toCopy.length, sample.packPath!);
      final target = p.joinAll([destination, ...sample.packPath!.split('/')]);
      try {
        await Directory(p.dirname(target)).create(recursive: true);
        final part = '$target.part';
        await File(sample.paths.first).copy(part);
        await File(part).rename(target);
        sample.added = true;
        final stat = await File(target).stat();
        written.add(_PackFile(target, sample.packPath!, stat.size, stat.modified));
        if (hashCache[sample.paths.first] case final h?) hashCache[target] = h;
      } catch (_) {
        sample.packPath = null;
      }
    }

    // 7. MIDI collections, rewritten whole: they are the app's own data.
    var midiFiles = 0;
    if (!stopped) {
      done = 0;
      for (final folder in midi) {
        progress(SamplePackPhase.midi, done++, midi.length, folder.name);
        final files = await MidiClipService.exportAll(
          folder.exports,
          Directory(p.join(destination, kMidiFolder, _safeName(folder.name))),
        );
        midiFiles += files.length;
      }
    }

    // 8. Manifest and report.
    progress(SamplePackPhase.finishing, 0, 1, kSamplePackReport);
    await _Manifest.write(destination, written, hashCache);
    final result = SamplePackResult(
      samples: ordered,
      problems: problems,
      projectsRead: read.length,
      midiFiles: midiFiles,
      stopped: stopped,
    );
    await File(p.join(destination, kSamplePackReport))
        .writeAsString(samplePackReportCsv(result.samples), flush: true);
    await File(p.join(destination, kSamplePackProblems))
        .writeAsString(samplePackProblemsCsv(problems), flush: true);
    return result;
  }

  /// `Kick/x.wav`, or `Kick/x (2).wav` when that is taken (case-insensitive:
  /// Windows and macOS would see the same file).
  static String _unique(String relative, Set<String> taken) {
    var candidate = relative;
    final dot = relative.lastIndexOf('.');
    final stem = dot < 0 ? relative : relative.substring(0, dot);
    final ext = dot < 0 ? '' : relative.substring(dot);
    for (var n = 2; !taken.add(candidate.toLowerCase()); n++) {
      candidate = '$stem ($n)$ext';
    }
    return candidate;
  }

  static String _safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceFirst(RegExp(r'[. ]+$'), '')
        .trim();
    return cleaned.isEmpty ? 'MIDI' : cleaned;
  }

  /// Every audio file in the pack folder, outside its MIDI folder.
  static Future<List<_PackFile>> _packAudioFiles(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final out = <_PackFile>[];
    await for (final entity
        in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
      if (entity is! File || !isSampleAudioFile(entity.path)) continue;
      final relative = p.relative(entity.path, from: root).replaceAll(r'\', '/');
      if (relative.startsWith('$kMidiFolder/')) continue;
      try {
        final stat = await entity.stat();
        out.add(_PackFile(entity.path, relative, stat.size, stat.modified));
      } catch (_) {
        // Gone while listing.
      }
    }
    return out;
  }
}

/// A path as a map key: normalised, and case-blind where the file system is.
String _pathKey(String path) {
  final n = p.normalize(path);
  return Platform.isLinux ? n : n.toLowerCase();
}

class _Located {
  _Located(this.path);
  final String path;
  final uses = <(SamplePackProject, Set<String>, SampleReference, String)>[];
  int size = 0;
  Duration? duration;
  bool measured = false;
}

class _PackFile {
  const _PackFile(this.path, this.relative, this.size, this.modified);
  final String path;
  final String relative;
  final int size;
  final DateTime modified;
}

/// Content identities for the files in [sizes] (path → size). A file of a
/// size no other file has is told apart by size alone; files sharing a size
/// are hashed with [hashOf]. Equal identities mean equal content.
Future<Map<String, String>> contentIdentities(
  Map<String, int> sizes,
  Future<String> Function(String path) hashOf,
) async {
  final bySize = <int, List<String>>{};
  sizes.forEach((path, size) => bySize.putIfAbsent(size, () => []).add(path));
  final out = <String, String>{};
  for (final MapEntry(key: size, value: paths) in bySize.entries) {
    if (paths.length == 1) {
      out[paths.single] = 'size:$size';
      continue;
    }
    for (final path in paths) {
      out[path] = 'sha1:${await hashOf(path)}';
    }
  }
  return out;
}

/// The SHA-1 of the file at [path], read in a background isolate.
Future<String> sha1OfFile(String path) => Isolate.run(
      () => sha1.convert(File(path).readAsBytesSync()).toString(),
    );

/// `sample_pack_manifest.json`: each pack file's size, modification time and
/// (once one was needed) hash, by path relative to the pack.
class _Manifest {
  _Manifest(this._entries);

  final Map<String, Map<String, dynamic>> _entries;

  static Future<_Manifest> read(String root) async {
    try {
      final json = jsonDecode(
        await File(p.join(root, kSamplePackManifest)).readAsString(),
      );
      final files = (json as Map)['files'] as Map;
      return _Manifest({
        for (final e in files.entries)
          if (e.value is Map) e.key as String: Map<String, dynamic>.from(e.value),
      });
    } catch (_) {
      return _Manifest({});
    }
  }

  /// The stored hash of [f], if the file is unchanged since it was taken.
  String? hashFor(_PackFile f) {
    final entry = _entries[f.relative];
    if (entry == null) return null;
    if (entry['size'] != f.size ||
        entry['modified'] != f.modified.millisecondsSinceEpoch) {
      return null;
    }
    return entry['sha1'] as String?;
  }

  static Future<void> write(
    String root,
    List<_PackFile> files,
    Map<String, String> hashes,
  ) async {
    await Directory(root).create(recursive: true);
    final json = {
      'version': 1,
      'files': {
        for (final f in files)
          f.relative: {
            'size': f.size,
            'modified': f.modified.millisecondsSinceEpoch,
            'sha1': ?hashes[f.path],
          },
      },
    };
    await File(p.join(root, kSamplePackManifest)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  }
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  return RegExp(r'[",\n\r]').hasMatch(text)
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

/// UTF-8's byte order mark, so Excel reads accented names correctly.
const _bom = '﻿';

/// `sample_pack_report.csv`: one row per distinct sample, most used first —
/// where it is in the pack (empty when left out), its category, how many
/// songs use it and which, its origin, length and the file it was copied
/// from.
String samplePackReportCsv(List<PackSample> samples) {
  final out = StringBuffer(_bom)
    ..writeln([
      'pack_file',
      'category',
      'songs',
      'song_names',
      'profiles',
      'origin',
      'seconds',
      'source_file',
      'other_copies',
    ].join(','));
  for (final s in samples) {
    out.writeln([
      s.packPath,
      s.category.folder,
      s.songs.length,
      (s.songs.values.toList()..sort()).join('; '),
      (s.profiles.toList()..sort()).join('; '),
      s.origin.name,
      s.duration == null
          ? null
          : (s.duration!.inMilliseconds / 1000).toStringAsFixed(2),
      s.paths.first,
      s.paths.skip(1).join('; '),
    ].map(_csvCell).join(','));
  }
  return out.toString();
}

/// `sample_pack_missing.csv`: samples that couldn't be found and projects
/// that couldn't be read.
String samplePackProblemsCsv(List<SamplePackProblem> problems) {
  final out = StringBuffer(_bom)
    ..writeln(['problem', 'project', 'profile', 'sample', 'where'].join(','));
  for (final x in problems) {
    out.writeln([x.problem.code, x.project, x.profile, x.sample, x.where]
        .map(_csvCell)
        .join(','));
  }
  return out.toString();
}
