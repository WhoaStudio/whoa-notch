import Foundation

/// Réglages de l'onglet « AI » : ce que l'app surveille pour afficher une notification dans l'encoche.
struct AISettings: Codable, Equatable, Sendable {
  /// Surveille le bouton Stop de Claude Desktop par Accessibilité. Désactivé par défaut.
  var desktopWatcherEnabled: Bool = false
}
