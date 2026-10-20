import 'dart:io';

import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/services/plugin_bridge/plugin_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_helper.dart';

/// Settings > DAW plugin's "last seen" line: device-local, kept across
/// restarts, never rolled back by an old heartbeat.
void main() {
  late Directory tempDir;
  late ProviderContainer container;
  final at = DateTime(2026, 10, 19, 12, 51);

  setUp(() async {
    tempDir = await HiveTestHelper.setUp();
    container = ProviderContainer();
    container.listen(dpmPluginSightingProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await HiveTestHelper.tearDown(tempDir);
  });

  DpmPluginSightingNotifier notifier() => container.read(dpmPluginSightingProvider.notifier);

  test('a sighting is kept and survives a restart', () async {
    await notifier().record(DpmPluginSighting('0.1.0', 'Steinberg Cubase 13', at));
    expect(container.read(dpmPluginSightingProvider)?.hostName, 'Steinberg Cubase 13');

    final box = await Hive.openBox<String>('settings');
    expect(box.get(DpmPluginSightingNotifier.storageKey), contains('Steinberg Cubase 13'));

    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    restarted.listen(dpmPluginSightingProvider, (_, _) {});
    for (var i = 0; i < 50 && restarted.read(dpmPluginSightingProvider) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(restarted.read(dpmPluginSightingProvider)?.version, '0.1.0');
  });

  test('an older sighting never replaces a newer one', () async {
    await notifier().record(DpmPluginSighting('0.2.0', 'Cubase', at));
    await notifier().record(DpmPluginSighting('0.1.0', 'Cubase', at.subtract(const Duration(days: 3))));
    expect(container.read(dpmPluginSightingProvider)?.version, '0.2.0');
  });

  test('heartbeats seconds apart aren\'t written each time', () async {
    await notifier().record(DpmPluginSighting('0.1.0', 'Cubase', at));
    await notifier().record(DpmPluginSighting('0.1.0', 'Cubase', at.add(const Duration(seconds: 10))));
    expect(container.read(dpmPluginSightingProvider)?.at, at);
    await notifier().record(DpmPluginSighting('0.1.0', 'Cubase', at.add(const Duration(minutes: 2))));
    expect(container.read(dpmPluginSightingProvider)?.at, at.add(const Duration(minutes: 2)));
  });
}
