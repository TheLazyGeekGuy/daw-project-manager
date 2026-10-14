import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/sample_pack/master_project.dart';

void main() {
  // Real names from a library where every song has a master project.
  const masters = [
    r'C:\Songs\Nebula\Master Project\2024_001_Audio Crawler - Nebula (Master).cpr',
    r'C:\Songs\Seek More\Master Project\Seek More (M).cpr',
    r'C:\Songs\Shivers\Master Project New\Shivers (Remix)-01 (M).cpr',
    r'C:\Songs\Awakening\Master Project New\Awakening With You (Remix) M-1.cpr',
    r'C:\Songs\Empire\Master Project New\Empire of Steel (AC RMX 2025 M).cpr',
    r'C:\Songs\Muse\Master Project2\Map of the Problematique (AC vs Reisser 2026 master).cpr',
    r'C:\Songs\Bulletproof\Master Project\Bulletproof (Audio Crawler Remix) M.cpr',
    '/Users/me/Songs/At Night/At Night (Remix) - Master/At Night.cpr',
    '/Users/me/Songs/Backtrack/Master project/Backtrack.cpr',
    '/Users/me/Songs/Hero/mastering/Hero.als',
    'Song - Mastering.rpp',
  ];

  const regular = [
    r'C:\Songs\Nebula\2024_001_Audio Crawler - Nebula.cpr',
    r'C:\Songs\Shivers\Shivers (Audio Crawler vs M4rs Remix)-01.cpr',
    r'C:\Songs\Phoenix\2024_007_M4rs vs Audio Crawler - Phoenix.cpr',
    r'C:\Songs\Mini Mix\2025_015_10_Audio Crawler Mini Mix.cpr',
    '/Users/me/Songs/Metallica - Master of Puppets (Remix)/Master of Puppets (Remix).als',
    '/Users/me/Songs/Mastermind/Mastermind.als',
    '/Users/me/Songs/Pitty/Admiravel Chip Novo (AC vs Reisser Remix).cpr',
    '/Users/me/Songs/Pitty/Song in Em.cpr',
  ];

  for (final path in masters) {
    test('a master project: $path', () {
      expect(isMasterProject(path), isTrue);
    });
  }

  for (final path in regular) {
    test('not a master project: $path', () {
      expect(isMasterProject(path), isFalse);
    });
  }
}
