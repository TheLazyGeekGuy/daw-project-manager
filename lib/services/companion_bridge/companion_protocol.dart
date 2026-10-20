import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/music_project.dart';
import '../../models/profile.dart';
import '../../models/todo_item.dart';

/// The app's side of the DAW Project Manager plugin's protocol — the pure part:
/// what goes into `index.json`, how the plugin's messages are read, and what
/// they do to a project. File I/O lives in `companion_bridge_service.dart`.
///
/// The contract is `docs/PROTOCOL.md` in bandpassrecords/daw-project-manager-plugin; this
/// file and that one change together.

/// `index.json`'s schema. A breaking change gets a new file name, not a new
/// number here: older plugins read any schema >= 1 and ignore unknown fields.
const int companionIndexSchema = 1;

/// One profile and its projects, as the bridge sees them.
class CompanionProfileProjects {
  final Profile profile;
  final List<MusicProject> projects;

  const CompanionProfileProjects(this.profile, this.projects);
}

/// The row a project's to-dos live on: a version-stack member's are its
/// stack's (the stack owns the shared metadata), everything else's its own.
MusicProject companionOwnerOf(MusicProject project, List<MusicProject> profileProjects) {
  final stackId = project.stackId;
  if (stackId == null) return project;
  for (final candidate in profileProjects) {
    if (candidate.id == stackId && candidate.isVirtual) return candidate;
  }
  return project;
}

/// Whether a project belongs in the plugin's list: it has a file a DAW can
/// open. Stacks (no file of their own) and archived projects (zipped away)
/// don't; a stack's members do, carrying the stack's to-dos.
bool companionListsProject(MusicProject project) => !project.isVirtual && !project.isArchived;

/// The newest plugin release on GitHub, for the plugin's "Update available".
class CompanionRelease {
  final String version;

  /// The release page.
  final String url;

  /// The installer for each platform, when the release has one.
  final Map<CompanionPlatform, String> downloads;

  const CompanionRelease(this.version, this.url, {this.downloads = const {}});
}

/// The desktop platforms the plugin ships installers for.
enum CompanionPlatform { windows, macOS, linux }

/// Where the plugin's releases live: the fallback when the newest release
/// isn't known (update checks off, offline, the Flatpak).
const companionReleasesPage = 'https://github.com/bandpassrecords/daw-project-manager-plugin/releases/latest';

/// The plugin installer's file name on a release, per platform — the names
/// the plugin's CI gives them (`packaging/`), version in the middle. Releases
/// up to v0.1.x named them DPM_Companion_….
final Map<CompanionPlatform, RegExp> _installerNames = {
  CompanionPlatform.windows: RegExp(r'^(DAW_Project_Manager_Plugin|DPM_Companion)_Installer_v[\d.]+\.exe$'),
  CompanionPlatform.macOS: RegExp(r'^(DAW_Project_Manager_Plugin|DPM_Companion)_macOS_Installer_v[\d.]+\.pkg$'),
  CompanionPlatform.linux: RegExp(r'^(DAW_Project_Manager_Plugin|DPM_Companion)_Linux_x86_64_v[\d.]+\.tar\.gz$'),
};

/// What "Download the DAW plugin" opens: this platform's installer from the
/// newest release, else that release's page, else the releases page.
String companionDownloadUrl(CompanionRelease? release, CompanionPlatform platform) =>
    release?.downloads[platform] ?? release?.url ?? companionReleasesPage;

/// Whether [remote] is a strictly newer x.y.z version than [local]. A
/// version that isn't x.y.z is never newer.
bool isNewerCompanionVersion(String remote, String local) {
  List<int>? parse(String v) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final r = parse(remote), l = parse(local);
  if (r == null || l == null) return false;
  for (var i = 0; i < 3; i++) {
    if (r[i] != l[i]) return r[i] > l[i];
  }
  return false;
}

/// The last time this computer saw the plugin running, and which: for the
/// DAW plugin settings ("last seen in … version …") and its update offer.
/// Device-local.
class CompanionSighting {
  final String version;
  final String hostName;
  final DateTime at;

  const CompanionSighting(this.version, this.hostName, this.at);

  Map<String, dynamic> toJson() => {'version': version, 'host': hostName, 'at': at.toUtc().toIso8601String()};

