import Foundation

/// Texte des mesures de la section Activity. Pur, pour que les tests fixent les chiffres.
nonisolated enum ActivityFormatting {

  /// « 842 », « 12.3K », « 4.6M » : les jetons se comptent vite en millions.
  static func tokens(_ count: Int) -> String {
    func scaled(_ value: Double, _ suffix: String) -> String {
      let text = value < 100 ? String(format: "%.1f", value) : String(format: "%.0f", value)
      return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
    }
    switch count {
    case ..<1_000: return "\(count)"
    case ..<1_000_000: return scaled(Double(count) / 1_000, "K")
    case ..<1_000_000_000: return scaled(Double(count) / 1_000_000, "M")
    default: return scaled(Double(count) / 1_000_000_000, "B")
    }
  }

  /// « $12.34 » ; au-delà de 1 000 $ les centimes ne disent plus rien. `nil` : aucun modèle de
  /// la période n'a de tarif connu.
  static func money(_ amount: Double?) -> String {
    guard let amount else { return "n/a" }
    return amount < 1_000 ? String(format: "$%.2f", amount) : "$" + tokens(Int(amount.rounded()))
  }

  static func activeDays(_ summary: ActivitySummary) -> String {
    "\(summary.activeDays)/\(summary.daysInPeriod)"
  }

  /// « 1.8M · $49.13 » : jetons et coût du mois, sur une ligne, pour la pastille de l'en-tête.
  static func chip(_ summary: ActivitySummary) -> String {
    "\(tokens(summary.tokens)) · \(money(summary.cost))"
  }
}
