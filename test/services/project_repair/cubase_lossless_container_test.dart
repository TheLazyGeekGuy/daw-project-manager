import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:daw_project_manager/services/project_repair/cubase_lossless_container.dart';
import 'package:daw_project_manager/services/project_repair/cubase_preservation_service.dart';

Uint8List _fixture() {
  final chunks = BytesBuilder();
  void add(String tag, List<int> payload) {
    chunks.add(ascii.encode(tag));
    chunks.add(
      (ByteData(
        4,
      )..setUint32(0, payload.length, Endian.big)).buffer.asUint8List(),
    );
    chunks.add(payload);
  }

  add('ROOT', [0, 255, 128]);
  add('ARCH', [0xff, 0xff, 0xff, 0xff, 0, 1, 2, 3, 0]);
  add('XUNK', [255, 0, 254, 0, 100]);
  add('ARCH', []);
  final body = chunks.toBytes();
  return (BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add(
          (ByteData(
            4,
          )..setUint32(0, body.length, Endian.big)).buffer.asUint8List(),
        )
        ..add(ascii.encode('NUND'))
        ..add(body))
      .toBytes();
}

void main() {
  test('reconstructs framing and preserves odd and unknown chunks exactly', () {
    final source = _fixture();
    final document = CubaseLosslessContainer.parse(source);
    expect(document.serializeUnchanged(), orderedEquals(source));
    expect(document.manifest.chunks, hasLength(4));
    final report = document.verificationReport();
    expect(report['byte_identical'], isTrue);
    expect(report['mutations_enabled'], isFalse);
    expect((report['validation'] as Map)['native_daw_reopen'], 'not-run');
  });

  test('source and returned chunk bytes cannot mutate preserved snapshot', () {
    final source = _fixture();
    final expected = Uint8List.fromList(source);
    final document = CubaseLosslessContainer.parse(source);
    source.fillRange(0, source.length, 0);
    document.chunkPayload(1).fillRange(0, 9, 77);
    expect(document.serializeUnchanged(), orderedEquals(expected));
  });

  test('rejects corrupted container length and chunk overrun', () {
    final source = _fixture();
    final corruptLength = Uint8List.fromList(source)..[7] ^= 1;
    expect(
      () => CubaseLosslessContainer.parse(corruptLength),
      throwsFormatException,
    );
    ByteData.sublistView(source).setUint32(16, 0xffffffff, Endian.big);
    expect(() => CubaseLosslessContainer.parse(source), throwsFormatException);
  });

  test(
    'preserves source with verified backup and distinct output per run',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cpr-preservation-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = await File(
        p.join(directory.path, 'sample.cpr'),
      ).writeAsBytes(_fixture());
      final expectedHash = sha256
          .convert(await source.readAsBytes())
          .toString();
      final service = CubasePreservationService();
      final first = await service.preserve(source);
      final second = await service.preserve(source);
      expect(first['status'], 'preserved');
      expect(first['workspace_path'], isNot(second['workspace_path']));
      expect(first['backup_path'], isNot(second['backup_path']));
      for (final path in [
        source.path,
        first['backup_path'],
        first['reconstructed_path'],
      ]) {
        expect(
          sha256.convert(await File(path as String).readAsBytes()).toString(),
          expectedHash,
        );
      }
      final report = jsonDecode(
        await File(
          p.join(first['workspace_path'] as String, 'report.json'),
        ).readAsString(),
      );
      expect(report['byte_identical'], isTrue);
      expect(report['chunk_paths'], hasLength(4));
      expect(report['original_modified'], isFalse);
    },
  );

  test('rejects source symlinks before creating an export', () async {
    if (Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp(
      'cpr-symlink-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = await File(
      p.join(directory.path, 'sample.cpr'),
    ).writeAsBytes(_fixture());
    final link = await Link(
      p.join(directory.path, 'alias.cpr'),
    ).create(source.path);
    expect(
      CubasePreservationService().preserve(File(link.path)),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await Directory(
        p.join(directory.path, '.project-repair-exports'),
      ).exists(),
      isFalse,
    );
  });

  for (final name in ['report.json', 'chunks']) {
    test('keeps a source named $name separate from export evidence', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cpr-preservation-name-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final original = _fixture();
      final source = await File(
        p.join(directory.path, name),
      ).writeAsBytes(original);
      final result = await CubasePreservationService().preserve(source);
      final output = File(result['reconstructed_path'] as String);
      final reportFile = File(
        p.join(result['workspace_path'] as String, 'report.json'),
      );
      final savedReport = jsonDecode(await reportFile.readAsString()) as Map;

      expect(result['status'], 'preserved');
      expect(output.path, isNot(reportFile.path));
      expect(await output.readAsBytes(), orderedEquals(original));
      expect(await source.readAsBytes(), orderedEquals(original));
      expect(
        await File(result['backup_path'] as String).readAsBytes(),
        orderedEquals(original),
      );
      expect(savedReport['reconstructed_path'], output.path);
      expect(savedReport['byte_identical'], isTrue);
      expect(savedReport['chunk_paths'], hasLength(4));
    });
  }
}
