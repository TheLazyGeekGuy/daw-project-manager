import 'package:daw_project_manager/models/plugin_capture.dart';
import 'package:daw_project_manager/services/plugin_capture_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 21, 18);
  PluginCapture capture(DateTime at) =>
      PluginCapture(path: '/data/preview_songs/plugin/p1/take.flac', capturedAt: at, durationSeconds: 60);
  CaptureEntry entry(DateTime at, {String hash = 'h1'}) => CaptureEntry(
        fileId: 'drive-1',
        hash: hash,
        name: 'take.flac',
        capturedAt: at,
        durationSeconds: 60,
      );

  group('CaptureEntry', () {
    test('round-trips through the JSON a backup is', () {
      final back = CaptureEntry.tryFromJson(entry(t0).toJson())!;
      expect(back.fileId, 'drive-1');
      expect(back.hash, 'h1');
      expect(back.name, 'take.flac');
      expect(back.capturedAt.isAtSameMomentAs(t0), isTrue);
      expect(back.durationSeconds, 60);
    });

    test('a malformed entry costs that capture, never the rest', () {
      final all = captureEntriesFrom({
        'solo/p1': entry(t0).toJson(),
        'solo/p2': {'fileId': 'x'},
        'solo/p3': 'nonsense',
      });
      expect(all.keys, ['solo/p1']);
      expect(captureEntriesFrom(null), isEmpty);
    });

    test('is keyed by profile and project, never the id alone', () {
      expect(captureEntryKey('solo', 'p1'), isNot(captureEntryKey('duo', 'p1')));
    });
  });

  group('decideCaptureUpload', () {
    test('nothing to send without a capture', () {
      expect(decideCaptureUpload(local: null, localHash: 'h1', onDrive: entry(t0)), isA<NoCaptureUpload>());
    });

    test('a capture Drive does not have yet goes up', () {
      final d = decideCaptureUpload(local: capture(t0), localHash: 'h1', onDrive: null);
      expect(d, isA<UploadCapture>());
      expect((d as UploadCapture).replacing, isNull);
    });

    test('the very file Drive has is kept, not sent again', () {
      final d = decideCaptureUpload(local: capture(t0), localHash: 'h1', onDrive: entry(t0));
      expect((d as KeepCaptureEntry).entry.fileId, 'drive-1');
    });

    test('a newer take goes up over the entry it replaces', () {
      final later = t0.add(const Duration(minutes: 5));
      final d = decideCaptureUpload(local: capture(later), localHash: 'h2', onDrive: entry(t0));
      expect((d as UploadCapture).replacing?.fileId, 'drive-1');
    });

    test("a capture whose file isn't here keeps Drive's entry for that take", () {
      // A phone, or a computer that hasn't downloaded it yet: its upload
      // must not take the capture away from every other device.
      final d = decideCaptureUpload(local: capture(t0), localHash: null, onDrive: entry(t0));
      expect(d, isA<KeepCaptureEntry>());
    });

    test("but not an entry for some other take", () {
      final d = decideCaptureUpload(local: capture(t0), localHash: null, onDrive: entry(t0.add(const Duration(hours: 1))));
      expect(d, isA<NoCaptureUpload>());
    });
  });

  group('captureNeedsDownload', () {
    test('when this device has no capture', () {
      expect(captureNeedsDownload(local: null, localFileExists: false, remote: entry(t0)), isTrue);
    });

    test('when Drive has a newer take', () {
      expect(
        captureNeedsDownload(local: capture(t0), localFileExists: true, remote: entry(t0.add(const Duration(minutes: 1)))),
        isTrue,
      );
    });

    test('when this device has the same take but not its file', () {
      expect(captureNeedsDownload(local: capture(t0), localFileExists: false, remote: entry(t0)), isTrue);
    });

    test('never over a newer take here, nor the same one already here', () {
      expect(
        captureNeedsDownload(local: capture(t0), localFileExists: true, remote: entry(t0.subtract(const Duration(minutes: 1)))),
        isFalse,
      );
      expect(captureNeedsDownload(local: capture(t0), localFileExists: true, remote: entry(t0)), isFalse);
    });
  });
}
