import Foundation

/// Lenteur et pannes simulées des sources factices (`--claude-usage`, `--codex-usage`,
/// `--copilot-usage`), pour voir les états de chargement et d'erreur de l'onglet Usage sans
/// couper le réseau.
///
/// - `--usage-delay=<secondes>` : chaque lecture factice attend ce temps avant de répondre.
/// - `--usage-fail=<liste>` : fournisseurs dont la lecture échoue, séparés par des virgules :
///   `claude`, `codex`, `copilot` ou `all`. Suffixe `:expired` pour une session expirée
///   (Claude et Codex seulement), par exemple `--usage-fail=claude:expired,copilot`.
nonisolated enum MockUsageBehavior {

  struct Failure: LocalizedError {
    var errorDescription: String? { "Simulated failure (--usage-fail)." }
  }

  static func apply(
    provider: String, arguments: [String] = CommandLine.arguments
  ) async throws {
    if let delay = delay(arguments), delay > 0 {
      try await Task.sleep(for: .seconds(delay))
    }
    switch failure(for: provider, arguments: arguments) {
    case .none: return
    case .failure: throw Failure()
    case .expired:
      switch provider {
      case "claude": throw ClaudeUsageCredentialError.expired
      case "codex": throw CodexUsageCredentialError.notSignedIn
      default: throw Failure()
      }
    }
  }

  enum Outcome: Equatable {
    case none
    case failure
    case expired
  }

  static func delay(_ arguments: [String]) -> Double? {
    arguments.first { $0.hasPrefix("--usage-delay=") }
      .flatMap { Double($0.dropFirst("--usage-delay=".count)) }
  }

  static func failure(for provider: String, arguments: [String]) -> Outcome {
    guard let argument = arguments.first(where: { $0.hasPrefix("--usage-fail=") }) else {
      return .none
    }
    for entry in argument.dropFirst("--usage-fail=".count).split(separator: ",") {
      let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
      guard let name = parts.first, name == provider || name == "all" else { continue }
      return parts.count > 1 && parts[1] == "expired" ? .expired : .failure
    }
    return .none
  }
}
