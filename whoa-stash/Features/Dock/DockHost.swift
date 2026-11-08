import AppKit

/// Les docks de l'app, selon « Screens » : un seul dock qui suit le curseur entre les écrans permis
/// (`one`, `attached`), ou un dock fixe par écran attaché (`all`). Chaque réglage est retenu et rejoué
/// sur les docks créés plus tard, quand un écran apparaît.
@MainActor
final class DockHost {

  private static let sharedKey = "shared"

  private let makeController: () -> DockController
  private var controllers: [String: DockController] = [:]
  /// Dernière valeur de chaque réglage, rejouée sur chaque dock créé.
  private var replays: [String: (DockController) -> Void] = [:]
  private var screenMode: DockScreenMode = .attached
  private var detached: [String] = []
  private var isActive = false
  private var screenObserver: NSObjectProtocol?

  init(makeController: @escaping () -> DockController) {
    self.makeController = makeController
  }

  func activate() {
    isActive = true
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.reconcile() }
    }
    reconcile()
  }

  // MARK: - Réglages retenus et rejoués

  private func record(_ key: String, _ apply: @escaping (DockController) -> Void) {
    replays[key] = apply
    controllers.values.forEach(apply)
  }

  func apply(magnification: Bool) {
    record("magnification") { $0.apply(magnification: magnification) }
  }
  func apply(profiles: [DockProfile], activeID: String?) {
    record("profiles") { $0.apply(profiles: profiles, activeID: activeID) }
  }
  func apply(widgets: [DockWidgetPlacement]) { record("widgets") { $0.apply(widgets: widgets) } }
  func apply(theme: DockTheme) { record("theme") { $0.apply(theme: theme) } }
  func apply(autoHide: Bool) { record("autoHide") { $0.apply(autoHide: autoHide) } }
  func apply(enabled: Bool) { record("enabled") { $0.apply(enabled: enabled) } }
  func apply(style: DockStyle) { record("style") { $0.apply(style: style) } }
  func apply(state: DockState) { record("state") { $0.apply(state: state) } }

  // MARK: - Écrans

  func apply(screenMode mode: DockScreenMode, detachedDisplays: [String]) {
    screenMode = mode
    detached = detachedDisplays
    reconcile()
  }

  /// Aligne les docks sur les écrans : crée ceux qui manquent, retire ceux dont l'écran a disparu.
  private func reconcile() {
    guard isActive else { return }
    let wanted = wantedDocks()

    for key in Array(controllers.keys) where wanted[key] == nil {
      controllers[key]?.shutdown()
      controllers[key] = nil
    }
    for (key, allowed) in wanted {
      if let existing = controllers[key] {
        existing.apply(allowedScreens: allowed)
        continue
      }
      let controller = makeController()
      controllers[key] = controller
      controller.apply(allowedScreens: allowed)
      replays.values.forEach { $0(controller) }
      controller.activate()
    }
  }

  /// Pour chaque dock voulu, la fonction qui donne ses écrans permis.
  private func wantedDocks() -> [String: () -> [NSScreen]] {
    switch screenMode {
    case .one, .attached:
      let mode = screenMode
      let detached = detached
      return [
        Self.sharedKey: {
          DockScreenPolicy.allowed(NSScreen.screens, mode: mode, detached: detached)
        }
      ]
    case .all:
      var docks: [String: () -> [NSScreen]] = [:]
      for screen in DockScreenPolicy.allowed(NSScreen.screens, mode: .attached, detached: detached)
      {
        guard let uuid = screen.displayUUID else { continue }
        docks[uuid] = { NSScreen.screens.filter { $0.displayUUID == uuid } }
      }
      return docks
    }
  }
}
