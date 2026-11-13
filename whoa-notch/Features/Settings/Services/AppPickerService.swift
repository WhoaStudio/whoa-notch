import AppKit
import UniformTypeIdentifiers

/// Sélection d'une application via `NSOpenPanel` — isole cet accès système hors des vues.
final class AppPickerService {

  static let shared = AppPickerService()

  /// Ouvre un panneau de sélection d'application dans `/Applications`.
  /// Retourne le chemin choisi, ou `nil` si l'utilisateur annule.
  func chooseApplication() -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.path
  }
}
