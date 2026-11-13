import Foundation

/// Une appli en cours d'exécution, telle que la voit le suivi de `NSWorkspace`.
struct DockRunningApp: Equatable, Sendable {
  var bundleID: String
  var path: String
  var name: String
}

/// Une icône du dock : épinglée, en cours d'exécution, ou les deux.
struct DockItem: Equatable, Identifiable, Sendable {
  var bundleID: String
  var path: String
  var name: String
  var isRunning: Bool
  var isWebApp: Bool
  var isPinned = false

  var id: String { bundleID }
}

struct DockState: Equatable, Sendable {
  /// Les applis du profil actif, dans l'ordre choisi.
  var items: [DockItem] = []
  /// Les applis ouvertes qui ne sont pas dans le profil actif : le dock les range dans un dossier.
  var overflow: [DockItem] = []
}

/// Source unique de l'état du dock : épingles + applis lancées → liste d'icônes. Pousse chaque
/// changement par `onStateChanged`, comme les autres modèles de vue ; il ne connaît ni la fenêtre
/// ni `NSWorkspace`.
@MainActor
final class DockModel {

  private(set) var state = DockState()
  var onStateChanged: ((DockState) -> Void)?

  private var pinned: [DockPinnedApp] = []
  private var running: [DockRunningApp] = []

  func setPinned(_ pinned: [DockPinnedApp]) {
    guard pinned != self.pinned else { return }
    self.pinned = pinned
    rebuild()
  }

  func setRunning(_ running: [DockRunningApp]) {
    guard running != self.running else { return }
    self.running = running
    rebuild()
  }

  private func rebuild() {
    let runningIDs = Set(running.map(\.bundleID))
    let items = pinned.map { app in
      DockItem(
        bundleID: app.bundleID, path: app.path, name: Self.displayName(path: app.path),
        isRunning: runningIDs.contains(app.bundleID),
        isWebApp: Self.isWebApp(bundleID: app.bundleID, path: app.path), isPinned: true)
    }
    let pinnedIDs = Set(pinned.map(\.bundleID))
    // Le Finder tourne toujours : le ranger dans le dossier n'apprendrait rien. Il n'apparaît que si on l'ajoute.
    let overflow = running.filter {
      !pinnedIDs.contains($0.bundleID) && $0.bundleID != Self.finderBundleID
    }.map { app in
      DockItem(
        bundleID: app.bundleID, path: app.path, name: app.name, isRunning: true,
        isWebApp: Self.isWebApp(bundleID: app.bundleID, path: app.path))
    }
    let next = DockState(items: items, overflow: overflow)
    guard next != state else { return }
    state = next
    onStateChanged?(next)
  }

  nonisolated static let finderBundleID = "com.apple.finder"

  nonisolated static func displayName(path: String) -> String {
    ((path as NSString).lastPathComponent as NSString).deletingPathExtension
  }

  /// Web apps installées par Safari, Chrome ou Edge : le dock leur colle un globe.
  nonisolated static func isWebApp(bundleID: String, path: String) -> Bool {
    bundleID.hasPrefix("com.apple.Safari.WebApp")
      || bundleID.hasPrefix("com.google.Chrome.app.")
      || bundleID.hasPrefix("com.microsoft.edgemac.app.")
      || path.contains("/Chrome Apps.localized/")
  }
}
