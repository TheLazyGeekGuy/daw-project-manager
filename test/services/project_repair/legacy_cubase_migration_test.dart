import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/legacy_cubase_migration.dart';

void main() {
  late Directory directory;
  late File song;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dpm-legacy-cubase-');
    song = File('${directory.path}/classic.ALL');
    await song.writeAsBytes([1, 2, 3, 4, 5]);
  });

  tearDown(() => directory.delete(recursive: true));

  test('recognizes only .ALL and .ARR without claiming direct parsing', () {
    expect(LegacyCubaseMigration.accepts('old.ALL'), true);
    expect(LegacyCubaseMigration.accepts('old.ARR'), true);
    expect(LegacyCubaseMigration.accepts('old.cpr'), false);
    expect(LegacyCubaseMigration.documentedLossRisks,
        anyElement(contains('VST')));
  });

  test('preparation retains a verified immutable legacy copy', () async {
    final result = await LegacyCubaseMigration.prepare(song);
    expect(result.legacySha256.length, 64);
    expect(await File(result.backupPath).readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await song.readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('rejects conversion result that is not a CPR', () async {
    final prepared = await LegacyCubaseMigration.prepare(song);
    await expectLater(
      LegacyCubaseMigration.validate(
        prepared, File('${directory.path}/song.rpp'),
      ),
      throwsFormatException,
    );
  });

  test('fails if legacy source changed after preparation', () async {
    final prepared = await LegacyCubaseMigration.prepare(song);
    await song.writeAsBytes([99, 100]);
    await expectLater(
      LegacyCubaseMigration.validate(
        prepared, File('${directory.path}/converted.cpr'),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('refuses missing or empty source', () async {
    final empty = File('${directory.path}/empty.arr');
    await empty.writeAsBytes([]);
    await expectLater(
      LegacyCubaseMigration.prepare(empty),
      throwsA(isA<FileSystemException>()),
    );
  });
}
