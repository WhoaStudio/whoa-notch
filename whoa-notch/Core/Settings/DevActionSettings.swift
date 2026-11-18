import Foundation

/// Une action de l'onglet Actions : une commande à lancer dans un dossier (`pnpm dev`, …).
struct DevAction: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var name: String
  var command: String
  /// Dossier de travail ; `nil` : le dossier personnel.
  var directory: String?
}

/// Réglages des onglets Actions et Servers : la liste des actions enregistrées.
struct DevActionSettings: Codable, Equatable, Sendable {
  var actions: [DevAction] = []
}
