import 'package:flutter/foundation.dart';

/// Set by the screenshot tool (`--dart-define=DPM_SCREENSHOTS=true`, see
/// `scripts/capture_screenshots.ps1`). The pictures show the app a user gets,
/// and the tool runs a debug build: without this, every debug-only tool would
/// be in them.
const bool screenshotMode = bool.fromEnvironment('DPM_SCREENSHOTS');

/// Tools for working on the app itself — the testing database, notification
/// debugging: in a debug build, never in a release and never in a screenshot.
const bool showDeveloperTools = kDebugMode && !screenshotMode;
