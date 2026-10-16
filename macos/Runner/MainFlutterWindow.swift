import Cocoa
import FlutterMacOS
import ServiceManagement

/// Native half of launch-at-login on macOS, answering the `launch_at_startup`
/// channel the Dart macOS backend (lib/services/auto_start/platform_backends.dart)
/// talks on:
///
/// - macOS 13+: `SMAppService.mainApp`, the supported API — the app shows up
///   in System Settings → General → Login Items, where the user can revoke
///   it (which is why the Dart side re-reads this state on every launch).
/// - macOS 10.15–12: a `~/Library/LaunchAgents/<bundle-id>.plist` with
///   `RunAtLoad`, since `SMAppService` doesn't exist there and the older
///   `SMLoginItemSetEnabled` needs a separate bundled helper app.
///
/// The "start minimized" option forces the LaunchAgent mechanism on *every*
/// macOS version: the flag has to reach the app as a launch argument, and
/// `SMAppService.mainApp` gives no way to supply one — it just launches the
/// bundle. The plist can, via `open --args`. Only one mechanism is ever left
/// registered; switching between them tears the other one down.
enum LaunchAtStartupHandler {
  private static let channelName = "launch_at_startup"
  private static let minimizedDefaultsKey = "launchAtStartupMinimized"
  /// Must stay in sync with kStartMinimizedFlag in
  /// lib/services/auto_start/auto_start_backend.dart.
  static let minimizedFlag = "--minimized"

  /// Whether this process is a login launch that should stay hidden.
  static let launchedMinimized = CommandLine.arguments.contains(minimizedFlag)

  static func register(with registrar: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupStatus":
        result(status())
      case "launchAtStartupSetEnabled":
        let args = call.arguments as? [String: Any]
        let value = args?["setEnabledValue"] as? Bool ?? false
        result(setEnabled(value))
      case "launchAtStartupSetLaunchMinimized":
        // Sent by AutoStartService.setup() before any enable() or status().
        // Persisted so a later status()/setEnabled() in a fresh process
        // still knows which mechanism this install is using.
        let args = call.arguments as? [String: Any]
        let value = args?["minimized"] as? Bool ?? false
        UserDefaults.standard.set(value, forKey: minimizedDefaultsKey)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var wantsMinimized: Bool {
    UserDefaults.standard.bool(forKey: minimizedDefaultsKey)
  }

  private static var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "io.bandpassrecords.dawProjectManager"
  }

  private static var legacyAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(bundleIdentifier).plist")
  }

  /// The agent's `ProgramArguments` for this bundle and flag.
  private static var expectedAgentArguments: [String] {
    // `open -a <bundle>` rather than the raw executable: launchd starts
    // agents outside an app context, and launching the binary directly
    // gives a process with no Dock icon and no proper activation.
    // `--args` forwards everything after it to the app itself.
    var arguments = ["/usr/bin/open", "-a", Bundle.main.bundlePath]
    if wantsMinimized {
      arguments.append(contentsOf: ["--args", minimizedFlag])
    }
    return arguments
  }

  /// The installed agent's `ProgramArguments`: nil without an agent, empty
  /// for one that can't be read.
  private static func installedAgentArguments() -> [String]? {
    guard FileManager.default.fileExists(atPath: legacyAgentURL.path) else { return nil }
    guard let data = try? Data(contentsOf: legacyAgentURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return [] }
    return plist["ProgramArguments"] as? [String] ?? []
  }

  /// "on", "off" or "stale" — an AutoStartStatus name on the Dart side.
  ///
  /// The agent stores the bundle's path, so moving the app leaves it
  /// opening nothing: an agent for this bundle, or for one that no longer
  /// exists, that isn't exactly what setEnabled(true) would write now is
  /// "stale", for the Dart side to rewrite. An agent opening another copy of
  /// the app that still exists is that copy's, and left alone.
  private static func status() -> String {
    if let arguments = installedAgentArguments() {
      if arguments == expectedAgentArguments { return "on" }
      let bundle = arguments.count > 2 ? arguments[2] : ""
      if bundle == Bundle.main.bundlePath || !FileManager.default.fileExists(atPath: bundle) {
        return "stale"
      }
    }
    if #available(macOS 13.0, *) {
      // Anything but .enabled — .requiresApproval is the user switching it
      // off in Login Items — is off, and stays the user's call.
      if SMAppService.mainApp.status == .enabled {
        // A login item can't carry the minimized flag (see above).
        return wantsMinimized ? "stale" : "on"
      }
    }
    return "off"
  }

  private static func setEnabled(_ enabled: Bool) -> Bool {
    guard enabled else {
      // Tear down both, so a mechanism switch can't strand a registration.
      let agentOK = setLegacyAgentEnabled(false)
      let serviceOK = setModernServiceEnabled(false)
      return agentOK && serviceOK
    }

    // SMAppService can't pass a launch argument, so the minimized flag forces
    // the LaunchAgent path even on macOS 13+.
    if wantsMinimized {
      guard setLegacyAgentEnabled(true) else { return false }
      _ = setModernServiceEnabled(false)
      return true
    }

    if #available(macOS 13.0, *) {
      guard setModernServiceEnabled(true) else { return false }
      _ = setLegacyAgentEnabled(false)
      return true
    }
    return setLegacyAgentEnabled(true)
  }

  private static func setModernServiceEnabled(_ enabled: Bool) -> Bool {
    guard #available(macOS 13.0, *) else { return true }
    do {
      if enabled {
        // Re-registering an already-enabled app throws; treat that as success.
        if SMAppService.mainApp.status != .enabled {
          try SMAppService.mainApp.register()
        }
      } else if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      }
      return true
    } catch {
      NSLog("[LaunchAtStartup] SMAppService failed: \(error.localizedDescription)")
      return false
    }
  }

  private static func setLegacyAgentEnabled(_ enabled: Bool) -> Bool {
    let fm = FileManager.default
    let url = legacyAgentURL
    do {
      guard enabled else {
        if fm.fileExists(atPath: url.path) {
          try fm.removeItem(at: url)
        }
        return true
      }
      try fm.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let plist: [String: Any] = [
        "Label": bundleIdentifier,
        "ProgramArguments": expectedAgentArguments,
        "RunAtLoad": true,
      ]
      let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      NSLog("[LaunchAtStartup] LaunchAgent update failed: \(error.localizedDescription)")
      return false
    }
  }
}

