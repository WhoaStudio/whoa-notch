import Foundation

/// Source d'un instantané d'utilisation. L'abstraction existe pour que la bague et le panneau
/// soient développables et vérifiables sans réseau ni trousseau (`MockClaudeUsageProvider`),
/// exactement comme `BrightnessControlling` permet de développer l'overlay de luminosité sans
/// piloter l'écran réel.
protocol ClaudeUsageProviding: Sendable {
  func fetchSnapshot() async throws -> ClaudeUsageSnapshot
}

/// Valeurs fixes injectées par `--claude-usage=<session>,<allModels>` (en pourcents), dans le
/// même esprit que `--show-settings` déjà géré par `AppDelegate`.
struct MockClaudeUsageProvider: ClaudeUsageProviding {

  let sessionPercent: Double
  let allModelsPercent: Double

  /// Décalages volontairement différents pour que les deux lignes du panneau n'affichent pas le
  /// même texte de réinitialisation : 51 min pour la session (sous les 24 h → format relatif),
  /// et 3 jours pour l'hebdomadaire (au-delà → format jour + heure).
  func fetchSnapshot() async throws -> ClaudeUsageSnapshot {
    try await MockUsageBehavior.apply(provider: "claude")
    let now = Date()
    return ClaudeUsageSnapshot(
      session: ClaudeUsageWindow(
        utilization: sessionPercent / 100, resetsAt: now.addingTimeInterval(51 * 60)),
      allModels: ClaudeUsageWindow(
        utilization: allModelsPercent / 100, resetsAt: now.addingTimeInterval(3 * 24 * 3600))
    )
  }

  /// Parse `--claude-usage=73,7`. Renvoie `nil` si l'argument est absent ou mal formé, pour que
  /// l'app retombe silencieusement sur la vraie source.
  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockClaudeUsageProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--claude-usage=") }) else {
      return nil
    }
    let values = argument.dropFirst("--claude-usage=".count).split(separator: ",").compactMap {
      Double($0)
    }
    guard values.count == 2 else { return nil }
    return MockClaudeUsageProvider(sessionPercent: values[0], allModelsPercent: values[1])
  }
}
