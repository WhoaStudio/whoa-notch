import Foundation

/// Bord de l'écran où un widget est ancré. Partagé par le slider de volume (`edgeSlider`),
/// l'overlay de luminosité (`brightness.widgetPosition`) et l'extension du Dock
/// (`dock.side`) — d'où sa place dans `Core` plutôt que dans la feature Settings.
enum EdgePosition: String, Codable, CaseIterable, Identifiable, Sendable {
  case left
  case right

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .left: return "Left Edge"
    case .right: return "Right Edge"
    }
  }
}
