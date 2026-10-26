import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/reaper_sidecar_stager.dart';

void main() {
  late Directory root;
  late Directory stage;
  late File song;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reaper-sidecar-');
    stage = Directory('${root.path}/stage');
    await stage.create();
    song = File('${root.path}/session.rpp');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'copies and verifies only explicit relative FILE dependencies',
    () async {
      await song.writeAsString('''
<REAPER_PROJECT 0.1
<TRACK
<SOURCE WAVE
FILE "Audio/short loop.wav"
>
>
<SOURCE MIDI
FILE "MIDI/lead.mid"
>
>
''');
      final audio = File('${root.path}/Audio/short loop.wav');
      await audio.parent.create();
      await audio.writeAsBytes([1, 2, 3, 4, 5]);
      final midi = File('${root.path}/MIDI/lead.mid');
      await midi.parent.create();
      await midi.writeAsBytes([0x4d, 0x54, 0x68, 0x64]);
      final before = await audio.readAsBytes();

      final report = await ReaperSidecarStager.stage(
        original: song,
        workspace: stage,
      );

      expect(report.files, hasLength(2));
      expect(report.totalBytes, 9);
      expect(
        await File('${stage.path}/Audio/short loop.wav').readAsBytes(),
        before,
      );
      expect(await File('${stage.path}/MIDI/lead.mid').readAsBytes(), [
        0x4d,
        0x54,
        0x68,
        0x64,
      ]);
      expect(await audio.readAsBytes(), before);
      expect(report.toJson()['opaque_plugin_media_verified'], false);
    },
  );

  test(
    'rejects missing external audio instead of silently dropping it',
    () async {
      await song.writeAsString('<REAPER_PROJECT\nFILE "missing.wav"\n>');
      await expectLater(
        ReaperSidecarStager.stage(original: song, workspace: stage),
        throwsFormatException,
      );
    },
  );

  test('rejects traversal and host-dependent absolute references', () async {
    for (final reference in [
      '../private.wav',
      'C:\\Sounds\\demo.wav',
      '/mnt/media/demo.wav',
    ]) {
      await song.writeAsString('<REAPER_PROJECT\nFILE "$reference"\n>');
      await expectLater(
        ReaperSidecarStager.stage(original: song, workspace: stage),
        throwsFormatException,
      );
    }
  });

  test('enforces total byte limits before copying media', () async {
    await song.writeAsString('<REAPER_PROJECT\nFILE "big.wav"\n>');
    await File('${root.path}/big.wav').writeAsBytes([1, 2, 3]);
    await expectLater(
      ReaperSidecarStager.stage(original: song, workspace: stage, maxBytes: 2),
      throwsFormatException,
    );
  });

  test('cannot overwrite the staged project with a media reference', () async {
    await song.writeAsString('<REAPER_PROJECT\nFILE "session.rpp"\n>');
    final stagedProject = File('${stage.path}/session.rpp');
    await stagedProject.writeAsString('keep');
    await expectLater(
      ReaperSidecarStager.stage(original: song, workspace: stage),
      throwsA(isA<FileSystemException>()),
    );
    expect(await stagedProject.readAsString(), 'keep');
  });

  test(
    'materializes generated output references into portable hashed paths',
    () async {
      final output = File('${stage.path}/converted.rpp');
      final media = File('${root.path}/runtime/generated.wav');
      await media.parent.create();
      await media.writeAsBytes([1, 2, 3]);
      await output.writeAsString('<REAPER_PROJECT\nFILE "${media.path}"\n>');
      final report = await ReaperSidecarStager.materializeOutput(
        output: output,
        trustedWorkspace: root,
      );
      final content = await output.readAsString();
      expect(content, contains('FILE "media/'));
      expect(content, isNot(contains(root.path)));
      final file = (report['files'] as List).single;
      expect(
        await File('${stage.path}/${file['relative_path']}').readAsBytes(),
        [1, 2, 3],
      );
      expect(await media.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'generated output cannot import files outside its conversion workspace',
    () async {
      final output = File('${stage.path}/converted.rpp');
      final outside = File('${root.path}/private.wav');
      await outside.writeAsBytes([42]);
      await output.writeAsString('<REAPER_PROJECT\nFILE "${outside.path}"\n>');
      await expectLater(
        ReaperSidecarStager.materializeOutput(
          output: output,
          trustedWorkspace: stage,
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
