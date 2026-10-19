import CoreMIDI
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAudioConvertChannel(engineBridge.pluginRegistry)
    // MIDI keyboards for the piano roll — the same bridge as on macOS.
    MidiInputBridge.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "MidiInputBridge")!.messenger()
    )
  }

  /// Backs `AudioAnalysisService.convertForSharing` on iOS. Mirrors the
  /// identically-named channel registered in MainActivity.kt on Android —
  /// same channel name, same method, same arguments, so the Dart side has a
  /// single code path for both.
  private func registerAudioConvertChannel(_ registry: FlutterPluginRegistry) {
    let messenger = registry.registrar(forPlugin: "AudioShareConverter")!.messenger()
    let channel = FlutterMethodChannel(
      name: "com.bandpassrecords.dpm/audio_convert",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "toM4a" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let input = args["input"] as? String,
        let output = args["output"] as? String
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "input and output are required",
            details: nil
          )
        )
        return
      }

      AudioShareConverter.convertToM4a(inputPath: input, outputPath: output) { error in
        // exportAsynchronously' completion runs off the main thread; channel
        // replies have to be delivered on it.
        DispatchQueue.main.async {
          if let error = error {
            result(
              FlutterError(
                code: "convert_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(output)
          }
        }
      }
    }
  }
}

/// Native half of MIDI input on Apple platforms, through CoreMIDI, answering
/// the channels `ChannelMidiInput` (lib/services/midi/input/channel_midi_input.dart)
/// talks on: `devices` lists the sources, `open` connects some (replacing
/// those connected before) and answers the ids that wouldn't connect,
/// `close` disconnects them all. What they play goes out on the event
/// channel as `{id, bytes}` — raw MIDI, parsed on the Dart side.
///
/// CoreMIDI is shared: a DAW listening to the same keyboard keeps it. One
/// client and port serve the app's lifetime; only connections come and go.
final class MidiInputBridge: NSObject, FlutterStreamHandler {
  static let shared = MidiInputBridge()

  private var client = MIDIClientRef()
  private var port = MIDIPortRef()
  private var sink: FlutterEventSink?

  /// The sources connected. A connection's refCon is its index here + 1,
  /// so the read block knows which one played (it runs on CoreMIDI's own
  /// thread; the list is only read back on the main one).
  private var sources: [(id: String, endpoint: MIDIEndpointRef)] = []

  static func register(with messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(
      name: "com.bandpassrecords.dpm/midi_input",
      binaryMessenger: messenger
    )
    methods.setMethodCallHandler { call, result in
      shared.handle(call, result: result)
    }
    FlutterEventChannel(
      name: "com.bandpassrecords.dpm/midi_input/events",
      binaryMessenger: messenger
    ).setStreamHandler(shared)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "devices":
      result(devices())
    case "open":
      let ids = (call.arguments as? [String: Any])?["ids"] as? [String] ?? []
      result(open(ids))
    case "close":
      close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func devices() -> [[String: String]] {
    return currentSources().map { ["id": $0.id, "name": displayName(of: $0.endpoint)] }
  }

  private func currentSources() -> [(id: String, endpoint: MIDIEndpointRef)] {
    var found: [(id: String, endpoint: MIDIEndpointRef)] = []
    for i in 0..<MIDIGetNumberOfSources() {
      let source = MIDIGetSource(i)
      if source != 0 { found.append((id: String(uniqueID(of: source)), endpoint: source)) }
    }
    return found
  }

  private func open(_ ids: [String]) -> [String] {
    close()
    guard ensurePort() else { return ids }
    let available = currentSources()
    var failed: [String] = []
    for id in ids {
      guard let source = available.first(where: { $0.id == id }) else {
        failed.append(id)
        continue
      }
      let refCon = UnsafeMutableRawPointer(bitPattern: sources.count + 1)
      if MIDIPortConnectSource(port, source.endpoint, refCon) == noErr {
        sources.append(source)
      } else {
        failed.append(id)
      }
    }
    return failed
  }

  private func close() {
    for source in sources {
      MIDIPortDisconnectSource(port, source.endpoint)
    }
    sources.removeAll()
  }

  private func ensurePort() -> Bool {
    if port != 0 { return true }
    if client == 0,
      MIDIClientCreateWithBlock("DAW Project Manager" as CFString, &client, nil) != noErr
    {
      client = 0
      return false
    }
    let status = MIDIInputPortCreateWithBlock(client, "MIDI in" as CFString, &port) {
      [weak self] list, refCon in
      self?.received(list, refCon: refCon)
    }
    if status != noErr {
      port = 0
      return false
    }
    return true
  }

  /// On CoreMIDI's thread: every packet's bytes, in order, handed to the
  /// main thread. Lengths are read straight from memory rather than by
  /// copying a whole `MIDIPacket` (256 bytes of data), which would read
  /// past a short packet at the end of the list.
  private func received(_ list: UnsafePointer<MIDIPacketList>, refCon: UnsafeMutableRawPointer?) {
    let slot = Int(bitPattern: refCon) - 1
    let raw = UnsafeRawPointer(list)
    let count = Int(raw.loadUnaligned(as: UInt32.self))
    let lengthOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.length) ?? 8
    let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data) ?? 10
    var packet = raw
      .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet) ?? 4)
      .assumingMemoryBound(to: MIDIPacket.self)
    var bytes = Data()
    for _ in 0..<count {
      let start = UnsafeRawPointer(packet)
      let length = Int(start.loadUnaligned(fromByteOffset: lengthOffset, as: UInt16.self))
      bytes.append(start.advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self), count: length)
      packet = UnsafePointer(MIDIPacketNext(packet))
    }
    guard !bytes.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let sink = self.sink, slot >= 0, slot < self.sources.count else {
        return
      }
      sink(["id": self.sources[slot].id, "bytes": FlutterStandardTypedData(bytes: bytes)])
    }
  }

  private func uniqueID(of object: MIDIObjectRef) -> Int32 {
    var id: Int32 = 0
    MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &id)
    return id
  }

  private func displayName(of object: MIDIObjectRef) -> String {
    var name: Unmanaged<CFString>?
    if MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr,
      let value = name?.takeRetainedValue()
    {
      return value as String
    }
    return "MIDI"
  }
}