  static CompanionSighting? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final version = json['version'], host = json['host'], at = companionTime(json['at']);
    if (version is! String || version.isEmpty || at == null) return null;
    return CompanionSighting(version, host is String ? host : '', at);
  }

  /// Whether this sighting says something [previous] didn't: a version or
  /// host change, or simply a minute later — so the record stays current
  /// without being rewritten on every heartbeat.
  bool isNewsAfter(CompanionSighting? previous) =>
      previous == null ||
      version != previous.version ||
      hostName != previous.hostName ||
      at.difference(previous.at) >= const Duration(minutes: 1);
}

/// `index.json`: every profile's projects with the to-dos the app shows for
/// them. Every profile, not just the active one — a DAW session belongs to
/// whichever artist it belongs to. [latestRelease], when known, lets the
/// plugin offer its own update without going on the network itself.
Map<String, dynamic> buildCompanionIndex(
  List<CompanionProfileProjects> library, {
  required DateTime generatedAt,
  required String appVersion,
  CompanionRelease? latestRelease,
  List<String> appliedMessageIds = const [],
}) {
  final projects = <Map<String, dynamic>>[];

  for (final entry in library) {
    for (final project in entry.projects) {
      if (!companionListsProject(project)) continue;
      final owner = companionOwnerOf(project, entry.projects);
      projects.add({
        'id': project.id,
        'profileId': entry.profile.id,
        'profileName': entry.profile.name,
        'name': project.displayName,
        'filePath': project.filePath,
        'dawType': project.dawType ?? '',
        'notes': owner.notes ?? '',
        'todos': [
          for (final todo in owner.todos)
            {
              'id': todo.id,
              'text': todo.text,
              'completed': todo.completed,
              'createdAt': todo.createdAt.toUtc().toIso8601String(),
            },
        ],
      });
    }
  }

  return {
    'schema': companionIndexSchema,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'app': {'version': appVersion},
    if (latestRelease != null)
      'companion': {'latestVersion': latestRelease.version, 'releaseUrl': latestRelease.url},
    // The plugin messages handled lately: how a notes edit learns it arrived.
    'applied': appliedMessageIds,
    'projects': projects,
  };
}

/// Reads GitHub's "latest release" answer for the plugin's repo. Null when it
/// isn't one (no tag, no page, a version that isn't x.y.z).
CompanionRelease? parseCompanionRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  final url = json['html_url'];
  if (tag is! String || url is! String) return null;
  final version = tag.replaceFirst(RegExp(r'^v'), '');
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) return null;

  final downloads = <CompanionPlatform, String>{};
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'], link = asset['browser_download_url'];
      if (name is! String || link is! String) continue;
      for (final entry in _installerNames.entries) {
        if (entry.value.hasMatch(name)) downloads[entry.key] = link;
      }
    }
  }
  return CompanionRelease(version, url, downloads: downloads);
}

/// The index without its timestamp, for "did anything change?" — rewriting
/// an identical index every few seconds would be pointless disk churn.
String companionIndexFingerprint(Map<String, dynamic> index) =>
    jsonEncode({...index}..remove('generatedAt'));

/// `launch.json`, written just before a project is opened in its DAW.
Map<String, dynamic> buildCompanionLaunchHint({
  required String profileId,
  required MusicProject project,
  required DateTime launchedAt,
}) => {
  'projectId': project.id,
  'profileId': profileId,
  'filePath': project.filePath,
  'launchedAt': launchedAt.toUtc().toIso8601String(),
};

// --- Messages from the plugin ------------------------------------------------

/// Which project a message is about. Matched by profile *and* id, never id
/// alone: one id can sit in two profiles.
class CompanionProjectRef {
  final String profileId;
  final String projectId;

  const CompanionProjectRef(this.profileId, this.projectId);
}

sealed class CompanionMessage {
  final String id;
  final DateTime createdAt;
  final CompanionProjectRef? project;

  /// The running plugin instance that sent it — never saved, so two open
  /// copies of one project are two instances. Null from older plugins.
  final String? runId;

  /// The DAW it runs in, as the host describes itself ("Steinberg Cubase 13").
  final String hostName;

  /// The plugin's own version.
  final String pluginVersion;

  const CompanionMessage(this.id, this.createdAt, this.project,
      {this.runId, this.hostName = '', this.pluginVersion = ''});
}

