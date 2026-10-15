import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../models/scan_root.dart';
import '../repository/profile_repository.dart';

/// How a folder about to be scanned meets one another profile scans.
enum RootOverlapKind {
  /// The very same folder.
  same,

  /// Inside the other profile's folder.
  inside,

  /// Holds the other profile's folder.
  contains,
}

/// A scan folder of another profile that a new one would overlap.
class RootOverlap {
  const RootOverlap({
    required this.profileName,
    required this.rootPath,
    required this.kind,
  });

  final String profileName;
  final String rootPath;
  final RootOverlapKind kind;
}

/// The other profiles' scan folders [path] would overlap, keyed in
/// [otherProfileRoots] by profile name.
///
/// Each profile scans its folders on its own and gives every project it
/// finds its own row, so a folder scanned by two profiles puts each of its
/// projects in both as two independent copies — notes, to-dos and work time
/// going their separate ways. With a profile per artist that is never what
/// was meant, so adding one is worth a warning.
List<RootOverlap> findRootOverlaps(
  String path,
  Map<String, List<String>> otherProfileRoots,
) {
  final candidate = p.normalize(path);
  return [
    for (final entry in otherProfileRoots.entries)
      for (final root in entry.value)
        if (_overlap(candidate, p.normalize(root)) case final kind?)
          RootOverlap(profileName: entry.key, rootPath: root, kind: kind),
  ];
}

RootOverlapKind? _overlap(String candidate, String root) {
  if (p.equals(candidate, root)) return RootOverlapKind.same;
  if (p.isWithin(root, candidate)) return RootOverlapKind.inside;
  if (p.isWithin(candidate, root)) return RootOverlapKind.contains;
  return null;
}

/// Every profile's scan folders but [currentProfileId]'s, by profile name.
Future<Map<String, List<String>>> otherProfilesRoots(
  ProfileRepository profileRepo,
  String? currentProfileId,
) async {
  final result = <String, List<String>>{};
  for (final profile in profileRepo.getAllProfiles()) {
    if (profile.id == currentProfileId) continue;
    try {
      final box = await Hive.openBox<ScanRoot>('${profile.id}_roots');
      final paths = [for (final r in box.values) r.path];
      if (paths.isNotEmpty) result[profile.name] = paths;
    } catch (_) {}
  }
  return result;
}
