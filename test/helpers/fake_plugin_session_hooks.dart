import 'package:daw_project_manager/services/plugin_bridge/plugin_bridge_service.dart';
import 'package:daw_project_manager/services/plugin_bridge/plugin_protocol.dart';

/// Records what the plugin bridge asks of the work sessions. Shared by the
/// bridge's own tests and the integration tests with the real plugin.
class FakeHooks implements DpmPluginSessionHooks {
  DpmPluginProjectRef? active;
  final departures = <DpmPluginDeparture>[];
  // In UTC to compare with the UTC test clock (Dart: equal moments in two
  // zones are not ==). The app itself is handed local times.
  List<DateTime> get ended => [for (final d in departures) d.at.toUtc()];
  final started = <DpmPluginProjectRef>[];

  @override
  bool endWhenDawCloses = true;
  @override
  bool startWhenDawOpens = false;

  @override
  DpmPluginProjectRef? activeSession() => active;

  @override
  Future<void> endSession(DpmPluginDeparture departure) async {
    departures.add(departure);
    active = null;
  }

  @override
  Future<void> startSession(DpmPluginProjectRef project) async {
    started.add(project);
    active = project;
  }
}