/// A plugin instance is running inside a project.
class CompanionHello extends CompanionMessage {
  const CompanionHello(super.id, super.createdAt, super.project, {super.runId, super.hostName, super.pluginVersion});
}

/// A plugin instance has left a project: the DAW closed it or quit, the
/// plugin was removed, or it was linked elsewhere. [createdAt] is when.
class CompanionGoodbye extends CompanionMessage {
  const CompanionGoodbye(super.id, super.createdAt, super.project, {super.runId, super.hostName});
}

class CompanionTodoAdd extends CompanionMessage {
  final String todoId;
  final String text;
  final DateTime todoCreatedAt;

  const CompanionTodoAdd(super.id, super.createdAt, super.project,
      {required this.todoId, required this.text, required this.todoCreatedAt});
}

class CompanionTodoSetCompleted extends CompanionMessage {
  final String todoId;
  final bool completed;

  const CompanionTodoSetCompleted(super.id, super.createdAt, super.project,
      {required this.todoId, required this.completed});
}

/// The project's notes, edited in the plugin: the whole new text and the
/// text it was edited from.
class CompanionNotesSet extends CompanionMessage {
  final String text;
  final String baseText;

  const CompanionNotesSet(super.id, super.createdAt, super.project, {required this.text, required this.baseText});
}

class CompanionCaptureReady extends CompanionMessage {
  /// Relative to the bridge folder, forward slashes.
  final String file;
  final double durationSeconds;
  final DateTime capturedAt;

  const CompanionCaptureReady(super.id, super.createdAt, super.project,
      {required this.file, required this.durationSeconds, required this.capturedAt});
}

/// A type this build doesn't know: logged and deleted, so a newer plugin
/// can't fill the folder.
class CompanionUnknownMessage extends CompanionMessage {
  final String type;

  const CompanionUnknownMessage(super.id, super.createdAt, super.project, this.type);
}

/// Longest to-do text accepted from the plugin (it sends at most 500).
const int companionMaxTodoLength = 500;

/// Longest notes text accepted from the plugin (it sends at most 20 000).
const int companionMaxNotesLength = 20000;

/// Put between the app's notes and the plugin's when both changed at once.
const companionNotesSeparator = '\n\n----------\n';

/// Reads one outbox file. Null when it isn't a message at all.
/// A time written by the plugin (UTC, "Z"), as the app keeps times: local.
/// Dart parses "…Z" as a UTC DateTime, and DateFormat prints it as such —
/// which is how a session once showed as 12:51–10:52 two hours east of UTC.
DateTime? companionTime(Object? value) => DateTime.tryParse('$value')?.toLocal();

CompanionMessage? parseCompanionMessage(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final id = decoded['id'];
  final type = decoded['type'];
  if (id is! String || id.isEmpty || type is! String) return null;

  final createdAt = companionTime(decoded['createdAt']) ?? DateTime.now();
  final project = _parseRef(decoded['project']);
  final payload = decoded['payload'] is Map<String, dynamic>
      ? decoded['payload'] as Map<String, dynamic>
      : const <String, dynamic>{};

  final plugin = decoded['plugin'];
  final runId = plugin is Map<String, dynamic> && plugin['runId'] is String && (plugin['runId'] as String).isNotEmpty
      ? plugin['runId'] as String
      : null;
  final pluginVersion = plugin is Map<String, dynamic> && plugin['version'] is String ? plugin['version'] as String : '';

  final host = decoded['host'];
  final hostName = host is Map<String, dynamic> && host['name'] is String ? host['name'] as String : '';

  switch (type) {
    case 'session.hello':
      return CompanionHello(id, createdAt, project, runId: runId, hostName: hostName, pluginVersion: pluginVersion);

    case 'session.goodbye':
      return CompanionGoodbye(id, createdAt, project, runId: runId, hostName: hostName);

    case 'todo.add':
      final todoId = payload['todoId'];
      final rawText = payload['text'];
      if (todoId is! String || todoId.isEmpty || rawText is! String) return null;
      final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) return null;
      return CompanionTodoAdd(id, createdAt, project,
          todoId: todoId,
          text: text.length > companionMaxTodoLength ? text.substring(0, companionMaxTodoLength) : text,
          todoCreatedAt: companionTime(payload['createdAt']) ?? createdAt);

    case 'todo.setCompleted':
      final todoId = payload['todoId'];
      final completed = payload['completed'];
      if (todoId is! String || completed is! bool) return null;
      return CompanionTodoSetCompleted(id, createdAt, project, todoId: todoId, completed: completed);

    case 'notes.set':
      final text = payload['text'];
      final baseText = payload['baseText'];
      if (text is! String || baseText is! String) return null;
      return CompanionNotesSet(id, createdAt, project,
          text: text.length > companionMaxNotesLength ? text.substring(0, companionMaxNotesLength) : text,
          baseText: baseText);

    case 'capture.ready':
      final file = payload['file'];
      if (file is! String || file.isEmpty) return null;
      return CompanionCaptureReady(id, createdAt, project,
          file: file,
          durationSeconds: (payload['durationSeconds'] as num?)?.toDouble() ?? 0,
          capturedAt: companionTime(payload['capturedAt']) ?? createdAt);

    default:
      return CompanionUnknownMessage(id, createdAt, project, type);
  }
}

