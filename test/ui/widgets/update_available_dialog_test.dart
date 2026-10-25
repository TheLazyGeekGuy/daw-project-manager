import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/ui/widgets/update_available_dialog.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';

void main() {
  group('updateRouteFor', () {
    test('the MSIX package updates from the Microsoft Store', () {
      expect(
        updateRouteFor(isWindows: true, isMsix: true, isVelopack: false, isAppImage: false),
        UpdateRoute.microsoftStore,
      );
    });

    test("the .exe installer's copy updates itself", () {
      expect(
        updateRouteFor(isWindows: true, isMsix: false, isVelopack: true, isAppImage: false),
        UpdateRoute.windowsSelfUpdate,
      );
    });

    test("the old installer's copy is offered the new installer", () {
      expect(
        updateRouteFor(isWindows: true, isMsix: false, isVelopack: false, isAppImage: false),
        UpdateRoute.windowsInstaller,
      );
    });

    test('the AppImage updates itself', () {
      expect(
        updateRouteFor(isWindows: false, isMsix: false, isVelopack: false, isAppImage: true),
        UpdateRoute.appImage,
      );
    });

    test('everything else downloads from GitHub', () {
      expect(
        updateRouteFor(isWindows: false, isMsix: false, isVelopack: false, isAppImage: false),
        UpdateRoute.gitHub,
      );
    });
  });

  Future<void> pump(WidgetTester tester, UpdateRoute route) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UpdateAvailableDialog(version: '9.9.9', route: route),
        ),
      ),
    );
  }

  testWidgets(
      "an installer copy is offered the installer, not the Store — the Store "
      'would install a second copy', (tester) async {
    await pump(tester, UpdateRoute.windowsInstaller);

    expect(find.text('Windows installer'), findsOneWidget);
    expect(find.text('Download installer'), findsOneWidget);
    expect(find.text('Get on Microsoft Store'), findsNothing);
    expect(find.textContaining('Microsoft Store'), findsNothing);
  });

  testWidgets("the installer's copy offers to update in place, not a download",
      (tester) async {
    await pump(tester, UpdateRoute.windowsSelfUpdate);

    expect(find.text('Windows installer'), findsOneWidget);
    expect(find.text('Update in place and restart.'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    expect(find.text('Download installer'), findsNothing);
    expect(find.text('Get on Microsoft Store'), findsNothing);
  });

  testWidgets('a Store copy is sent to the Store', (tester) async {
    await pump(tester, UpdateRoute.microsoftStore);

    expect(find.text('Get on Microsoft Store'), findsOneWidget);
    expect(find.text('Download installer'), findsNothing);
  });

  testWidgets('macOS and the tarball download from GitHub', (tester) async {
    await pump(tester, UpdateRoute.gitHub);

    expect(find.text('Download from GitHub'), findsOneWidget);
    expect(find.text('Download installer'), findsNothing);
    expect(find.text('Get on Microsoft Store'), findsNothing);
  });

  testWidgets('the AppImage offers to update in place', (tester) async {
    await pump(tester, UpdateRoute.appImage);

    expect(find.text('Update in place and restart.'), findsOneWidget);
    expect(find.text('Download installer'), findsNothing);
  });
}
