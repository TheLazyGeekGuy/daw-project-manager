import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/utils/folder_tree.dart';

void main() {
  test('draws folders first, then files, with counts', () {
    final text = folderTreeText('Pack', [
      'sample_pack_report.csv',
      'Kick/kick 2.wav',
      'Kick/distorted/dist kick.wav',
      'Kick/Kick 1.wav',
      'MIDI/Ideas/Lead 01.mid',
      'Bass/bass.wav',
    ]);
    expect(text, '''
Pack/ (6)
├── Bass/ (1)
│   └── bass.wav
├── Kick/ (3)
│   ├── distorted/ (1)
│   │   └── dist kick.wav
│   ├── Kick 1.wav
│   └── kick 2.wav
├── MIDI/ (1)
│   └── Ideas/ (1)
│       └── Lead 01.mid
└── sample_pack_report.csv
''');
  });

  test('an empty folder is just its name', () {
    expect(folderTreeText('Pack', const []), 'Pack/ (0)\n');
  });

  test('ignores empty path segments and lists a file once', () {
    expect(
      folderTreeText('P', ['/a//b.wav', 'a/b.wav']),
      'P/ (1)\n└── a/ (1)\n    └── b.wav\n',
    );
  });
}
