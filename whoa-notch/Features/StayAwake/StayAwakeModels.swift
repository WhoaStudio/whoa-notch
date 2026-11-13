import Foundation

/// Durée choisie pour garder le Mac éveillé. `forever` n'a pas d'échéance : seul « Turn Off » y
/// met fin.
enum StayAwakeDuration: CaseIterable, Equatable {
  case minutes15
  case hour1
  case hours2
  case forever

  /// Durée en secondes, `nil` pour `forever`.
  var seconds: TimeInterval? {
    switch self {
    case .minutes15: 15 * 60
    case .hour1: 60 * 60
    case .hours2: 2 * 60 * 60
    case .forever: nil
    }
  }

  /// Intitulé de la pastille.
  var label: String {
    switch self {
    case .minutes15: "15m"
    case .hour1: "1h"
    case .hours2: "2h"
    case .forever: "∞"
    }
  }
}

/// Ce que le Mac garde éveillé : l'écran compris, ou le système seul (l'écran peut s'éteindre).
enum StayAwakeScope: CaseIterable, Equatable {
  case macAndDisplay
  case macOnly

  var title: String {
    switch self {
    case .macAndDisplay: "Mac and display"
    case .macOnly: "Mac only"
    }
  }

  var symbolName: String {
    switch self {
    case .macAndDisplay: "display"
    case .macOnly: "laptopcomputer"
    }
  }
}

/// Ce que l'interface demande au modèle de vue.
enum StayAwakeAction: Equatable {
  case start(StayAwakeDuration)
  case setScope(StayAwakeScope)
  /// Ajoute (ou retire, si négatif) du temps à l'échéance en cours. Sans effet sans échéance.
  case adjust(TimeInterval)
  case turnOff
}

/// État affiché par l'onglet. `duration` vaut `nil` tant que rien ne tient le Mac éveillé ;
/// `remaining` vaut `nil` sans échéance (inactif, ou `forever`).
struct StayAwakeState: Equatable {
  var scope: StayAwakeScope = .macAndDisplay
  var duration: StayAwakeDuration?
  var remaining: TimeInterval?
  /// Durée de référence de l'anneau : ce que `remaining` vide. `nil` sans échéance.
  var total: TimeInterval?
  /// Vrai quand le temps a été ajusté à la main : plus aucune pastille de durée n'est la bonne.
  var isAdjusted = false

  /// Part restante de l'anneau, entre 0 et 1 ; pleine sans échéance.
  var fraction: Double {
    guard let remaining, let total, total > 0 else { return isActive ? 1 : 0 }
    return min(1, max(0, remaining / total))
  }

  /// Compte à rebours en grands chiffres : « 47:12 », « 1:59:03 », « ∞ ».
  var countdownText: String {
    guard isActive else { return "0:00" }
    guard let remaining else { return "∞" }
    let seconds = max(0, Int(remaining.rounded(.up)))
    let (h, m, s) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
    return h > 0
      ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }

  var isActive: Bool { duration != nil }

  /// Ligne d'état de l'onglet : « 2 hr left », « 45 min left », « 30 sec left ».
  var statusText: String {
    guard isActive else { return "Off" }
    guard let remaining else { return "Until turned off" }
    return Self.remainingText(remaining)
  }

  /// Les minutes sont arrondies au-dessus : « 2 hr left » tient toute la première minute d'un
  /// réglage de 2 h, puis « 1 hr 59 min left ».
  static func remainingText(_ remaining: TimeInterval) -> String {
    let seconds = Int(remaining.rounded(.up))
    guard seconds >= 60 else { return "\(max(seconds, 0)) sec left" }
    let totalMinutes = (seconds + 59) / 60
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    switch (hours, minutes) {
    case (0, _): return "\(minutes) min left"
    case (_, 0): return "\(hours) hr left"
    default: return "\(hours) hr \(minutes) min left"
    }
  }
}
