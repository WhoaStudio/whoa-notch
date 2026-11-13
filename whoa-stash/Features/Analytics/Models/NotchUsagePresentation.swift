import Foundation

/// Ce que l'onglet Usage dérive d'une lecture sans rien recalculer d'elle : couleur selon le
/// reste, rythme de consommation, textes relatifs. Pur et sans AppKit pour pouvoir se tester.
/// Les pourcentages eux-mêmes viennent toujours de `NotchUsageReading`.

/// Teinte de la jauge : elle vire à l'ambre puis au rouge quand la limite approche.
nonisolated enum NotchUsageTone: Equatable {
  case plenty
  case low
  case critical

  /// Sous 10 % restants : critique ; sous 30 % : bas. Sans valeur (chargement, erreur) : calme.
  init(remaining: Double?) {
    guard let remaining else {
      self = .plenty
      return
    }
    if remaining < 0.10 {
      self = .critical
    } else if remaining < 0.30 {
      self = .low
    } else {
      self = .plenty
    }
  }
}

/// Rythme de consommation par rapport à une consommation régulière sur la fenêtre.
nonisolated enum NotchUsagePace: Equatable {
  case under
  case on
  case over

  /// Écart toléré (en fraction de la fenêtre) avant de parler d'avance ou de retard.
  static let tolerance = 0.05

  /// Durée de la fenêtre, déduite de son étiquette (« 5H », « 7D », « MO »).
  static func windowLength(forLabel label: String) -> TimeInterval? {
    switch label {
    case "5H": 5 * 3600
    case "7D": 7 * 24 * 3600
    case "MO": 30 * 24 * 3600
    default: nil
    }
  }

  /// Le reste qu'une consommation régulière laisserait à `now` : la part de la fenêtre qui reste
  /// à courir. `nil` quand la réinitialisation est passée ou plus lointaine que la fenêtre.
  static func expectedRemaining(resetsAt: Date, windowLength: TimeInterval, now: Date) -> Double? {
    guard windowLength > 0 else { return nil }
    let left = resetsAt.timeIntervalSince(now)
    guard left > 0, left <= windowLength * 1.02 else { return nil }
    return min(1, left / windowLength)
  }

  static func evaluate(remaining: Double, expected: Double) -> NotchUsagePace {
    let delta = remaining - expected
    if delta < -tolerance { return .over }
    if delta > tolerance { return .under }
    return .on
  }
}

nonisolated enum NotchUsageFormatting {

  /// « Resets in 2 h 14 min », « Resets in 3 d 4 h ».
  static func resetsIn(_ date: Date, now: Date) -> String {
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return "Resetting…" }
    let minutes = (seconds + 59) / 60
    if minutes < 60 { return "Resets in \(minutes) min" }
    let hours = minutes / 60
    if hours < 24 {
      let rest = minutes % 60
      return rest == 0 ? "Resets in \(hours) h" : "Resets in \(hours) h \(rest) min"
    }
    let days = hours / 24
    let restHours = hours % 24
    return restHours == 0 ? "Resets in \(days) d" : "Resets in \(days) d \(restHours) h"
  }

  /// « Updated just now », « Updated 3 min ago ».
  static func updatedAgo(_ date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 45 { return "Updated just now" }
    let minutes = (seconds + 30) / 60
    if minutes < 60 { return "Updated \(minutes) min ago" }
    return "Updated \(minutes / 60) h ago"
  }

  /// Part consommée, complément exact du reste arrondi : les deux chiffres font toujours 100.
  static func usedPercentage(remainingPercentage: Int) -> Int {
    max(0, min(100, 100 - remainingPercentage))
  }

  /// Valeur exacte pour l'info-bulle de la jauge : « 47.3% remaining · 52.7% used ».
  static func exactText(remaining: Double) -> String {
    let remainingTenths = (min(1, max(0, remaining)) * 1000).rounded()
    let used = (1000 - remainingTenths) / 10
    return String(format: "%.1f%% remaining · %.1f%% used", remainingTenths / 10, used)
  }
}
