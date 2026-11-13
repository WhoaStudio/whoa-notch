import Foundation

protocol CopilotUsageProviding: Sendable {
  func fetchSnapshot() async throws -> CopilotUsageSnapshot
}

struct MockCopilotUsageProvider: CopilotUsageProviding {
  let percent: Double

  func fetchSnapshot() async throws -> CopilotUsageSnapshot {
    try await MockUsageBehavior.apply(provider: "copilot")
    let now = Date()
    return CopilotUsageSnapshot(
      premiumInteractions: ClaudeUsageWindow(
        utilization: percent / 100,
        resetsAt: now.addingTimeInterval(3 * 24 * 3600)
      ),
      monthlyReset: now.addingTimeInterval(3 * 24 * 3600)
    )
  }

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockCopilotUsageProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--copilot-usage=") }),
      let percent = Double(argument.dropFirst("--copilot-usage=".count))
    else { return nil }
    return MockCopilotUsageProvider(percent: percent)
  }
}
