import 'dart:io';

import 'package:daw_project_manager/utils/save_file_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('savedLocation', () {
    test('a cancelled dialog saved nothing', () {
      expect(savedLocation(null), isNull);
    });

    test('a file URI reads back as the path it names', () {
      final path = p.join(Directory.systemTemp.path, 'backup 2026.json');
      expect(savedLocation(Uri.file(path)), path);
    });

    test("a phone's content URI is shown as it is: there is no path", () {
      final uri = Uri.parse(
          'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fclip.mid');
      expect(savedLocation(uri), uri.toString());
    });
  });
}
