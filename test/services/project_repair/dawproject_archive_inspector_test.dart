import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/dawproject_archive_inspector.dart';

import '../../helpers/dawproject_fixture.dart';

void main() {
  test('reads actual ZIP/XML entries and opaque plug-in state hashes', () {
    final bytes = dawProjectFixture(
      project: '''
<Project version="1.0"><Application name="Fixture" version="1"/>
<Structure><Track id="track1" name="Keys"><Channel role="regular">
<Devices><Vst3Plugin id="synth1" deviceName="Synth" deviceID="ABC123" deviceVendor="Vendor">
<State path="plugins/synth.vstpreset"/></Vst3Plugin></Devices>
</Channel></Track><Track id="master" name="Master"><Channel role="master"/></Track></Structure>
<Arrangement><Lanes><Clips><Clip><Notes><Note key="60"/></Notes></Clip></Clips></Lanes></Arrangement>
</Project>''',
      files: {
        'plugins/synth.vstpreset': [1, 2, 3],
      },
    );
    final result = DawProjectArchiveInspector.inspect(bytes);
    expect(result.applicationName, 'Fixture');
    expect(result.tracks.map((t) => t.name), ['Keys', 'Master']);
    expect(result.tracks.last.isMaster, true);
    expect(result.plugins.single.pluginId, 'ABC123');
    expect(
      result.plugins.single.stateSha256,
      sha256.convert([1, 2, 3]).toString(),
    );
    expect(result.noteCount, 1);
    expect(result.selfContained, true);
    expect(result.toJson()['full_xsd_validation'], false);
  });

  test('ZIP magic alone is insufficient', () {
    final zip = Archive()..addFile(ArchiveFile('unrelated.txt', 1, [42]));
    expect(
      () => DawProjectArchiveInspector.inspect(
        Uint8List.fromList(ZipEncoder().encode(zip)),
      ),
      throwsFormatException,
    );
    expect(
      () => DawProjectArchiveInspector.inspect(
        Uint8List.fromList([80, 75, 3, 4]),
      ),
      throwsFormatException,
    );
  });

  test('reports missing and external assets without reading host files', () {
    final result = DawProjectArchiveInspector.inspect(
      dawProjectFixture(
        project: '''
<Project version="1.0"><Application name="Fixture"/>
<Structure><Track id="repeated"/><Track id="repeated"/></Structure>
<Arrangement><Audio><File path="audio/missing.wav"/></Audio>
<Audio><File path="/private/secret.wav" external="true"/></Audio></Arrangement></Project>''',
      ),
    );
    expect(result.missingReferences, ['audio/missing.wav']);
    expect(result.externalReferences, ['/private/secret.wav']);
    expect(result.duplicateIds, ['repeated']);
    expect(result.selfContained, false);
  });

  test('rejects traversal archive names and internal file references', () {
    for (final path in ['../secret', '/absolute', 'C:/secret', 'a\\b']) {
      expect(
        () => DawProjectArchiveInspector.inspect(
          dawProjectFixture(
            files: {
              path: [1],
            },
          ),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => DawProjectArchiveInspector.inspect(
        dawProjectFixture(
          project:
              '<Project version="1.0"><Application name="Fixture"/><Audio><File path="../secret"/></Audio></Project>',
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects unsupported versions, XML entity declarations and malformed XML',
    () {
      for (final project in [
        '<Project version="2.0"><Application name="Fixture"/></Project>',
        '<!DOCTYPE Project [<!ENTITY secret SYSTEM "file:///etc/passwd">]><Project version="1.0"/>',
        '<Project version="1.0">',
      ]) {
        expect(
          () => DawProjectArchiveInspector.inspect(
            dawProjectFixture(project: project),
          ),
          throwsA(anything),
        );
      }
    },
  );

  test('rejects directory sizes that understate decompressed XML', () {
    final bytes = dawProjectFixture(
      project:
          '<Project version="1.0"><Application name="Fixture"/><!--${'a' * 100000}--></Project>',
    );
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (view.getUint32(i, Endian.little) == 0x02014b50 &&
          utf8.decode(
                bytes.sublist(
                  i + 46,
                  i + 46 + view.getUint16(i + 28, Endian.little),
                ),
              ) ==
              'project.xml') {
        view.setUint32(i + 24, 1, Endian.little);
        break;
      }
    }
    expect(
      () => DawProjectArchiveInspector.inspect(bytes),
      throwsFormatException,
    );
  });
}
