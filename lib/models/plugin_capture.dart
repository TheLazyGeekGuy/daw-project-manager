/// The latest pass the DAW plugin captured for a project: a pre-listen of
/// where the song is, kept beside the preview song, never in its place. The
/// preview song is what the user chose or the newest bounce; a capture is
/// only ever the last thing played in the DAW, so the two answer different
/// questions and neither may stand in for the other.
///
/// Only the latest is kept: each new capture replaces it (the plugin itself
/// keeps one per instance). User data: it syncs and backs up with the
/// project, file included, like the preview song.
class PluginCapture {
  const PluginCapture({
    required this.path,
    required this.capturedAt,
    required this.durationSeconds,
  });

  /// The app's own copy, under `preview_songs/plugin/<project id>/`.
  final String path;

  /// When the plugin finished the take (its own clock, made local).
  final DateTime capturedAt;

  final double durationSeconds;

  Map<String, dynamic> toMap() => {
        'path': path,
        'at': capturedAt.toUtc().toIso8601String(),
        'seconds': durationSeconds,
      };

  /// Lenient on purpose, like `ProjectStats`: this runs inside Hive's
  /// adapter and on Drive/backup payloads, so a malformed value costs the
  /// capture, never the project.
  static PluginCapture? tryFromMap(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    final at = value['at'] is String ? DateTime.tryParse(value['at'] as String) : null;
    final seconds = value['seconds'];
    if (path is! String || path.isEmpty || at == null || seconds is! num) return null;
    return PluginCapture(path: path, capturedAt: at.toLocal(), durationSeconds: seconds.toDouble());
  }

  PluginCapture copyWith({String? path}) =>
      PluginCapture(path: path ?? this.path, capturedAt: capturedAt, durationSeconds: durationSeconds);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginCapture &&
          path == other.path &&
          capturedAt.isAtSameMomentAs(other.capturedAt) &&
          durationSeconds == other.durationSeconds;

  @override
  int get hashCode => Object.hash(path, capturedAt.millisecondsSinceEpoch, durationSeconds);
}
