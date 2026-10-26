import 'dart:async';

import 'package:daw_project_manager/generated/l10n/app_localizations.dart';
import 'package:daw_project_manager/generated/l10n/app_localizations_en.dart';
import 'package:daw_project_manager/ui/widgets/release_metadata_form.dart';
import 'package:daw_project_manager/utils/localization_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _l = AppLocalizationsEn();

Future<Completer<Map<String, dynamic>?>> _open(
  WidgetTester tester, {
  required Map<String, dynamic> initial,
  required List<ReleaseMetadataField> fields,
}) async {
  final result = Completer<Map<String, dynamic>?>();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-fixture-form'),
            onPressed: () async {
              result.complete(
                await showReleaseMetadataForm(
                  context: context,
                  title: 'Fixture release metadata',
                  initial: initial,
                  fields: fields,
                ),
              );
            },
            child: const Text('Open fixture form'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-fixture-form')));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('apply-record')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an optional choice with an empty saved value can remain empty', (
    tester,
  ) async {
    final initial = <String, dynamic>{'id': 'asset-1', 'role': ''};
    final result = await _open(
      tester,
      initial: initial,
      fields: const [
        ReleaseMetadataField(
          'role',
          'Fixture role',
          kind: ReleaseFieldKind.choice,
          choices: {'master': 'Master', 'instrumental': 'Instrumental'},
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('field-role')), findsOneWidget);
    await _apply(tester);
    expect(await result.future, {'id': 'asset-1', 'role': null});
    expect(initial, {'id': 'asset-1', 'role': ''});
    expect(tester.takeException(), isNull);
  });

  testWidgets('an optional selected choice can be cleared through None', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initial: {'role': 'master'},
      fields: const [
        ReleaseMetadataField(
          'role',
          'Fixture role',
          kind: ReleaseFieldKind.choice,
          choices: {'master': 'Master'},
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('field-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l.releaseManagerNone).last);
    await tester.pumpAndSettle();
    await _apply(tester);
    expect(await result.future, {'role': null});
  });

  testWidgets('calendar dates reject overflow instead of silently changing the day', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initial: {},
      fields: const [
        ReleaseMetadataField(
          'release_date',
          'Fixture release date',
          kind: ReleaseFieldKind.date,
        ),
      ],
    );
    final input = find.byKey(const ValueKey('field-release_date'));
    await tester.enterText(input, '2026-02-30');
    await _apply(tester);
    expect(result.isCompleted, isFalse);
    expect(find.text(_l.releaseManagerInvalidDate), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(input, '2024-02-29');
    await _apply(tester);
    expect(await result.future, {'release_date': '2024-02-29'});
  });

  testWidgets('a release date stays a calendar date without an offset or UTC shift', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initial: {'release_date': '2026-01-01'},
      fields: const [
        ReleaseMetadataField(
          'release_date',
          'Fixture release date',
          kind: ReleaseFieldKind.date,
        ),
      ],
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-release_date')),
      '2026-10-26',
    );
    await _apply(tester);
    expect(await result.future, {'release_date': '2026-10-26'});
  });

  testWidgets('a timestamp with an explicit offset is stored as the same UTC instant', (
    tester,
  ) async {
    final result = await _open(
      tester,
      initial: {},
      fields: const [
        ReleaseMetadataField(
          'scheduled_at',
          'Fixture schedule',
          kind: ReleaseFieldKind.dateTime,
        ),
      ],
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-scheduled_at')),
      '2026-10-26T00:30:00+14:00',
    );
    await _apply(tester);
    expect(await result.future, {'scheduled_at': '2026-10-25T10:30:00.000Z'});
  });

  testWidgets('editing known fields preserves unknown metadata and the source map', (
    tester,
  ) async {
    final initial = <String, dynamic>{
      'id': 'track-1',
      'title': 'Before',
      'artist_ids': ['artist-1'],
      'future_metadata': {
        'version': 8,
        'flags': ['keep', 'opaque'],
      },
    };
    final result = await _open(
      tester,
      initial: initial,
      fields: const [
        ReleaseMetadataField('title', 'Fixture title'),
        ReleaseMetadataField(
          'artist_ids',
          'Fixture artists',
          kind: ReleaseFieldKind.references,
          choices: {'artist-1': 'Artist One', 'artist-2': 'Artist Two'},
        ),
      ],
    );
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'After');
    await tester.tap(find.widgetWithText(FilterChip, 'Artist Two'));
    await tester.pumpAndSettle();
    await _apply(tester);
    final saved = await result.future;
    expect(saved, {
      'id': 'track-1',
      'title': 'After',
      'artist_ids': ['artist-1', 'artist-2'],
      'future_metadata': {
        'version': 8,
        'flags': ['keep', 'opaque'],
      },
    });
    expect(initial['title'], 'Before');
    expect(initial['artist_ids'], ['artist-1']);
  });

  testWidgets('cancelling discards text and reference edits', (tester) async {
    final initial = <String, dynamic>{
      'title': 'Original',
      'artist_ids': ['artist-1'],
      'future_field': 'retained',
    };
    final result = await _open(
      tester,
      initial: initial,
      fields: const [
        ReleaseMetadataField('title', 'Fixture title'),
        ReleaseMetadataField(
          'artist_ids',
          'Fixture artists',
          kind: ReleaseFieldKind.references,
          choices: {'artist-1': 'Artist One', 'artist-2': 'Artist Two'},
        ),
      ],
    );
    await tester.enterText(find.byKey(const ValueKey('field-title')), 'Discarded');
    await tester.tap(find.widgetWithText(FilterChip, 'Artist Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _l.cancel));
    await tester.pumpAndSettle();
    expect(await result.future, isNull);
    expect(initial, {
      'title': 'Original',
      'artist_ids': ['artist-1'],
      'future_field': 'retained',
    });
  });
}
