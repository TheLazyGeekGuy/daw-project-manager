import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/cubase_structural_probe.dart';

void main() {
  void addU16(BytesBuilder bytes, int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.big);
    bytes.add(data.buffer.asUint8List());
  }

  void addU32(BytesBuilder bytes, int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    bytes.add(data.buffer.asUint8List());
  }

  void addTagged(BytesBuilder bytes, String tag, String value) {
    addU32(bytes, tag.length + 1);
    bytes.add(ascii.encode(tag));
    bytes.addByte(0);
    addU16(bytes, 8);
    final valueBytes = utf8.encode(value);
    addU32(bytes, valueBytes.length + 4);
    bytes.add(valueBytes);
    bytes.add([0, 0xef, 0xbb, 0xbf]);
  }

  Uint8List pluginUidRecord(String uid, String name) {
    final bytes = BytesBuilder();
    addU32(bytes, 'Plugin UID'.length + 1);
    bytes.add(ascii.encode('Plugin UID'));
    bytes.addByte(0);
    addU16(bytes, 2);
    addU16(bytes, 6);
    addU32(bytes, 1);
    addTagged(bytes, 'GUID', uid);
    addTagged(bytes, 'Plugin Name', name);
    return bytes.toBytes();
  }

  test('preflight verifies RIFF big-endian chunk lengths', () {
    final bytes = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add([0, 0, 0, 8])
      ..add(ascii.encode('NUNDARCH'))
      ..add([0, 0, 0, 0]);
    final manifest = CubaseContainerManifest.inspect(bytes.toBytes());
    expect(manifest.archiveCount, 1);
    expect(manifest.chunks.single.offset, 12);
    expect(manifest.toJson()['safe_to_rewrite'], isFalse);
  });

  test('rejects truncated RIFF chunks even when signature matches', () {
    final bytes = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add([0, 0, 0, 8])
      ..add(ascii.encode('NUNDARCH'))
      ..add([0, 0, 0, 1]);
    expect(
      () => CubaseContainerManifest.inspect(bytes.toBytes()),
      throwsFormatException,
    );
  });

  test('aggregates exact typed UID declarations, not vendor verification', () {
    const uid = '745C69937EB44378A9CC237A3D758B16';
    final record = pluginUidRecord(uid, 'Mystic');
    final combined = BytesBuilder()..add(record)..add(record);
    final evidence = CubasePluginUidProbe.inspect(combined.toBytes());
    expect(evidence, hasLength(1));
    expect(evidence.single.name, 'Mystic');
    expect(evidence.single.uid, uid);
    expect(evidence.single.occurrences, 2);
    expect(evidence.single.toJson()['vendor_identity_verified'], isFalse);
  });

  test('does not mistake arbitrary GUIDs for tagged plug-in records', () {
    final fake = Uint8List.fromList(ascii.encode(
      'Plugin UID GUID 745C69937EB44378A9CC237A3D758B16 Mystic',
    ));
    expect(CubasePluginUidProbe.inspect(fake), isEmpty);
  });
}
