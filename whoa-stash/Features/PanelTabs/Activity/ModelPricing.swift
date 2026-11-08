import Foundation

/// Tarifs publics de l'API, en dollars par million de jetons.
///
/// Une écriture en cache coûte 1,25× l'entrée (durée de 5 min) ou 2× (durée d'1 h). La lecture
/// du cache est un tarif propre à chaque modèle, car son rapport à l'entrée varie.
///
/// Haiku 5.5 : tarif des prompts jusqu'à 100 K jetons ; le palier supérieur n'est pas distingué,
/// le journal ne dit pas la taille du prompt. Lecture du cache de Haiku 5.5 : 0,1× l'entrée, le
/// rapport général — la grille ne la liste pas.
///
/// Un modèle absent de la table n'a pas de coût : ses jetons sont comptés, pas son prix.
nonisolated struct ModelPricing: Equatable, Sendable {
  let input: Double
  let output: Double
  let cacheRead: Double

  static let cacheWrite5mMultiplier = 1.25
  static let cacheWrite1hMultiplier = 2.0

  /// Du préfixe le plus spécifique au plus général : la première correspondance gagne.
  private static let table: [(prefix: String, pricing: ModelPricing)] = [
    ("claude-fable-5", ModelPricing(input: 10, output: 50, cacheRead: 0.25)),
    ("claude-mythos-5", ModelPricing(input: 10, output: 50, cacheRead: 0.25)),
    ("claude-opus-5-5", ModelPricing(input: 4, output: 20, cacheRead: 0.20)),
    ("claude-opus-5", ModelPricing(input: 5, output: 25, cacheRead: 0.50)),
    ("claude-opus-4-8", ModelPricing(input: 5, output: 25, cacheRead: 0.50)),
    ("claude-opus-4-7", ModelPricing(input: 5, output: 25, cacheRead: 0.50)),
    ("claude-opus-4-6", ModelPricing(input: 5, output: 25, cacheRead: 0.50)),
    ("claude-sonnet-5", ModelPricing(input: 2, output: 10, cacheRead: 0.20)),
    ("claude-sonnet-4-6", ModelPricing(input: 3, output: 15, cacheRead: 0.30)),
    ("claude-haiku-5-5", ModelPricing(input: 0.10, output: 0.50, cacheRead: 0.01)),
    ("claude-haiku-4-5", ModelPricing(input: 1, output: 5, cacheRead: 0.10)),
  ]

  static func pricing(for model: String) -> ModelPricing? {
    table.first { model.hasPrefix($0.prefix) }?.pricing
  }

  func cost(of tokens: TokenCounts) -> Double {
    let perToken = 1.0 / 1_000_000
    return perToken
      * (Double(tokens.input) * input
        + Double(tokens.output) * output
        + Double(tokens.cacheRead) * cacheRead
        + Double(tokens.cacheWrite5m) * input * Self.cacheWrite5mMultiplier
        + Double(tokens.cacheWrite1h) * input * Self.cacheWrite1hMultiplier)
  }
}
