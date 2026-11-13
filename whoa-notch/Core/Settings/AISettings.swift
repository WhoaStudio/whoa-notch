import Foundation

/// Réglages de l'onglet « AI » : ce que l'app surveille pour afficher une notification dans l'encoche.
struct AISettings: Codable, Equatable, Sendable {
  /// Surveille le bouton Stop de Claude Desktop par Accessibilité. Désactivé par défaut.
  var desktopWatcherEnabled: Bool = false
  /// Après la fin d'un tour de Claude Code, l'encoche propose un champ de réponse pendant quelques
  /// secondes : le texte tapé fait repartir Claude. Désactivé par défaut : le hook `Stop` est retenu
  /// le temps de la carte.
  var stopReplyEnabled: Bool = false
}
