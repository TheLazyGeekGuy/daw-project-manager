import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/music_project.dart';
import '../../models/profile.dart';
import '../../models/todo_item.dart';

/// The app's side of the DPM Companion plugin's protocol — the pure part:
/// what goes into `index.json`, how the plugin's messages are read, and what
/// they do to a project. File I/O lives in `companion_bridge_service.dart`.
///
/// The contract is `docs/PROTOCOL.md` in bandpassrecords/dpm-companion; this
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
  final String url;

  const CompanionRelease(this.version, this.url);
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
  return CompanionRelease(version, url);
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

  const CompanionMessage(this.id, this.createdAt, this.project, {this.runId, this.hostName = ''});
}

/// A plugin instance is running inside a project.
class CompanionHello extends CompanionMessage {
  const CompanionHello(super.id, super.createdAt, super.project, {super.runId, super.hostName});
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

  final host = decoded['host'];
  final hostName = host is Map<String, dynamic> && host['name'] is String ? host['name'] as String : '';

  switch (type) {
    case 'session.hello':
      return CompanionHello(id, createdAt, project, runId: runId, hostName: hostName);

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

  const CompanionInstance(this.runId, this.project, this.lastSeen, {this.hostName = ''});

  CompanionInstance seenAt(DateTime time) => CompanionInstance(runId, project, time, hostName: hostName);
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
  return CompanionInstance(runId, project, lastSeen, hostName: hostName);
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
