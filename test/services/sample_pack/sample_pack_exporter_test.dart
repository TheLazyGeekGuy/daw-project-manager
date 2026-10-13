import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/models/midi_clip.dart';
import 'package:daw_project_manager/models/sample_reference.dart';
import 'package:daw_project_manager/services/midi/midi_file_writer.dart';
import 'package:daw_project_manager/services/sample_pack/sample_classifier.dart';
import 'package:daw_project_manager/services/sample_pack/sample_pack_exporter.dart';

void main() {
  late Directory root;
  late String pack;

  /// What each project file "references", by path.
  late Map<String, List<SampleReference>> refsByProject;
  late Map<String, Duration> durations;
  late List<String> hashed;

  /// Every file whose contents were read: measured or hashed.
  late List<String> opened;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sample_pack_');
    pack = p.join(root.path, 'Pack');
    refsByProject = {};
    durations = {};
    hashed = [];
    opened = [];
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> file(List<String> parts, String content) async {
    final path = p.joinAll([root.path, ...parts]);
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString(content);
    return path;
  }

  /// A project file at [parts] that references [refs].
  Future<SamplePackProject> project(
    List<String> parts,
    List<SampleReference> refs, {
    String? name,
    String profile = 'Main',
    String? songKey,
  }) async {
    final path = await file(parts, 'project');
    refsByProject[path] = refs;
    return SamplePackProject(
      filePath: path,
      name: name ?? p.basenameWithoutExtension(path),
      profileName: profile,
      songKey: songKey ?? path,
    );
  }

  SampleReference ref(String path,
          {SampleKind? kind, SampleUse use = SampleUse.audio}) =>
      SampleReference(
        fileName: p.basename(path),
        candidates: [path],
        kind: kind,
        use: use,
      );

  SamplePackExporter exporter({
    bool includeOwnAudio = false,
    bool excludeMasterProjects = false,
  }) =>
      SamplePackExporter(
        destination: pack,
        includeOwnAudio: includeOwnAudio,
        excludeMasterProjects: excludeMasterProjects,
        readReferences: (path) async {
          final refs = refsByProject[path];
          if (refs == null) throw const FormatException('unreadable');
          return refs;
        },
        readDuration: (path) async {
          opened.add(path);
          return durations[p.basename(path)];
        },
        hashFile: (path) async {
          hashed.add(path);
          opened.add(path);
          return sha1OfFile(path);
        },
      );

  Future<List<String>> packFiles() async => [
        for (final e in await Directory(pack)
            .list(recursive: true)
            .where((e) => e is File)
            .toList())
          p.relative(e.path, from: pack).replaceAll(r'\', '/'),
      ]..sort();

  test('one sound used by two songs is one sample, used twice', () async {
    // The same kick copied into two projects' folders, and a library hat.
    final kickA = await file(['A', 'Audio', 'gataka_kick.wav'], 'KICK');
    final kickB = await file(['B', 'Audio', 'kick copy.wav'], 'KICK');
    final hat = await file(['Library', 'Hats', 'hat 1.wav'], 'HAT!!');
    durations.addAll({
      'gataka_kick.wav': const Duration(milliseconds: 300),
      'kick copy.wav': const Duration(milliseconds: 300),
      'hat 1.wav': const Duration(milliseconds: 200),
    });
    final result = await exporter().export([
      await project(['A', 'a.cpr'], [ref(kickA), ref(hat)], name: 'Song A'),
      await project(['B', 'b.cpr'], [ref(kickB)], name: 'Song B'),
    ]);

    expect(result.samples, hasLength(2));
    final kick = result.samples.firstWhere((s) => s.category == SampleCategory.kick);
    expect(kick.songs.values.toSet(), {'Song A', 'Song B'});
    expect(kick.paths, hasLength(2));
    expect(kick.origin, SampleOrigin.project);
    expect(result.added, 2);
    expect(await packFiles(), [
      'Hi-Hat/hat 1.wav',
      'Kick/gataka_kick.wav',
      kSamplePackManifest,
      kSamplePackProblems,
      kSamplePackReport,
      kSamplePackTree,
    ]);
    final tree = await File(p.join(pack, kSamplePackTree)).readAsString();
    expect(tree, contains('Pack/ (5)'),
        reason: 'every file in the folder but the tree itself');
    expect(tree, contains('├── Kick/ (1)\n│   └── gataka_kick.wav'));
    expect(hashed, isNot(contains(hat)),
        reason: 'a file of a size nothing else has is not hashed');
  });

  test('versions of one stack count as one song', () async {
    final snare = await file(['Lib', 'snare.wav'], 'SNARE');
    final result = await exporter().export([
      await project(['S', 'v1.cpr'], [ref(snare)],
          name: 'Stacked', songKey: 'stack-1'),
      await project(['S', 'v2.cpr'], [ref(snare)],
          name: 'Stacked', songKey: 'stack-1'),
    ]);
    expect(result.samples.single.songs, {'stack-1': 'Stacked'});
  });

  test('one project file in two profiles is read once, in both', () async {
    final clap = await file(['Lib', 'clap.wav'], 'CLAP');
    final a = await project(['P', 'p.cpr'], [ref(clap)], profile: 'Artist');
    final b = SamplePackProject(
      filePath: a.filePath,
      name: a.name,
      profileName: 'Label',
      songKey: 'other-id',
    );
    final result = await exporter().export([a, b]);
    expect(result.projectsRead, 1);
    expect(result.samples.single.profiles, {'Artist', 'Label'});
  });

  group('own audio', () {
    late List<SamplePackProject> projects;

    setUp(() async {
      final take = await file(['V', 'Audio', 'Vocals_03.wav'], 'TAKE');
      final kick = await file(['V', 'Audio', 'kick.wav'], 'KICK');
      projects = [
        await project(['V', 'v.cpr'], [
          ref(take, kind: SampleKind.recorded),
          ref(kick),
        ]),
      ];
    });

    test('is left out unless asked for, and never opened', () async {
      final result = await exporter().export(projects);
      expect(result.leftOut, 1);
      expect(opened.where((x) => x.contains('Vocals_03')), isEmpty,
          reason: 'reading a file can mean downloading it');
      expect(result.added, 1);
      expect(await packFiles(), contains('Kick/kick.wav'));
      expect((await packFiles()).where((f) => f.contains('Vocals_03')), isEmpty);
    });

    test('goes in a folder of its own when asked for', () async {
      final result = await exporter(includeOwnAudio: true).export(projects);
      expect(result.leftOut, 0);
      expect(await packFiles(),
          contains('$kOwnAudioFolder/Vocal/Vocals_03.wav'));
    });
  });

  test("a sampler's sample goes in even when it looks like a bounce",
      () async {
    final kick = await file(['Song', 'Audio', 'kick-01.wav'], 'TRIMMED');
    final result = await exporter().export([
      await project(['Song', 'song.cpr'], [
        ref(kick, use: SampleUse.sampler),
      ]),
    ]);
    expect(result.added, 1);
    expect(await packFiles(), contains('Kick/kick-01.wav'));
  });

  test('master projects are left unread when asked', () async {
    final stem = await file(['Song', 'Master Project', 'Audio', 'Drums.wav'],
        'STEM');
    final kick = await file(['Song', 'Audio', 'kick.wav'], 'KICK');
    final projects = [
      await project(['Song', 'Song.cpr'], [ref(kick)]),
      await project(['Song', 'Master Project', 'Song (Master).cpr'],
          [ref(stem)]),
    ];
    final skipped =
        await exporter(excludeMasterProjects: true).export(projects);
    expect(skipped.masterProjectsLeftOut, 1);
    expect(skipped.projectsRead, 1);
    expect([for (final s in skipped.samples) p.basename(s.paths.single)],
        ['kick.wav']);

    final read = await exporter().export(projects);
    expect(read.masterProjectsLeftOut, 0);
    expect(read.projectsRead, 2);
  });

  test('two different sounds with one name are both kept', () async {
    final k1 = await file(['A', 'kick.wav'], 'ONE');
    final k2 = await file(['B', 'kick.wav'], 'TWO!');
    await exporter().export([
      await project(['A', 'a.cpr'], [ref(k1)]),
      await project(['B', 'b.cpr'], [ref(k2)]),
    ]);
    expect(await packFiles(), containsAll(['Kick/kick.wav', 'Kick/kick (2).wav']));
  });

  group('exporting again', () {
    test('adds only what is new', () async {
      final kick = await file(['Lib', 'kick.wav'], 'KICK');
      final first = [await project(['A', 'a.cpr'], [ref(kick)])];
      expect((await exporter().export(first)).added, 1);

      final snare = await file(['Lib', 'snare.wav'], 'SNARE');
      final again = await exporter().export([
        ...first,
        await project(['B', 'b.cpr'], [ref(snare)]),
      ]);
      expect(again.added, 1);
      expect(again.alreadyInPack, 1);
    });

    test('finds a sample the user moved and renamed in the pack', () async {
      final kick = await file(['Lib', 'kick.wav'], 'KICK');
      final projects = [await project(['A', 'a.cpr'], [ref(kick)])];
      await exporter().export(projects);

      await Directory(p.join(pack, 'Favourites')).create();
      await File(p.join(pack, 'Kick', 'kick.wav'))
          .rename(p.join(pack, 'Favourites', 'best kick.wav'));
      final again = await exporter().export(projects);
      expect(again.added, 0);
      expect(again.samples.single.packPath, 'Favourites/best kick.wav');
      expect(await packFiles(), isNot(contains('Kick/kick.wav')));
    });

    test('the manifest saves re-reading unchanged pack files', () async {
      // Same size, different content: both sides must be hashed once.
      final a = await file(['Lib', 'a.wav'], 'AAAA');
      final b = await file(['Lib', 'b.wav'], 'BBBB');
      final projects = [await project(['A', 'a.cpr'], [ref(a), ref(b)])];
      await exporter().export(projects);
      final manifest = jsonDecode(
        await File(p.join(pack, kSamplePackManifest)).readAsString(),
      ) as Map;
      expect((manifest['files'] as Map).keys,
          containsAll(['Other/a.wav', 'Other/b.wav']));

      hashed.clear();
      final again = await exporter().export(projects);
      expect(again.added, 0);
      expect(hashed.where((h) => h.startsWith(pack)), isEmpty,
          reason: 'pack files keep their stored hashes');
    });
  });

  test('reports what it could not find or read', () async {
    final unsupported = await file(['X', 'song.bwproject'], 'x');
    final result = await exporter().export([
      await project(['A', 'a.cpr'],
          [ref(p.join(root.path, 'gone', 'lost kick.wav'))], name: 'Song A'),
      SamplePackProject(
        filePath: unsupported,
        name: 'Bitwig song',
        profileName: 'Main',
        songKey: 'b',
      ),
      SamplePackProject(
        filePath: p.join(root.path, 'missing.cpr'),
        name: 'Gone song',
        profileName: 'Main',
        songKey: 'g',
      ),
      SamplePackProject(
        filePath: await file(['U', 'u.cpr'], 'x'), // no refs: throws
        name: 'Broken song',
        profileName: 'Main',
        songKey: 'u',
      ),
    ]);
    expect(result.missing, 1);
    expect(result.projectsNotRead, 3);
    expect({for (final x in result.problems) x.project: x.problem}, {
      'Song A': SamplePackProblemKind.sampleNotFound,
      'Bitwig song': SamplePackProblemKind.formatNotSupported,
      'Gone song': SamplePackProblemKind.projectNotFound,
      'Broken song': SamplePackProblemKind.projectUnreadable,
    });
    final csv = await File(p.join(pack, kSamplePackProblems)).readAsString();
    expect(csv, contains('sample_not_found,Song A,Main,lost kick.wav,'));
  });

  test('the report lists every sample, most used first', () async {
    final kick = await file(['Lib', 'kick.wav'], 'KICK');
    final hat = await file(['Lib', 'hat.wav'], 'HAT!!');
    durations['kick.wav'] = const Duration(milliseconds: 250);
    await exporter().export([
      await project(['A', 'a.cpr'], [ref(kick)], name: 'Beta, the song'),
      await project(['B', 'b.cpr'], [ref(kick), ref(hat)], name: 'Alpha'),
    ]);
    final bytes = await File(p.join(pack, kSamplePackReport)).readAsBytes();
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF],
        reason: 'a BOM, so Excel reads accented names as UTF-8');
    final lines = const LineSplitter()
        .convert(utf8.decode(bytes).replaceFirst('﻿', ''));
    expect(lines.first, startsWith('pack_file,category,songs,'));
    expect(lines[1],
        startsWith('Kick/kick.wav,Kick,2,"Alpha; Beta, the song",Main,library,0.25,'));
    expect(lines[2], startsWith('Hi-Hat/hat.wav,Hi-Hat,1,Alpha,'));
  });

  test('works project by project: stopping keeps what was copied', () async {
    final kick = await file(['Lib', 'kick.wav'], 'KICK');
    final snare = await file(['Lib', 'snare.wav'], 'SNARE');
    var stopNow = false;
    final result = await exporter().export(
      [
        await project(['A', 'a.cpr'], [ref(kick)]),
        await project(['B', 'b.cpr'], [ref(snare)]),
      ],
      onProgress: (u) {
        if (u.project == 1) stopNow = true; // as the second one starts
      },
      shouldStop: () => stopNow,
    );
    expect(result.stopped, isTrue);
    expect(result.added, 1);
    final files = await packFiles();
    expect(files, contains('Kick/kick.wav'));
    expect(files.where((f) => f.contains('snare')), isEmpty);
    expect(files, containsAll([kSamplePackReport, kSamplePackManifest]),
        reason: 'the report covers what was done before the stop');
  });

  test('a file the size of a stem is left out without being opened',
      () async {
    final stem = p.join(root.path, 'Song', 'Audio', 'Drums.wav');
    await Directory(p.dirname(stem)).create(recursive: true);
    await File(stem).writeAsBytes(List.filled(kLongAudioBytes, 0));
    final result = await exporter().export(
      [await project(['Song', 'song.cpr'], [ref(stem)])],
    );
    expect(result.samples.single.origin, SampleOrigin.long);
    expect(result.leftOut, 1);
    expect(opened, isEmpty);
  });

  test('reports progress through each phase, always moving forward',
      () async {
    final kick = await file(['Lib', 'kick.wav'], 'KICK');
    final phases = <SamplePackPhase>{};
    final fractions = <double>[];
    await exporter().export(
      [await project(['A', 'a.cpr'], [ref(kick)])],
      onProgress: (u) {
        phases.add(u.phase);
        fractions.add(u.fraction);
      },
    );
    expect(phases, containsAll([
      SamplePackPhase.reading,
      SamplePackPhase.locating,
      SamplePackPhase.measuring,
      SamplePackPhase.copying,
      SamplePackPhase.finishing,
    ]));
    for (var i = 1; i < fractions.length; i++) {
      expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]));
    }
    expect(fractions.last, 1);
  });

  test('writes MIDI collections under MIDI, one folder each', () async {
    const clip = MidiClip(
      name: 'Lead',
      ppq: 480,
      lengthTicks: 1920,
      notes: [MidiNote(startTick: 0, lengthTicks: 480, pitch: 60, velocity: 100)],
    );
    final result = await exporter().export(const [], midi: [
      const SamplePackMidiFolder('Leads: best', [
        MidiExport(clip, bpm: 140, name: 'Lead 01.mid'),
      ]),
    ]);
    expect(result.midiFiles, 1);
    expect(await packFiles(), contains('MIDI/Leads_ best/Lead 01.mid'));
  });
}
