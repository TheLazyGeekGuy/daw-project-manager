import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/services/companion_bridge/companion_protocol.dart';
import 'package:daw_project_manager/services/companion_bridge/riverpod_companion_session_hooks.dart';
import 'package:daw_project_manager/ui/dialogs/companion_session_ended_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final pt = lookupAppLocalizations(const Locale('pt'));

  CompanionSessionEnded ended(CompanionDepartureReason reason, {String host = 'Steinberg Cubase 13', int seconds = 3060}) {
    final start = DateTime(2026, 10, 18, 12, 51);
    return CompanionSessionEnded(
      'Teardrop',
      CompanionDeparture(start.add(Duration(seconds: seconds)), reason, hostName: host),
      (start: start, end: start.add(Duration(seconds: seconds)), seconds: seconds),
    );
  }

  test('session lengths read like the end-session dialog\'s', () {
    expect(formatSessionLength(30), '< 1m');
    expect(formatSessionLength(52 * 60), '52m');
    expect(formatSessionLength(3600 + 5 * 60), '1h 5m');
  });

  test('the summary shows local start and end, and the length', () {
    expect(companionSessionSummary(en, ended(CompanionDepartureReason.closed)), '12:51–13:42 · 51m');
  });

  test('closing the project names the DAW and the project', () {
    expect(companionSessionEndedReason(en, ended(CompanionDepartureReason.closed)),
        'Steinberg Cubase 13 closed Teardrop, so its work session ended.');
  });

  test('a silent plugin says so, and says the DAW may have crashed', () {
    final text = companionSessionEndedReason(en, ended(CompanionDepartureReason.stoppedResponding));
    expect(text, contains('stopped responding in Steinberg Cubase 13'));
    expect(text, contains('Teardrop'));
    expect(text, contains('crashed'));
  });

  test('an unknown DAW is "Your DAW", in the user\'s language', () {
    expect(companionSessionEndedReason(en, ended(CompanionDepartureReason.closed, host: '')),
        startsWith('Your DAW closed Teardrop'));
    expect(companionSessionEndedReason(pt, ended(CompanionDepartureReason.closed, host: ' ')),
        startsWith('Sua DAW fechou Teardrop'));
  });
}
