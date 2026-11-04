import Foundation

/// Réglages de l'onglet Color : les dernières couleurs prélevées, la plus récente d'abord, en
/// `#RRGGBB`.
struct ColorPickerSettings: Codable, Equatable, Sendable {
    var recent: [String] = []
}
