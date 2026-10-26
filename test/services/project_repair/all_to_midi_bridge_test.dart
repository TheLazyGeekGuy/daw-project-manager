import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/all_to_midi_bridge.dart';

void main() {
  final validMidi = Uint8List.fromList([
    // MThd: SMF type 1, 1 track, 480 PPQ.
    0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6,
    0, 1, 0, 1, 1, 0xe0,
    // One MIDI note at velocity 100, released after 480 ticks.
    0x4d, 0x54, 0x72, 0x6b, 0, 0, 0, 13,
    0, 0x90, 0x3c, 0x64,
    0x83, 0x60, 0x80, 0x3c, 0x40,
    0, 0xff, 0x2f, 0,
  ]);

  test('accepts strict, bounded MIDI type 1 files', () {
    final result = AllToMidiOutputProbe.inspect(validMidi);
    expect(result.tracks, 1);
    expect(result.ppq, 480);
    expect(result.notes, 1);
  });

  test('refuses unexpected formats and truncated tracks', () {
    final formatZero = Uint8List.fromList(validMidi)..[9] = 0;
    expect(() => AllToMidiOutputProbe.inspect(formatZero), throwsFormatException);
    expect(
      () => AllToMidiOutputProbe.inspect(validMidi.sublist(0, 24)),
      throwsFormatException,
    );
  });

  late Directory root;
  late File source;
  late File application;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('all-to-midi-test-');
    source = File('${root.path}/original.ALL');
    await source.writeAsBytes([1, 2, 3, 4, 5]);
    application = File('${root.path}/AllToMidi.exe');
    await application.writeAsString('synthetic converter used only in tests');
  });
  tearDown(() => root.delete(recursive: true));

  test('blocks .ARR and non-Windows execution', () async {
    final bridge = AllToMidiBridge(
      runner: (_, __, ___, ____) async =>
          throw StateError('Must not execute'),
    );
    await expectLater(
      bridge.convert(
        original: source,
        executable: application,
        acknowledgeLosses: true,
      ),
      throwsUnsupportedError,
    );
    final mockWindows = AllToMidiBridge(
      windowsOverrideForTests: true,
      runner: (_, __, ___, ____) async =>
          throw StateError('Must not execute'),
    );
    final arr = File('${root.path}/arrangement.ARR');
    await arr.writeAsBytes([1, 2]);
    await expectLater(
      mockWindows.convert(
        original: arr,
        executable: application,
        acknowledgeLosses: true,
      ),
      throwsFormatException,
    );
  }, skip: Platform.isWindows);

  test('converts a staged copy while preserving original and backup', () async {
    String? stagedInput;
    final bridge = AllToMidiBridge(
      windowsOverrideForTests: true,
      runner: (_, args, __, ___) async {
        final index = args.indexOf('--output-folder');
        final outputFolder = Directory(args[index + 1]);
        stagedInput = args.last;
        expect(stagedInput, isNot(source.path));
        expect(await File(stagedInput!).readAsBytes(), [1, 2, 3, 4, 5]);
        await File('${outputFolder.path}/original.mid')
            .writeAsBytes(validMidi, flush: true);
        return const AllToMidiProcessOutcome(
          exitCode: 0,
          stdout: 'Saved: original.mid Tracks: 1 Notes: 1',
          stderr: '',
        );
      },
    );
    final result = await bridge.convert(
      original: source,
      executable: application,
      acknowledgeLosses: true,
    );
    expect(result.trackCount, 1);
    expect(result.noteCount, 1);
    expect(result.ppq, 480);
    expect(result.sourceSha256.length, 64);
    expect(result.outputSha256.length, 64);
    expect(await source.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await File(result.backupPath).readAsBytes(), [1, 2, 3, 4, 5]);
    expect(result.outputPath, contains('.project-repair-exports'));
    expect(await File(result.reportPath).exists(), true);
  });

  test('malformed converter output keeps a failure report and backup', () async {
    final bridge = AllToMidiBridge(
      windowsOverrideForTests: true,
      runner: (_, args, __, ___) async {
        final folder = Directory(args[args.indexOf('--output-folder') + 1]);
        await File('${folder.path}/original.mid').writeAsString('not-midi');
        return const AllToMidiProcessOutcome(
          exitCode: 0, stdout: '', stderr: '',
        );
      },
    );
    await expectLater(
      bridge.convert(
        original: source,
        executable: application,
        acknowledgeLosses: true,
      ),
      throwsFormatException,
    );
    final exports = Directory('${root.path}/.project-repair-exports');
    final run = (await exports.list().toList()).single;
    expect(await File('${run.path}/alltomidi-report.json').readAsString(),
        contains('"status": "failed"'));
    expect(await source.readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('rejects conversion until user acknowledges MIDI-only losses', () async {
    final bridge = AllToMidiBridge(windowsOverrideForTests: true);
    await expectLater(
      bridge.convert(
        original: source,
        executable: application,
        acknowledgeLosses: false,
      ),
      throwsFormatException,
    );
  });
}
