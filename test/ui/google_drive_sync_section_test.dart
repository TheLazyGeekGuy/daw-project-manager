import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/models/auto_backup_interval.dart';
import 'package:daw_project_manager/providers/providers.dart';
import 'package:daw_project_manager/services/google_drive_sync_service.dart';
import 'package:daw_project_manager/ui/google_drive_sync_page.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

/// A service that is signed out and never touches Drive, Hive or the
/// platform, so the sync section can be mounted in a widget test.
class _SignedOutService extends GoogleDriveSyncService {
  @override
  bool get isSignedIn => false;

  @override
  Future<bool> restoreSession() async => false;

  @override
  Future<DateTime?> getLastSyncedAt() async => null;

  @override
  Future<SyncFailure?> getLastFailure() async => null;

  @override
  Future<DateTime?> getLastBackupUploadTimestamp() async => null;

  @override
  Future<String?> getCurrentUserEmail() async => null;
}

class _FixedInterval extends AutoBackupIntervalNotifier {
  @override
  AutoBackupInterval build() => AutoBackupInterval.off;
}

class _FixedUploadAuto extends UploadAutoPreviewSongsNotifier {
  @override
  bool build() => false;
}

class _FixedSyncOnStartup extends SyncOnStartupNotifier {
  @override
  bool build() => true;
}

void main() {
  testWidgets('leaving the sync page does not use ref after it is gone',
      (tester) async {
    // The bug: dispose() read the service through `ref`, which Riverpod
    // refuses once the widget is unmounting — "Using ref when a widget is
    // about to or has been unmounted is unsafe" every time the page closed.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        googleDriveSyncServiceProvider.overrideWithValue(_SignedOutService()),
        autoBackupIntervalProvider.overrideWith(_FixedInterval.new),
        uploadAutoPreviewSongsProvider.overrideWith(_FixedUploadAuto.new),
        syncOnStartupProvider.overrideWith(_FixedSyncOnStartup.new),
      ],
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: GoogleDriveSyncSection()),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Sign in to Google Drive'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
