import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:daw_project_manager/utils/path_rebase.dart';

void main() {
  // An absolute path on every platform (C:\… on Windows, /tmp/… elsewhere).
  final base = p.join(Directory.systemTemp.path, 'dpm_rebase');
  final music = p.join(base, 'Proton Drive', 'Music');
  final moved = p.join(base, 'D', 'Music');

  test('the folder itself becomes the new folder', () {
    expect(rebasePath(music, from: music, to: moved), p.normalize(moved));
  });

  test('a path inside keeps its tail', () {
    expect(
      rebasePath(p.join(music, 'Song', 'Song.als'), from: music, to: moved),
      p.join(moved, 'Song', 'Song.als'),
    );
  });

  test('a sibling that only starts with the same name is not inside', () {
    // "Music2" begins with "Music": a text prefix match moved it too.
    expect(rebasePath(p.join('${music}2', 'Song.als'), from: music, to: moved), isNull);
  });

  test('a path elsewhere, or above, is left alone', () {
    expect(rebasePath(p.join(base, 'Other', 'Song.als'), from: music, to: moved), isNull);
    expect(rebasePath(base, from: music, to: moved), isNull);
  });

  test('a trailing separator on either folder makes no difference', () {
    expect(
      rebasePath(p.join(music, 'a.als'), from: '$music${p.separator}', to: '$moved${p.separator}'),
      p.join(moved, 'a.als'),
    );
  });

  test('a Drive fallback reference and an empty path are never paths inside', () {
    expect(rebasePath('drive://abc123', from: music, to: moved), isNull);
    expect(rebasePath('', from: music, to: moved), isNull);
  });

  test('on Windows, a drive letter in another case still matches', () {
    final upper = music.toUpperCase();
    expect(rebasePath(p.join(upper, 'Song.als'), from: music, to: moved), p.join(moved, 'Song.als'));
  }, skip: Platform.isWindows ? false : 'Windows compares paths case-insensitively; other platforms do not');
}
