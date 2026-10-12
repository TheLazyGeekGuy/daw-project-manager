import 'package:daw_project_manager/models/custom_theme.dart';
import 'package:daw_project_manager/providers/theme_provider.dart';
import 'package:daw_project_manager/ui/app_snack_bar.dart';
import 'package:daw_project_manager/utils/color_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: the snackbar's close (✕) button used Flutter's default
/// `onInverseSurface`, which assumes an inverted snackbar. Ours sits on the
/// card color, so on Classic Dark the ✕ was 1.05:1 against it — invisible —
/// and the Undo label (`inversePrimary`) about 2:1.
void main() {
  final themes = <CustomTheme>[
    ...AppThemes.allBuiltIns,
    // User themes: a muted accent, a vivid one, and a light card.
    AppThemes.classicDarkSpec.copyWith(
      id: 'user-muted',
      primary: const Color(0xFF3A3F47),
    ),
    AppThemes.classicDarkSpec.copyWith(
      id: 'user-vivid',
      primary: const Color(0xFFFF4FD8),
    ),
    AppThemes.classicDarkSpec.copyWith(
      id: 'user-light-card',
      card: const Color(0xFFE8E8E8),
    ),
  ];

  for (final spec in themes) {
    group(spec.id, () {
      final theme = AppThemes.buildFrom(spec);
      final background = theme.snackBarTheme.backgroundColor!;

      test('the close button is legible', () {
        expect(
          contrastRatio(theme.snackBarTheme.closeIconColor!, background),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('the action label is legible', () {
        expect(
          contrastRatio(theme.snackBarTheme.actionTextColor!, background),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }

  test('a vivid accent that reads on the snackbar colors its action', () {
    final spec = AppThemes.neonDarkSpec;
    expect(AppThemes.buildFrom(spec).snackBarTheme.actionTextColor,
        spec.primary);
  });

  testWidgets('the rendered close button takes the theme color',
      (tester) async {
    final spec = AppThemes.classicDarkSpec;
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.buildFrom(spec),
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

    messenger.showAppSnackBar(const SnackBar(content: Text('Saved')));
    await tester.pumpAndSettle();

    final close = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      ),
    );
    expect(close.color, spec.resolvedSnackBarForeground);
  });
}
