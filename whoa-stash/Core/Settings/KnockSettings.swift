import Foundation

/// Ce que déclenche un coup sur le châssis. Les cas qui envoient une frappe synthétique
/// demandent la permission Accessibilité (`requiresAccessibility`).
enum KnockAction: String, Codable, CaseIterable, Identifiable, Sendable {
  case none
  case displayOff
  case lockScreen
  case startScreenSaver
  case missionControl
  case playPause
  case nextTrack

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none: return "None"
    case .displayOff: return "Turn display off"
    case .lockScreen: return "Lock screen"
    case .startScreenSaver: return "Start screen saver"
    case .missionControl: return "Mission Control"
    case .playPause: return "Play / Pause"
    case .nextTrack: return "Next track"
    }
  }

  /// Vrai quand l'action passe par une frappe envoyée au système (⌃⌘Q pour verrouiller).
  var requiresAccessibility: Bool { self == .lockScreen }
}

/// Réglages de la détection de coups : une action par motif (simple ou double coup).
struct KnockSettings: Codable, Equatable, Sendable {
  var enabled: Bool = true
  var single: KnockAction = .displayOff
  var double: KnockAction = .lockScreen
  /// 0...1 ; plus haut = coups plus légers détectés (voir `KnockClassifier.threshold`).
  var sensitivity: Double = 0.7

  func action(taps: Int) -> KnockAction {
    taps == 1 ? single : double
  }

  /// Sans action de double coup, le coup simple part tout de suite au lieu d'attendre un second.
  var hasDoubleAction: Bool { double != .none }

  var requiresAccessibility: Bool {
    enabled && (single.requiresAccessibility || double.requiresAccessibility)
  }
}
