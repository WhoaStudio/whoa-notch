import AppKit

/// Source des applis lancées. Derrière un protocole pour vérifier le dock sans dépendre de
/// ce qui tourne sur la machine (`--dock=sample`).
@MainActor
protocol RunningAppsProviding: AnyObject {
  var onChange: (([DockRunningApp]) -> Void)? { get set }
  var current: [DockRunningApp] { get }
  func activate()
}

/// Suit les lancements et fins d'applis par les notifications de `NSWorkspace`, sans sondage.
@MainActor
final class WorkspaceRunningAppsProvider: RunningAppsProviding {

  var onChange: (([DockRunningApp]) -> Void)?
  private var observers: [NSObjectProtocol] = []

  var current: [DockRunningApp] {
    NSWorkspace.shared.runningApplications.compactMap(Self.makeApp)
  }

  func activate() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self else { return }
            self.onChange?(self.current)
          }
        })
    }
    onChange?(current)
  }

  /// Seules les applis `.regular` ont une icône dans le Dock ; le dock lui-même n'en est pas une.
  private static func makeApp(_ app: NSRunningApplication) -> DockRunningApp? {
    guard app.activationPolicy == .regular, !app.isTerminated,
      let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
      let url = app.bundleURL
    else { return nil }
    return DockRunningApp(
      bundleID: bundleID, path: url.path,
      name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
  }
}

/// Applis fixes, pour `--dock=sample`.
@MainActor
final class MockRunningAppsProvider: RunningAppsProviding {

  var onChange: (([DockRunningApp]) -> Void)?
  let current: [DockRunningApp]

  init(apps: [DockRunningApp]) { current = apps }

  func activate() { onChange?(current) }

  static func fromLaunchArguments() -> MockRunningAppsProvider? {
    guard CommandLine.arguments.contains("--dock=sample") else { return nil }
    let apps = [
      ("com.apple.Safari", "/Applications/Safari.app"),
      ("com.apple.Terminal", "/System/Applications/Utilities/Terminal.app"),
      ("com.apple.finder", "/System/Library/CoreServices/Finder.app"),
    ]
    return MockRunningAppsProvider(
      apps: apps.map {
        DockRunningApp(bundleID: $0.0, path: $0.1, name: DockModel.displayName(path: $0.1))
      })
  }
}
