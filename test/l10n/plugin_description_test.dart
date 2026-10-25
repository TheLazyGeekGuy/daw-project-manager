import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Settings > DAW plugin once said the plugin records each playback pass "as
/// the project's preview song" — in every language — after captures got a
/// slot of their own and stopped replacing the preview. The description has
/// to call a capture what the project page does: its latest capture.
void main() {
  final arbs = Directory('lib/l10n').listSync().whereType<File>().where((f) => f.path.endsWith('.arb'));

  test('there are locales to check', () => expect(arbs, isNotEmpty));

  for (final arb in arbs) {
    test('${arb.uri.pathSegments.last}: a capture is the latest capture, not the preview song', () {
      final strings = jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;
      final description = (strings['dpmPluginDescription'] as String).toLowerCase();
      final captureTitle = (strings['latestCaptureTitle'] as String).toLowerCase();

      expect(description, contains(captureTitle));
    });
  }
}
