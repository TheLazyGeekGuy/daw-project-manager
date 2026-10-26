import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/project_repair/legacy_all_conversion_service.dart';
import 'package:daw_project_manager/services/project_repair/midi_file_validator.dart';

import '../../helpers/legacy_all_fixture.dart';

void main() {
  late Directory root;
  late File source;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dpm-legacy-all-test-');
    source = File('${root.path}/original.ALL');
    await source.writeAsBytes(legacyAllFixture());
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'backs up ALL and writes separately verified MIDI on repeated conversions',
    () async {
      final originalBytes = await source.readAsBytes();
      final first = await LegacyAllConversionService.convert(
        original: source,
        acknowledgeFidelityRisks: true,
      );
      final second = await LegacyAllConversionService.convert(
        original: source,
        acknowledgeFidelityRisks: true,
      );
      expect(first['output'], isNot(second['output']));
      expect(await source.readAsBytes(), originalBytes);
      expect(
        await File(first['backup'] as String).readAsBytes(),
        originalBytes,
      );
      expect(
        MidiFileValidator.inspect(
          await File(first['output'] as String).readAsBytes(),
        ).noteCount,
        1,
      );
      expect(first['native_daw_reopen_verified'], false);
    },
  );
  test('requires explicit loss acceptance and refuses ARR', () async {
    await expectLater(
      LegacyAllConversionService.convert(
        original: source,
        acknowledgeFidelityRisks: false,
      ),
      throwsFormatException,
    );
    final arr = File('${root.path}/arrangement.ARR');
    await arr.writeAsBytes(legacyAllFixture());
    await expectLater(
      LegacyAllConversionService.convert(
        original: arr,
        acknowledgeFidelityRisks: true,
      ),
      throwsFormatException,
    );
  });
}
