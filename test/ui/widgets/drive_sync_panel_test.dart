import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/models/auto_backup_interval.dart';
import 'package:daw_project_manager/models/drive_sync_status.dart';
import 'package:daw_project_manager/ui/google_drive_sync_page.dart'
    show DriveSyncStatusGlyph, driveSyncStatusTooltip;
import 'package:daw_project_manager/ui/widgets/drive_sync_panel.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> pump(
    WidgetTester tester,
    DriveSyncPanelData data, {
    Locale locale = const Locale('en'),
    // A spinner never settles.
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriveSyncPanel(
            data: data,
            snapshotsKept: 10,
            onSignIn: () => calls.add('signIn'),
            onCancelSignIn: () => calls.add('cancelSignIn'),
            onSignOut: () => calls.add('signOut'),
            onSyncNow: () => calls.add('syncNow'),
            onRestoreFromDrive: () => calls.add('restore'),
            onRecoverEarlier: () => calls.add('recover'),
            onOverwriteDrive: () => calls.add('overwrite'),
            onDeleteDriveData: () => calls.add('delete'),
            onIntervalChanged: (i) => calls.add('interval:${i.name}'),
            onUploadAutoDetectedChanged: (v) => calls.add('auto:$v'),
          ),
        ),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('signed out', () {
    testWidgets('offers sign-in, and no Drive actions', (tester) async {
      await pump(tester, DriveSyncPanelData(now: now));
      await tester.tap(find.text('Sign in to Google Drive'));
      expect(calls, ['signIn']);
      expect(find.text('Sync now'), findsNothing);
      expect(find.text('Restore and other options'), findsNothing);
    });

    testWidgets('while the browser is open, says so and can be cancelled',
        (tester) async {
      // The bug: the page just spun, every button disabled, until left.
      await pump(
        tester,
        DriveSyncPanelData(now: now, waitingForBrowser: true),
        settle: false,
      );
      expect(find.text('Finish signing in in your browser…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      expect(calls, ['cancelSignIn']);
    });
  });

  group('signed in', () {
    DriveSyncPanelData signedIn({
      bool newerOnDrive = false,
      String? remoteDevice = 'Phone',
      bool remoteIsThisDevice = false,
      String? errorText,
      String? errorTitle,
      bool busy = false,
      bool isMobile = false,
    }) =>
        DriveSyncPanelData(
          now: now,
          signedIn: true,
          email: 'me@example.com',
          lastSyncedAt: now.subtract(const Duration(hours: 2)),
          remoteUpdatedAt: now.subtract(const Duration(minutes: 10)),
          remoteDevice: remoteDevice,
          remoteIsThisDevice: remoteIsThisDevice,
          newerOnDrive: newerOnDrive,
          errorText: errorText,
          errorTitle: errorTitle,
          busy: busy,
          isMobile: isMobile,
          interval: AutoBackupInterval.hourly,
          lastAutoSyncAt: now.subtract(const Duration(minutes: 20)),
        );

    testWidgets('Sync now is the one main action', (tester) async {
      await pump(tester, signedIn());
      await tester.tap(find.text('Sync now'));
      expect(calls, ['syncNow']);
      // The four equal buttons are gone.
      expect(find.text('Check for Backup'), findsNothing);
      expect(find.text('Upload Backup'), findsNothing);
    });

    testWidgets('says when each side last changed, and from where',
        (tester) async {
      await pump(tester, signedIn());
      expect(find.text('This device synced 2 hours ago'), findsOneWidget);
      expect(find.text('Drive updated 10 minutes ago from Phone'), findsOneWidget);
      expect(find.text('Next sync in 40 min'), findsOneWidget);
    });

    testWidgets('names this device as "this device"', (tester) async {
      await pump(tester, signedIn(remoteIsThisDevice: true));
      expect(
        find.text('Drive updated 10 minutes ago from this device'),
        findsOneWidget,
      );
    });

    testWidgets('shows "newer on Drive" on desktop too', (tester) async {
      // It used to be mobile-only, so a desktop never learned another
      // device had pushed.
      await pump(tester, signedIn(newerOnDrive: true, isMobile: false));
      expect(find.byKey(const ValueKey('drive-sync-newer')), findsOneWidget);
      expect(find.textContaining('Phone has changes on Drive'), findsOneWidget);
    });

    testWidgets('shows an error in any language', (tester) async {
      // The bug: the card decided what was an error with
      // `contains('Error') || contains('Failed')`, so in the other eight
      // languages a failed sync never showed in it.
      await pump(
        tester,
        signedIn(
          errorTitle: 'Letzte Synchronisierung fehlgeschlagen (vor 1 Stunde)',
          errorText: 'Google Drive ist nicht erreichbar.',
        ),
        locale: const Locale('de'),
      );
      expect(find.byKey(const ValueKey('drive-sync-error')), findsOneWidget);
      expect(find.text('Google Drive ist nicht erreichbar.'), findsOneWidget);
      expect(find.text('Jetzt synchronisieren'), findsOneWidget);
    });

    testWidgets('an error takes the place of the "newer" banner', (tester) async {
      await pump(tester, signedIn(newerOnDrive: true, errorText: 'Broken'));
      expect(find.byKey(const ValueKey('drive-sync-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('drive-sync-newer')), findsNothing);
    });

    testWidgets('nothing can be started while something runs', (tester) async {
      await pump(tester, signedIn(busy: true), settle: false);
      await tester.tap(find.text('Sync now'));
      await tester.tap(find.text('Sign Out'));
      expect(calls, isEmpty);
    });

    testWidgets('the other Drive actions sit under one expandable card',
        (tester) async {
      await pump(tester, signedIn());
      expect(find.text('Delete my data from Google Drive'), findsNothing);
      await tester.tap(find.text('Restore and other options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Get Drive's changes only"));
      await tester.tap(find.text('Recover from an earlier backup'));
      await tester.tap(find.text("Replace Drive's copy with this device"));
      await tester.tap(find.text('Delete my data from Google Drive'));
      expect(calls, ['restore', 'recover', 'overwrite', 'delete']);
    });

    testWidgets('lays out on a phone', (tester) async {
      await pump(tester, signedIn(isMobile: true));
      expect(find.text('Sync now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DriveSyncStatusGlyph', () {
    Future<void> pumpGlyph(WidgetTester tester, DriveSyncIndicator i) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: DriveSyncStatusGlyph(indicator: i)),
        ));

    testWidgets('marks a failure with a dot and a crossed-out cloud',
        (tester) async {
      await pumpGlyph(tester, DriveSyncIndicator.failed);
      expect(find.byKey(const ValueKey('drive-status-dot-failed')), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('marks news on Drive with a dot', (tester) async {
      await pumpGlyph(tester, DriveSyncIndicator.newerOnDrive);
      expect(
        find.byKey(const ValueKey('drive-status-dot-newerOnDrive')),
        findsOneWidget,
      );
    });

    testWidgets('spins while syncing', (tester) async {
      await pumpGlyph(tester, DriveSyncIndicator.syncing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('draws a plain cloud with nothing to say', (tester) async {
      await pumpGlyph(tester, DriveSyncIndicator.none);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.byType(Container), findsNothing);
    });

    test('every state has its own tooltip', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final tips = {
        for (final i in DriveSyncIndicator.values) driveSyncStatusTooltip(l10n, i),
      };
      expect(tips.length, DriveSyncIndicator.values.length);
    });
  });
}