CompanionProjectRef? _parseRef(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final id = value['id'];
  final profileId = value['profileId'];
  if (id is! String || id.isEmpty || profileId is! String) return null;
  return CompanionProjectRef(profileId, id);
}

/// [owner] with the plugin's to-do added, or null when it is already there —
/// which is what makes applying the same message twice harmless.
MusicProject? applyCompanionTodoAdd(MusicProject owner, CompanionTodoAdd message) {
  if (owner.todos.any((t) => t.id == message.todoId)) return null;
  return owner.copyWith(todos: [
    ...owner.todos,
    TodoItem(id: message.todoId, text: message.text, createdAt: message.todoCreatedAt),
  ]);
}

/// [owner] with the to-do ticked or unticked, or null when there is nothing
/// to change — including a to-do deleted in the app: a deletion beats a tick.
MusicProject? applyCompanionTodoSetCompleted(MusicProject owner, CompanionTodoSetCompleted message) {
  final index = owner.todos.indexWhere((t) => t.id == message.todoId);
  if (index < 0 || owner.todos[index].completed == message.completed) return null;
  final todos = [...owner.todos];
  todos[index] = todos[index].copyWith(completed: message.completed);
  return owner.copyWith(todos: todos);
}

// --- Presence: which projects a DAW has open --------------------------------

/// A plugin instance's heartbeat goes stale after this long without a
/// refresh (it refreshes every 10 s): the DAW died without a goodbye.
const companionHeartbeatStale = Duration(seconds: 90);

/// A gap this long between two of the app's own ticks means the computer
/// slept: every instance then gets a fresh [companionHeartbeatStale].
const companionSleepGap = Duration(seconds: 30);

/// One running plugin instance, present in a project.
class CompanionInstance {
  final String runId;
  final CompanionProjectRef project;
  final DateTime lastSeen;
  final String hostName;
  final String pluginVersion;

  const CompanionInstance(this.runId, this.project, this.lastSeen, {this.hostName = '', this.pluginVersion = ''});

  CompanionInstance seenAt(DateTime time) =>
      CompanionInstance(runId, project, time, hostName: hostName, pluginVersion: pluginVersion);
}

/// How an instance left its project.
enum CompanionDepartureReason {
  /// It said goodbye: the DAW closed the project or quit, or the plugin was
  /// removed.
  closed,

  /// It went quiet: no goodbye, and its heartbeat went stale — a crashed or
  /// killed DAW, most likely.
  stoppedResponding,
}

/// When and how the last instance in a project left it.
class CompanionDeparture {
  final DateTime at;
  final CompanionDepartureReason reason;
  final String hostName;

  const CompanionDeparture(this.at, this.reason, {this.hostName = ''});
}

/// Reads `instances/<runId>.json`. Null when it isn't a linked heartbeat.
CompanionInstance? parseCompanionHeartbeat(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final runId = decoded['runId'];
  final project = _parseRef(decoded['project']);
  final lastSeen = companionTime(decoded['lastSeen']);
  if (runId is! String || runId.isEmpty || project == null || lastSeen == null) return null;
  final host = decoded['host'];
  final hostName = host is Map<String, dynamic> && host['name'] is String ? host['name'] as String : '';
  final pluginVersion = decoded['pluginVersion'] is String ? decoded['pluginVersion'] as String : '';
  return CompanionInstance(runId, project, lastSeen, hostName: hostName, pluginVersion: pluginVersion);
}

