# Development setup

[← README](../README.md) · **Development** · [Testing](testing.md) · [Architecture](architecture.md) · [Releasing](releasing.md)

## 1. Install Flutter 3.47.7 and your platform's tools

| Platform | You need | Run with |
|---|---|---|
| <img src="../resources/os/Windows_logo_-_2012.svg" height="16"> Windows | Visual Studio 2022, workload **Desktop development with C++** | `flutter run -d windows` |
| <img src="../resources/os/MacOS_logo_(2017).svg" height="16"> macOS | Xcode, CocoaPods | `flutter run -d macos` |
| <img src="../resources/os/Linux_logo.svg" height="16"> Linux | the packages below | `flutter run -d linux` |
| <img src="../resources/os/android-head.png" height="16"> Android | Android Studio + SDK | `flutter run -d <device>` |
| iOS | Xcode, CocoaPods (builds; not shipped yet) | `flutter run -d <device>` |

Linux packages (Debian/Ubuntu):

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libayatana-appindicator3-dev libnotify-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

`flutter doctor` tells you what's still missing.

## 2. Clone and run

```bash
git clone https://github.com/bandpassrecords/daw-project-manager.git
cd daw-project-manager
cp lib/config/oauth_config.dart.template lib/config/oauth_config.dart
flutter pub get
flutter run -d windows
```

The copied `oauth_config.dart` is required to build. Its placeholder values are fine: everything works except signing in to Google Drive.

## Your own library stays safe

A debug build keeps its library in its own folder (`daw_project_manager_dev`), apart from the installed app's. For a throwaway one:

```bash
flutter run -d windows --dart-define=DPM_DATA_DIR=daw_project_manager_try
```

## After changing…

| … | run |
|---|---|
| a `@HiveType` model | `dart run build_runner build --delete-conflicting-outputs` |
| a UI string (`lib/l10n/app_en.arb` + every `app_*.arb`) | `flutter gen-l10n` |
| anything | `flutter test` — see [Testing](testing.md) |

## Google Drive sign-in (optional)

Only needed to try Drive sync on your own build. In a Google Cloud project with the **Google Drive API** enabled, create these OAuth clients:

| Client type | Gives you |
|---|---|
| **Desktop app** | the desktop client ID and client secret |
| **Web application** | the Android web client ID (Android sign-in passes it as `serverClientId`) |

Write them into `lib/config/oauth_config.dart`, from the repository root:

```powershell
# Windows (PowerShell)
.\scripts\inject_oauth_config.ps1 -DesktopClientId "<desktop client id>" -DesktopClientSecret "<desktop client secret>" -AndroidWebClientId "<android web client id>"
```

```bash
# macOS, Linux
./scripts/inject_oauth_config.sh -d "<desktop client id>" -s "<desktop client secret>" -a "<android web client id>"
```

The script always starts again from the template, so run it again to change a value. Then, per platform:

| Platform | Also needed |
|---|---|
| Windows, macOS, Linux | nothing: sign-in opens your browser |
| Android | a third client, type **Android**, for package `com.bandpassrecords.dpm` and the SHA-1 of the key your build is signed with. Without it, sign-in fails with error 10. |
| iOS | nothing: its client ID is already in `ios/Runner/Info.plist` |
| Flatpak | skip all of this: Drive sync isn't offered inside the Flatpak sandbox ([why](../flatpak/README.md)) |

A debug build is signed with the debug keystore; its SHA-1:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
# Windows: -keystore "%USERPROFILE%\.android\debug.keystore"
```

Never commit `oauth_config.dart`. Why a secret is needed at all: [`lib/config/README.md`](../lib/config/README.md).

## Refreshing the screenshots

```powershell
scripts/capture_screenshots.ps1
```

Opens the app on a demo library (never yours), visits every screen and rewrites `resources/screenshots/` — at 1920×1080, Classic Dark, no version in the title. Run it after a UI change; copy what changed to the `gh-pages` branch for the website. New screens go in `integration_test/screenshots/capture_test.dart`.

## Making a change

1. Branch from `main`.
2. Follow the codebase's rules in [`CLAUDE.md`](../CLAUDE.md): every UI string translated, a test with every fix, which data syncs.
3. Open a pull request. CI runs **Unit tests** on Windows, macOS and Linux and builds every platform; all must pass. After the merge it does both again on `main`, building nothing for release: two pull requests merged one after the other were each checked only against the `main` before the other.
