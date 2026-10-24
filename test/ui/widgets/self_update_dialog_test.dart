import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/self_updater.dart';
import 'package:daw_project_manager/services/update_download.dart';
import 'package:daw_project_manager/ui/widgets/self_update_dialog.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

/// Stands in for the AppImage's and the Windows installer's updaters.
class _FakeUpdater implements SelfUpdater {
  final Completer<void> done = Completer<void>();
  void Function(double? progress)? progress;
  String? preparedVersion;
  var closed = false;

  @override
  String get reportName => 'Fake';

  @override
  Future<void> prepare(
    String version, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) {
    preparedVersion = version;
    progress = onProgress;
    cancelToken?.whenCancelled.then((_) {
      if (!done.isCompleted) done.completeError(const UpdateCancelledException());
    });
    return done.future;
  }

  @override
  Future<void> restart() async {}

  @override
  void close() => closed = true;
}

void main() {
  Future<void> pump(WidgetTester tester, _FakeUpdater updater) => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SelfUpdateDialog(version: '9.9.9', createUpdater: () => updater),
          ),
        ),
      );

  testWidgets('shows the download, then offers to restart into the update', (tester) async {
    final updater = _FakeUpdater();
    await pump(tester, updater);

    expect(updater.preparedVersion, '9.9.9');
    expect(find.text('Looking for the update…'), findsOneWidget);

    updater.progress!(0.5);
    await tester.pump();
    expect(find.text('Downloading update… 50%'), findsOneWidget);

    updater.done.complete();
    await tester.pump();
    expect(find.text('Update Ready'), findsOneWidget);
    expect(find.text('Restart Now'), findsOneWidget);
    // Kept open: it is the one that restarts into the update.
    expect(updater.closed, isFalse);
  });

  testWidgets('a failure is shown with its details and can be retried', (tester) async {
    final updater = _FakeUpdater();
    await pump(tester, updater);

    updater.done.completeError(StateError('No update package found for v9.9.9.'));
    await tester.pump();

    expect(find.text('Update Failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(updater.closed, isTrue);
  });
}
