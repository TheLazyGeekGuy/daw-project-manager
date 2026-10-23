import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/models/plugin_capture.dart';
import 'package:daw_project_manager/ui/widgets/latest_capture_section.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The project page's "Latest capture", drawn from plain values: no player,
/// Riverpod or Hive (LatestCaptureSection is the glue around it).
void main() {
  final capture = PluginCapture(
    path: '/data/preview_songs/plugin/p1/take.flac',
    capturedAt: DateTime(2026, 10, 21, 18, 4),
    durationSeconds: 92,
  );

  Future<void> pump(
    WidgetTester tester, {
    bool available = true,
    bool playing = false,
    bool isPreviewSong = false,
    VoidCallback? onPlayPause,
    VoidCallback? onUseAsPreview,
  }) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: LatestCaptureView(
          capture: capture,
          available: available,
          playing: playing,
          position: Duration.zero,
          duration: Duration.zero,
          isPreviewSong: isPreviewSong,
          onPlayPause: onPlayPause ?? () {},
          onSeek: (_) {},
          onUseAsPreview: onUseAsPreview ?? () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says what it is, when it was captured and how long it is', (tester) async {
    await pump(tester);

    expect(find.text('Latest capture'), findsOneWidget);
    expect(find.text('The last pass the DAW plugin recorded'), findsOneWidget);
    // Until the player reports one, the length the plugin recorded.
    expect(find.textContaining('1:32'), findsWidgets);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('plays, and offers to become the preview song', (tester) async {
    var played = 0;
    var promoted = 0;
    await pump(tester, onPlayPause: () => played++, onUseAsPreview: () => promoted++);

    await tester.tap(find.byIcon(Icons.play_circle));
    await tester.tap(find.text('Use as preview song'));

    expect(played, 1);
    expect(promoted, 1);
  });

  testWidgets('shows pause while it plays', (tester) async {
    await pump(tester, playing: true);
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);
  });

  testWidgets('once it is the preview song, it is not offered again', (tester) async {
    await pump(tester, isPreviewSong: true);
    expect(find.text('Use as preview song'), findsNothing);
  });

  testWidgets('a capture whose file is not here yet says so and cannot play', (tester) async {
    var played = 0;
    await pump(tester, available: false, onPlayPause: () => played++);

    expect(find.text('Not on this device yet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle));
    expect(played, 0);
  });
}
