import Foundation

/// Bouton de souris qui ouvre le menu radial : maintenu, il l'ouvre sous le curseur.
/// Les valeurs sont les numéros de bouton de `CGEvent` (0 = gauche, 1 = droit, 2 = milieu…) ;
/// `threeFingerClick` n'est pas un bouton : le nom est gardé pour les réglages déjà écrits, mais
/// le geste est désormais trois doigts posés sur le trackpad, sans clic.
enum RadialMouseButton: Int, Codable, CaseIterable, Identifiable, Sendable {
  case middle = 2
  case back = 3
  case forward = 4
  case threeFingerClick = 100

  var id: Int { rawValue }

  var displayName: String {
    switch self {
    case .middle: return "Middle button"
    case .back: return "Back button"
    case .forward: return "Forward button"
    case .threeFingerClick: return "Three fingers (trackpad)"
    }
  }
}

/// Un élément du menu radial : une appli (lancée) ou un raccourci de Raccourcis.app (exécuté).
struct RadialMenuItem: Codable, Equatable, Identifiable, Sendable {
  enum Kind: String, Codable, Sendable {
    case app
    case shortcut
  }

  var id: String = UUID().uuidString
  var kind: Kind
  /// Nom affiché ; pour un raccourci, c'est aussi ce qu'on passe à `shortcuts run`.
  var name: String
  /// Appli seulement : identifiant du bundle d'abord, chemin en repli (appli déplacée).
  var bundleID: String = ""
  var path: String = ""

  init(
    id: String = UUID().uuidString, kind: Kind, name: String, bundleID: String = "",
    path: String = ""
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.bundleID = bundleID
    self.path = path
  }

  init?(appURL: URL) {
    guard let pinned = DockPinnedApp(appURL: appURL) else { return nil }
    self.init(
      kind: .app, name: appURL.deletingPathExtension().lastPathComponent, bundleID: pinned.bundleID,
      path: pinned.path)
  }

  static func shortcut(named name: String) -> RadialMenuItem {
    RadialMenuItem(kind: .shortcut, name: name)
  }

  var pinnedApp: DockPinnedApp { DockPinnedApp(bundleID: bundleID, path: path) }
}

struct RadialMenuSettings: Codable, Equatable, Sendable {
  /// Au-delà, les secteurs deviennent trop étroits pour être visés.
  static let maxItems = 12

  var enabled: Bool = false
  var button: RadialMouseButton = .middle
  var items: [RadialMenuItem] = []
}
