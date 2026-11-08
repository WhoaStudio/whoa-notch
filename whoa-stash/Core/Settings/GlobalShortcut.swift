import Carbon.HIToolbox
import Foundation

/// Raccourci global, choisi parmi une courte liste de combinaisons. Un enregistreur libre
/// (« appuyez sur une touche ») demanderait une vue dédiée et la gestion des conflits avec les
/// raccourcis système ; une liste fermée de combinaisons peu disputées rend le réglage réel
/// sans cette machinerie, et le type est prêt à en accueillir d'autres.
enum GlobalShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
  case disabled
  case optionCommandN
  case controlCommandN
  case optionCommandB
  case controlOptionSpace

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .disabled: return "Off"
    case .optionCommandN: return "⌥⌘N"
    case .controlCommandN: return "⌃⌘N"
    case .optionCommandB: return "⌥⌘B"
    case .controlOptionSpace: return "⌃⌥Space"
    }
  }

  /// `nil` pour `.disabled` : rien à enregistrer auprès du système.
  var keyCode: UInt32? {
    switch self {
    case .disabled: return nil
    case .optionCommandN, .controlCommandN: return UInt32(kVK_ANSI_N)
    case .optionCommandB: return UInt32(kVK_ANSI_B)
    case .controlOptionSpace: return UInt32(kVK_Space)
    }
  }

  /// Masque de modificateurs au format Carbon (`cmdKey`, `optionKey`…), celui qu'attend
  /// `RegisterEventHotKey` — distinct de `NSEvent.ModifierFlags`.
  var carbonModifiers: UInt32 {
    switch self {
    case .disabled: return 0
    case .optionCommandN, .optionCommandB: return UInt32(optionKey | cmdKey)
    case .controlCommandN: return UInt32(controlKey | cmdKey)
    case .controlOptionSpace: return UInt32(controlKey | optionKey)
    }
  }
}
