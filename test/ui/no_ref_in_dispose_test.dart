import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Riverpod 3 refuses `ref` once a widget is being unmounted, so a
/// `dispose()` that reads a provider throws every time — and whatever it
/// meant to do after that line never runs. Two did: the music player never
/// handed back the bottom bar's previous/next, and a release's audio rows
/// leaked their players and stayed registered with the app's audio focus.
/// Keep the notifier in a field when the widget is set up instead.
void main() {
  test('no dispose() in lib/ uses ref', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp(r'void dispose\(\)\s*\{').allMatches(source)) {
        var depth = 1, end = match.end;
        while (depth > 0 && end < source.length) {
          final c = source[end++];
          if (c == '{') depth++;
          if (c == '}') depth--;
        }
        final body = source.substring(match.end, end);
        if (RegExp(r'\bref\.(read|watch|listen|invalidate|refresh)\(').hasMatch(body)) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('${p.normalize(file.path)}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
