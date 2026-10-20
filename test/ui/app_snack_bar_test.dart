import 'dart:io';

import 'package:daw_project_manager/ui/app_snack_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('snackBarDisplayDuration', () {
    test('a short message stays the minimum', () {
      expect(
        snackBarDisplayDuration(message: 'Saved', hasAction: false),
        kSnackBarMinDuration,
      );
    });

    test('an action gets time to reach it', () {
      expect(
        snackBarDisplayDuration(message: 'Hidden', hasAction: true),
        kSnackBarActionMinDuration,
      );
    });

    test('a longer message stays up longer', () {
      final short = snackBarDisplayDuration(message: 'x' * 60, hasAction: false);
      final long = snackBarDisplayDuration(message: 'x' * 120, hasAction: false);
      expect(short, greaterThan(kSnackBarMinDuration));
      expect(long, greaterThan(short));
    });

    test('reading time is capped', () {
      expect(
        snackBarDisplayDuration(message: 'x' * 5000, hasAction: true),
        kSnackBarMaxReadingDuration,
      );
    });

    test('an explicitly longer duration is honoured', () {
      expect(
        snackBarDisplayDuration(
          message: 'Uploading',
          hasAction: false,
          requested: const Duration(seconds: 30),
        ),
        const Duration(seconds: 30),
      );
    });

    test('content that is not text gets the floor', () {
      expect(
        snackBarDisplayDuration(hasAction: false),
        kSnackBarMinDuration,
      );
    });
  });

  group('normalizeSnackBar', () {
    test('a snackbar with an action no longer persists', () {
      final raw = SnackBar(
        content: const Text('1 project hidden.'),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      );
      // Flutter's own default — the reason the bar never went away.
      expect(raw.persist, isTrue);

      final shown = normalizeSnackBar(raw);
      expect(shown.persist, isFalse);
      expect(shown.duration, kSnackBarActionMinDuration);
      expect(shown.action, same(raw.action));
    });

    test('adds a close button unless the caller chose otherwise', () {
      expect(
        normalizeSnackBar(const SnackBar(content: Text('a'))).showCloseIcon,
        isTrue,
      );
      expect(
        normalizeSnackBar(
          const SnackBar(content: Text('a'), showCloseIcon: false),
        ).showCloseIcon,
        isFalse,
      );
    });

    test('keeps what the caller set', () {
      const key = Key('bar');
      final shown = normalizeSnackBar(
        const SnackBar(
          key: key,
          content: Text('a'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
          dismissDirection: DismissDirection.horizontal,
        ),
      );
      expect(shown.key, key);
      expect(shown.backgroundColor, Colors.red);
      expect(shown.behavior, SnackBarBehavior.fixed);
      expect(shown.dismissDirection, DismissDirection.horizontal);
    });
  });

  group('showAppSnackBar', () {
    late ScaffoldMessengerState messenger;

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                messenger = ScaffoldMessenger.of(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
    }

    // Regression: "1 project hidden." with its Undo action stayed on screen
    // over the bottom of the window until the app was restarted.
    testWidgets('a snackbar with an action times out', (tester) async {
      await pumpHost(tester);

      messenger.showAppSnackBar(
        SnackBar(
          content: const Text('1 project hidden.'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 project hidden.'), findsOneWidget);

      await tester.pump(kSnackBarActionMinDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the close button dismisses it', (tester) async {
      await pumpHost(tester);

      messenger.showAppSnackBar(const SnackBar(content: Text('Saved')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the newest message replaces the one on screen',
        (tester) async {
      await pumpHost(tester);

      messenger.showAppSnackBar(
        SnackBar(
          content: const Text('first'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      messenger.showAppSnackBar(const SnackBar(content: Text('second')));
      await tester.pumpAndSettle();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
    });
  });

  // Every snackbar has to go through showAppSnackBar: a direct showSnackBar
  // with an action is one that never times out again.
  test('nothing in lib/ calls showSnackBar directly', () {
    final helper = p.normalize(p.join('lib', 'ui', 'app_snack_bar.dart'));
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (p.normalize(entity.path) == helper) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'\bshowSnackBar\(').hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use showAppSnackBar from lib/ui/app_snack_bar.dart');
  });
}
