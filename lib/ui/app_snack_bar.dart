import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The shortest time any snackbar stays on screen.
const Duration kSnackBarMinDuration = Duration(seconds: 4);

/// The shortest time a snackbar with an action (Undo, Open…) stays on screen,
/// so there is time to reach the button.
const Duration kSnackBarActionMinDuration = Duration(seconds: 8);

/// The longest a snackbar is kept up for reading time alone. A caller asking
/// for longer explicitly still gets it.
const Duration kSnackBarMaxReadingDuration = Duration(seconds: 12);

/// Reading time per character of the message.
const Duration kSnackBarPerCharacter = Duration(milliseconds: 60);

/// How long a snackbar stays up: long enough to read [message], longer when it
/// carries an action, never shorter than [requested].
///
/// [requested] is the [SnackBar.duration] the caller built it with. Flutter's
/// default (4 s) can't be told apart from an explicit 4 s, so it is treated as
/// a minimum rather than an exact time.
Duration snackBarDisplayDuration({
  String? message,
  required bool hasAction,
  Duration requested = kSnackBarMinDuration,
}) {
  final reading = Duration(
    milliseconds:
        1500 + (message?.length ?? 0) * kSnackBarPerCharacter.inMilliseconds,
  );
  final floor = hasAction ? kSnackBarActionMinDuration : kSnackBarMinDuration;
  final readingMs = reading.inMilliseconds.clamp(
    floor.inMilliseconds,
    kSnackBarMaxReadingDuration.inMilliseconds,
  );
  return Duration(milliseconds: math.max(readingMs, requested.inMilliseconds));
}

/// The plain text of a snackbar's content, when it is a [Text].
String? snackBarMessage(Widget content) {
  if (content is Text) return content.data ?? content.textSpan?.toPlainText();
  return null;
}

/// [snackBar] as the app shows it: it always times out, always has a close
/// button, and stays up long enough to read and to reach its action.
SnackBar normalizeSnackBar(SnackBar snackBar) {
  return SnackBar(
    key: snackBar.key,
    content: snackBar.content,
    backgroundColor: snackBar.backgroundColor,
    elevation: snackBar.elevation,
    margin: snackBar.margin,
    padding: snackBar.padding,
    width: snackBar.width,
    shape: snackBar.shape,
    hitTestBehavior: snackBar.hitTestBehavior,
    behavior: snackBar.behavior,
    action: snackBar.action,
    actionOverflowThreshold: snackBar.actionOverflowThreshold,
    showCloseIcon: snackBar.showCloseIcon ?? true,
    closeIconColor: snackBar.closeIconColor,
    duration: snackBarDisplayDuration(
      message: snackBarMessage(snackBar.content),
      hasAction: snackBar.action != null,
      requested: snackBar.duration,
    ),
    // Flutter makes a snackbar with an action persist by default — it never
    // times out and sits over the bottom of the window until swiped away.
    persist: false,
    animation: snackBar.animation,
    onVisible: snackBar.onVisible,
    dismissDirection: snackBar.dismissDirection,
    clipBehavior: snackBar.clipBehavior,
  );
}

/// The one way the app shows a snackbar.
extension AppSnackBars on ScaffoldMessengerState {
  /// Shows [snackBar] through [normalizeSnackBar], replacing whatever is on
  /// screen or queued: the newest message wins instead of waiting its turn
  /// behind older ones.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    SnackBar snackBar,
  ) {
    clearSnackBars();
    // The one place `showSnackBar` is called directly (see
    // test/ui/app_snack_bar_test.dart).
    return showSnackBar(normalizeSnackBar(snackBar));
  }
}
