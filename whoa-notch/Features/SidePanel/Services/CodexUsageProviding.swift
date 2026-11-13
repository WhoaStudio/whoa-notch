import Foundation

protocol CodexUsageProviding: Sendable {
  func fetchSnapshot() async throws -> CodexUsageSnapshot
}

/// Valeurs fixes pour développer et vérifier sans réseau ni connexion Codex :
/// `--codex-usage=<5h>,<7j>` donne les pourcentages **consommés**.
struct MockCodexUsageProvider: CodexUsageProviding {
  let fiveHourPercent: Double
  let weeklyPercent: Double

  func fetchSnapshot() async throws -> CodexUsageSnapshot {
    try await MockUsageBehavior.apply(provider: "codex")
    let now = Date()
    return CodexUsageSnapshot(
      fiveHour: ClaudeUsageWindow(
        utilization: fiveHourPercent / 100, resetsAt: now.addingTimeInterval(2 * 3600)),
      weekly: ClaudeUsageWindow(
        utilization: weeklyPercent / 100, resetsAt: now.addingTimeInterval(3 * 24 * 3600))
    )
  }

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockCodexUsageProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--codex-usage=") }) else {
      return nil
    }
    let values = argument.dropFirst("--codex-usage=".count).split(separator: ",").compactMap {
      Double($0)
    }
    guard values.count == 2 else { return nil }
    return MockCodexUsageProvider(fiveHourPercent: values[0], weeklyPercent: values[1])
  }
}
