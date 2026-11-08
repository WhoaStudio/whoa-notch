import Foundation

enum CopilotUsageServiceError: LocalizedError {
  case badStatus(Int)
  case unrecognizedPayload(keys: [String])

  var errorDescription: String? {
    switch self {
    case .badStatus(let code):
      return "Réponse GitHub inattendue (HTTP \(code))."
    case .unrecognizedPayload(let keys):
      return "Réponse Copilot illisible (clés reçues : \(keys.joined(separator: ", ")))."
    }
  }
}

struct CopilotUsageService: CopilotUsageProviding {
  private let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!
  private let credentials = CopilotUsageCredentialStore()
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchSnapshot() async throws -> CopilotUsageSnapshot {
    let token = try credentials.accessToken()
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw CopilotUsageServiceError.badStatus(http.statusCode)
    }
    return try Self.parse(data)
  }

  static func parse(_ data: Data) throws -> CopilotUsageSnapshot {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let quotas = root["quota_snapshots"] as? [String: Any],
      let premium = quotas["premium_interactions"] as? [String: Any],
      let remaining = number(premium["percent_remaining"]),
      let reset = date(root["quota_reset_date_utc"] ?? root["quota_reset_date"])
    else {
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      throw CopilotUsageServiceError.unrecognizedPayload(keys: root?.keys.sorted() ?? [])
    }

    let utilization = min(100, max(0, 100 - remaining)) / 100
    return CopilotUsageSnapshot(
      premiumInteractions: ClaudeUsageWindow(utilization: utilization, resetsAt: reset),
      monthlyReset: reset
    )
  }

  private static func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static let iso8601 = ISO8601DateFormatter()
  private static let iso8601Fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static func date(_ value: Any?) -> Date? {
    if let value = value as? String {
      return iso8601Fractional.date(from: value) ?? iso8601.date(from: value)
    }
    if let value = number(value) {
      return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
    return nil
  }
}