/// The key a session is tracked under: profile and id, never id alone.
String companionKey(String profileId, String projectId) => '$profileId/$projectId';

/// What the plugin's comings and goings mean for the work session.
sealed class CompanionSessionAction {
  const CompanionSessionAction();
}

/// End the running session, at the moment the DAW let go of its project.
class EndCompanionSession extends CompanionSessionAction {
  final CompanionDeparture departure;
  const EndCompanionSession(this.departure);

  DateTime get at => departure.at;
}

/// Start a session for a project that just opened in the DAW.
class StartCompanionSession extends CompanionSessionAction {
  final CompanionProjectRef project;
  const StartCompanionSession(this.project);
}

/// Decides one tick of presence changes.
///
/// [activeSessionKeys] are the keys the running session answers to: its
/// project's, plus — for a session on a version stack — every member's, so
/// closing the version the DAW had open ends the stack's session.
/// [presentBefore]/[presentAfter] are the keys with at least one instance at
/// the start and end of the tick; [departures], when and how each key's
/// last instance left; [hellos], projects that said hello this tick, in order.
///
/// A session ends only on a transition from present to absent — a session
/// for a project no plugin was ever present in is never ended — and only
/// once *every* key it answers to is absent. A session starts only when none
/// is running: it never switches away from one.
CompanionSessionAction? decideCompanionSession({
  required Set<String> activeSessionKeys,
  required Set<String> presentBefore,
  required Set<String> presentAfter,
  required Map<String, CompanionDeparture> departures,
  required List<CompanionProjectRef> hellos,
  required bool endWhenDawCloses,
  required bool startWhenDawOpens,
}) {
  if (activeSessionKeys.isNotEmpty) {
    if (!endWhenDawCloses) return null;
    final wasPresent = activeSessionKeys.any(presentBefore.contains);
    final isPresent = activeSessionKeys.any(presentAfter.contains);
    if (!wasPresent || isPresent) return null;

    CompanionDeparture? last;
    for (final key in activeSessionKeys) {
      final left = departures[key];
      if (left != null && (last == null || left.at.isAfter(last.at))) last = left;
    }
    return last == null ? null : EndCompanionSession(last);
  }

  if (startWhenDawOpens && hellos.isNotEmpty) return StartCompanionSession(hellos.last);
  return null;
}

/// [owner] with the plugin's notes edit applied, or null when there is
/// nothing to change. Notes are never silently lost:
/// - the app's notes still read as the edit began ([CompanionNotesSet.baseText])
///   → the plugin's text replaces them;
/// - they changed in the app meanwhile → both are kept: the app's, a
///   separator line, then the plugin's.
MusicProject? applyCompanionNotesSet(MusicProject owner, CompanionNotesSet message) {
  final current = owner.notes ?? '';
  if (current == message.text) return null;

  final merged = current == message.baseText || current.trim().isEmpty
      ? message.text
      : '$current$companionNotesSeparator${message.text}';
  return merged.isEmpty ? owner.copyWith(clearNotes: true) : owner.copyWith(notes: merged);
}

/// The plugin's captures are copied here, under the preview-songs folder,
/// so the app knows a preview it set itself from one it didn't.
const String companionPreviewFolderName = 'companion';

/// Whether a capture may become [owner]'s preview song.
///
/// Never over a preview the user picked: only when there is none, when the
/// current one is an earlier capture (inside [companionPreviewDir]), or when
/// it is an auto-detected mixdown older than the capture — the case #118 is
/// about, a bounce months behind the project.
bool companionMayReplacePreview(
  MusicProject owner, {
  required String companionPreviewDir,
  required DateTime capturedAt,
  DateTime? currentPreviewModifiedAt,
}) {
  final current = owner.previewSongPath;
  if (current == null || current.isEmpty) return true;
  if (p.isWithin(companionPreviewDir, current)) return true;

  final isAutoDetected = owner.previewSongAutoPath != null && owner.previewSongAutoPath == current;
  return isAutoDetected && currentPreviewModifiedAt != null && currentPreviewModifiedAt.isBefore(capturedAt);
}
