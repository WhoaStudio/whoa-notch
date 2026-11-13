import Foundation

/// Réglages de l'onglet Color : les dernières couleurs prélevées (la plus récente d'abord) et les
/// couleurs gardées, en `#RRGGBB`, puis l'écriture choisie pour la copie.
struct ColorPickerSettings: Codable, Equatable, Sendable {
  var recent: [String] = []
  var saved: [String] = []
  var format: ColorFormat = .hex
}
