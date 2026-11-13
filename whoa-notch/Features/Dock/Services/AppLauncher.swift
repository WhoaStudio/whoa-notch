import AppKit
import os

/// Lance d'un coup toutes les applis de la liste (les épingles du dock) : par exemple après un
/// redémarrage. Ignore celles qui tournent déjà ou dont le lancement est en cours, et les
/// applis introuvables — jamais d'erreur fatale.
@MainActor
final class AppLauncher {

  /// Ce que `launchAll` fait d'une appli, séparé de l'exécution pour pouvoir être testé.
  enum Decision: Equatable {
    case launch(URL)
    case skipRunning
    case skipPending
    case skipMissing
  }

  private let isRunning: (String) -> Bool
  private let resolveURL: (DockPinnedApp) -> URL?
  private let open: (URL, @escaping @MainActor (Error?) -> Void) -> Void
  private var pending: Set<String> = []

  init(
    isRunning: @escaping (String) -> Bool = AppLauncher.isRunning,
    resolveURL: @escaping (DockPinnedApp) -> URL? = AppLauncher.resolveURL,
    open: @escaping (URL, @escaping @MainActor (Error?) -> Void) -> Void = AppLauncher.open
  ) {
    self.isRunning = isRunning
    self.resolveURL = resolveURL
    self.open = open
  }

  func decision(for app: DockPinnedApp) -> Decision {
    if isRunning(app.bundleID) { return .skipRunning }
    if pending.contains(app.bundleID) { return .skipPending }
    guard let url = resolveURL(app) else { return .skipMissing }
    return .launch(url)
  }

  func launchAll(_ apps: [DockPinnedApp]) {
    for app in apps {
      switch decision(for: app) {
      case .launch(let url):
        pending.insert(app.bundleID)
        open(url) { [weak self] error in
          self?.pending.remove(app.bundleID)
          if let error {
            Log.dock.error("Lancement impossible : \(error.localizedDescription, privacy: .public)")
          }
        }
      case .skipMissing:
        Log.dock.info("Appli introuvable, ignorée : \(app.bundleID, privacy: .public)")
      case .skipRunning, .skipPending:
        break
      }
    }
  }

  nonisolated static func isRunning(bundleID: String) -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
      !$0.isTerminated
    }
  }

  /// Identifiant d'abord (l'appli a pu être déplacée), chemin enregistré sinon.
  nonisolated static func resolveURL(_ app: DockPinnedApp) -> URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
      return url
    }
    return FileManager.default.fileExists(atPath: app.path) ? URL(fileURLWithPath: app.path) : nil
  }

  nonisolated static func open(_ url: URL, completion: @escaping @MainActor (Error?) -> Void) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      Task { @MainActor in completion(error) }
    }
  }
}
