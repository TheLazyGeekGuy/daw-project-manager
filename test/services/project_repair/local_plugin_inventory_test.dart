import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/local_plugin_inventory.dart';

const processorId = '0123456789ABCDEF0123456789ABCDEF';
const oldProcessorId = '11111111111111111111111111111111';

Future<File> manifest(
  Directory root,
  Object contents, {
  bool legacyPath = false,
}) async {
  final file = File(
    '${root.path}/Package.vst3/Contents/${legacyPath ? '' : 'Resources/'}moduleinfo.json',
  );
  await file.parent.create(recursive: true);
  return file.writeAsString(
    contents is String ? contents : jsonEncode(contents),
  );
}

Map<String, Object> processor({
  String id = processorId,
  String name = 'Synth',
}) => {
  'CID': id,
  'Name': name,
  'Category': 'Audio Module Class',
  'Version': '1.2.3',
};

void main() {
  late Directory temp;
  setUp(() async {
    final created = await Directory.systemTemp.createTemp('plugin-inventory-');
    temp = Directory(await created.resolveSymbolicLinks());
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('discovers candidates without interpreting bundle binaries', () async {
    await Directory('${temp.path}/Synth.vst3/Contents').create(recursive: true);
    await File(
      '${temp.path}/Synth.vst3/Contents/fake.dll',
    ).writeAsString('not a plug-in');
    await File('${temp.path}/Delay.clap').writeAsString('fake');
    final results = LocalPluginInventory.scan(roots: [temp.path]);
    expect(results.map((p) => p.name), containsAll(['Synth', 'Delay']));
    expect(results.length, 2);
    expect(
      results.every((p) => p.toJson()['loadability'] == 'untested'),
      isTrue,
    );
  });

  test(
    'reads all processor class IDs, not controller classes or bundle name',
    () async {
      await manifest(temp, {
        'Factory Info': {'Vendor': 'Studio'},
        'Classes': [
          processor(),
          processor(id: oldProcessorId, name: 'Delay'),
          {
            'CID': '22222222222222222222222222222222',
            'Name': 'Controller',
            'Category': 'Component Controller Class',
          },
        ],
        'Compatibility': [
          {
            'New': processorId,
            'Old': [oldProcessorId],
          },
        ],
      });
      final report = LocalPluginInventory.scanReport(roots: [temp.path]);
      expect(report.candidates, hasLength(2));
      final synth = report.candidates.firstWhere((p) => p.name == 'Synth');
      expect(synth.identifier, processorId);
      expect(synth.vendor, 'Studio');
      expect(synth.version, '1.2.3');
      expect(synth.compatibleIdentifiers, [oldProcessorId]);
      expect(synth.toJson()['identity_evidence'], 'module_manifest');
      expect(synth.toJson()['license_status'], 'unknown');
      expect(report.warnings, isEmpty);
    },
  );

  test(
    'SDK comments/trailing commas preserve URLs and quoted punctuation',
    () async {
      await manifest(temp, '''{
      // SDK moduleinfotool output
      "Factory Info": {"Vendor": "https://vendor.test/",},
      "Classes": [/* processors */{
        "CID": "$processorId",
        "Category": "Audio Module Class",
        "Name": "Synth,}",
      },],
    }''', legacyPath: true);
      final report = LocalPluginInventory.scanReport(roots: [temp.path]);
      expect(report.candidates.single.identifier, processorId);
      expect(report.candidates.single.name, 'Synth,}');
      expect(report.candidates.single.vendor, 'https://vendor.test/');
    },
  );

  test(
    'malformed and unsupported JSON5 remains unverified with warning',
    () async {
      await manifest(
        temp,
        "{Classes: [{'Name':'Invented', 'CID':'$processorId'}]}",
      );
      final report = LocalPluginInventory.scanReport(roots: [temp.path]);
      expect(report.candidates.single.identifier, isNull);
      expect(report.candidates.single.name, 'Package');
      expect(report.warnings, isNotEmpty);
    },
  );

  test('oversized manifests never produce identifiers', () async {
    await manifest(temp, {
      'Classes': [processor()],
    });
    final report = LocalPluginInventory.scanReport(
      roots: [temp.path],
      maxManifestBytes: 10,
    );
    expect(report.candidates.single.identifier, isNull);
    expect(report.warnings.single, contains('size limit'));
  });

  test('invalid IDs and duplicate classes are diagnosed', () async {
    await manifest(temp, {
      'Classes': [processor(), processor(), processor(id: 'not-an-id')],
    });
    final report = LocalPluginInventory.scanReport(roots: [temp.path]);
    expect(report.candidates, hasLength(1));
    expect(report.warnings, hasLength(2));
  });

  test('repeated roots do not duplicate identities', () async {
    await manifest(temp, {
      'Classes': [processor()],
    });
    expect(
      LocalPluginInventory.scan(roots: [temp.path, temp.path]),
      hasLength(1),
    );
  });

  test(
    'entry/depth limits are observable and never claim completeness',
    () async {
      await File('${temp.path}/One.clap').writeAsString('fake');
      await File('${temp.path}/Two.clap').writeAsString('fake');
      final bounded = LocalPluginInventory.scanReport(
        roots: [temp.path],
        maxEntries: 1,
      );
      expect(bounded.candidates, hasLength(1));
      expect(bounded.truncated, true);
      expect(bounded.toJson()['absence_is_conclusive'], false);
      await Directory('${temp.path}/nested').create();
      final shallow = LocalPluginInventory.scanReport(
        roots: [temp.path],
        maxDepth: 0,
      );
      expect(shallow.truncated, true);
    },
  );

  test('missing roots remain visible', () {
    final report = LocalPluginInventory.scanReport(
      roots: ['${temp.path}/missing'],
    );
    expect(report.scannedRoots, isEmpty);
    expect(report.warnings.single, contains('not available'));
  });

  test(
    'linked manifest and linked root ancestors are skipped',
    () async {
      final outside = await Directory('${temp.path}/external').create();
      final scanRoot = await Directory('${temp.path}/plugins').create();
      final file = await File('${outside.path}/moduleinfo.json').writeAsString(
        jsonEncode({
          'Classes': [processor()],
        }),
      );
      final resources = await Directory(
        '${scanRoot.path}/Linked.vst3/Contents/Resources',
      ).create(recursive: true);
      await Link('${resources.path}/moduleinfo.json').create(file.path);
      final report = LocalPluginInventory.scanReport(roots: [scanRoot.path]);
      expect(report.candidates.single.identifier, isNull);
      expect(report.warnings.single, contains('linked'));
      await Link('${temp.path}/alias').create(scanRoot.path);
      final linkedRoot = LocalPluginInventory.scanReport(
        roots: ['${temp.path}/alias/Linked.vst3'],
      );
      expect(linkedRoot.candidates, isEmpty);
      expect(linkedRoot.warnings.single, contains('linked inventory root'));
    },
    skip: Platform.isWindows
        ? 'Creating links requires Windows developer mode'
        : false,
  );
}
