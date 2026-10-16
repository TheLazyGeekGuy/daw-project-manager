import 'auto_start_backend.dart';

/// Web build: no login items, and the real backends need `dart:ffi`.
AutoStartBackend createPlatformAutoStartBackend() => _NoBackend();

class _NoBackend implements AutoStartBackend {
  @override
  Future<void> setup({required bool minimized}) async {}
  @override
  Future<AutoStartStatus> status() async => AutoStartStatus.off;
  @override
  Future<bool> enable() async => false;
  @override
  Future<bool> disable() async => false;
}