class MainFlutterWindow: NSWindow {
  private var isTitleBarDragging = false
  private var dragStartScreenPoint = NSPoint.zero
  private var dragStartFrameOrigin = NSPoint.zero
  private var launchShowHandled = false

  /// The nib shows the window as soon as it loads, before Dart has decided
  /// anything — so on a "start minimized" login launch it is hidden again on
  /// that first ordering (the same thing window_manager's
  /// `hiddenWindowAtLaunch()` does). Dart skips its own show() for that
  /// launch, and the menu bar icon or the Dock brings the window back.
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if !launchShowHandled {
      launchShowHandled = true
      if LaunchAtStartupHandler.launchedMinimized {
        setIsVisible(false)
      }
    }
  }

  override func awakeFromNib() {
    // The macOS embedder doesn't hand the process's arguments to Dart's
    // main(), so a login launch's --minimized never reached it. Only that
    // flag is forwarded: it is the one argument main() reads on macOS (quick
    // actions arrive through the Dock menu, in-process).
    let project = FlutterDartProject()
    if LaunchAtStartupHandler.launchedMinimized {
      project.dartEntrypointArguments = [LaunchAtStartupHandler.minimizedFlag]
    }
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Disable automatic window tabbing (hides "Show Tab Bar" / "Show All Tabs" menu items)
    NSWindow.allowsAutomaticWindowTabbing = false

    // Set dark background immediately so there is no white flash before Flutter paints.
    // Matches the default classicDark theme background (#1E1F22).
    // Flutter will update this to the saved theme colour once it loads.
    self.backgroundColor = NSColor(red: 0.118, green: 0.122, blue: 0.133, alpha: 1.0)

    // Handle title-bar double-click (zoom/restore) and drag natively so they
    // work reliably without conflicting with Flutter's gesture arena.
    setupTitleBarInteractions()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Launch at login is answered natively — see the handler above.
    LaunchAtStartupHandler.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func setupTitleBarInteractions() {
    let titleBarHeight: CGFloat = 28

    // mouseDown in the top 28 pt: double-click → zoom/restore; single click →
    // record start position so a subsequent drag can move the window.
    NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      guard let self = self, event.window === self else { return event }
      let contentHeight = self.contentView?.frame.height ?? 0
      guard event.locationInWindow.y >= contentHeight - titleBarHeight else {
        self.isTitleBarDragging = false
        return event
      }
      if event.clickCount == 2 {
        self.isTitleBarDragging = false
        self.zoom(nil)  // zoom = maximise / restore (NOT full screen)
        return nil      // consume – Flutter never sees this tap
      }
      self.isTitleBarDragging = true
      self.dragStartScreenPoint = NSEvent.mouseLocation
      self.dragStartFrameOrigin = self.frame.origin
      return event      // pass single click through (e.g. back button)
    }

    // mouseDragged: move the window by applying the pointer delta to the frame origin.
    NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
      guard let self = self, event.window === self,
            self.isTitleBarDragging,
            !self.styleMask.contains(.fullScreen) else { return event }
      let current = NSEvent.mouseLocation
      let dx = current.x - self.dragStartScreenPoint.x
      let dy = current.y - self.dragStartScreenPoint.y
      self.setFrameOrigin(NSPoint(
        x: self.dragStartFrameOrigin.x + dx,
        y: self.dragStartFrameOrigin.y + dy
      ))
      return nil  // consume
    }

    // mouseUp: end any in-progress title-bar drag.
    NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
      if event.window === self { self?.isTitleBarDragging = false }
      return event
    }
  }
}
