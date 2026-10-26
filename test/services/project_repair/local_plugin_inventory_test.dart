import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/local_plugin_inventory.dart';

void main() {
  test('discovers bundle candidates without inspecting their internals', () async {
    final temp = await Directory.systemTemp.createTemp('plugin-inventory-');
    try {
      await Directory('${temp.path}/Synth.vst3/Contents').create(recursive: true);
      await File('${temp.path}/Synth.vst3/Contents/fake.dll').writeAsString('not a plug-in');
      await File('${temp.path}/Delay.clap').writeAsString('fake');
      final results = LocalPluginInventory.scan(roots: [temp.path]);
      expect(results.map((p) => p.name), containsAll(['Synth', 'Delay']));
      expect(results.length, 2);
      expect(results.every((p) => p.toJson()['loadability'] == 'untested'), isTrue);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
