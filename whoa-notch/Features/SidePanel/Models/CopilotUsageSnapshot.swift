import Foundation

struct CopilotUsageSnapshot: Equatable, Sendable {
  let premiumInteractions: ClaudeUsageWindow
  let monthlyReset: Date
}

enum CopilotUsageState: Equatable {
  case loading
  case loaded(CopilotUsageSnapshot)
  case unavailable(reason: String)

  var snapshot: CopilotUsageSnapshot? {
    if case .loaded(let snapshot) = self { return snapshot }
    return nil
  }

  var ringState: ClaudeUsageState {
    switch self {
    case .loading:
      return .loading
    case .loaded(let snapshot):
      return .loaded(
        ClaudeUsageSnapshot(
          session: snapshot.premiumInteractions,
          allModels: ClaudeUsageWindow(utilization: 0, resetsAt: snapshot.monthlyReset)
        )
      )
    case .unavailable(let reason):
      return .unavailable(reason: reason)
    }
  }
}
