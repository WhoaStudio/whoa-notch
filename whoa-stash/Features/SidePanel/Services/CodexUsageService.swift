import Foundation

enum CodexUsageServiceError: LocalizedError {
  case badStatus(Int)
  case unrecognizedPayload(keys: [String])

  var errorDescription: String? {
    switch self {
    case .badStatus(let code) where code == 401 || code == 403:
      "Connexion Codex expirée — relancez Codex pour la renouveler (HTTP \(code))."
    case .badStatus(let code):
      "Réponse ChatGPT inattendue (HTTP \(code))."
    case .unrecognizedPayload(let keys):
      "Réponse Codex illisible (clés reçues : \(keys.joined(separator: ", ")))."
    }
  }
}

/// Quota Codex, tel que le client Codex le lit lui-même : `GET /backend-api/wham/usage` avec le
/// jeton de la connexion ChatGPT. Point d'entrée non documenté, comme celui de Claude.
struct CodexUsageService: CodexUsageProviding {
  private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
  private let credentials = CodexUsageCredentialStore()
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchSnapshot() async throws -> CodexUsageSnapshot {
    let credentials = try credentials.credentials()
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
    if let accountID = credentials.accountID {
      request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
    }

    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw CodexUsageServiceError.badStatus(http.statusCode)
    }
    return try Self.parse(data)
  }

  /// Une fenêtre se reconnaît à sa durée (`limit_window_seconds`), pas à son rang : selon le
  /// forfait, la fenêtre principale est la session de 5 h ou déjà l'hebdomadaire.
  static func parse(_ data: Data, now: Date = Date()) throws -> CodexUsageSnapshot {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let limits = root["rate_limit"] as? [String: Any]
    else {
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      throw CodexUsageServiceError.unrecognizedPayload(keys: root?.keys.sorted() ?? [])
    }

    var fiveHour: ClaudeUsageWindow?
    var weekly: ClaudeUsageWindow?
    for (rank, key) in ["primary_window", "secondary_window"].enumerated() {
      guard let raw = limits[key] as? [String: Any],
        let used = number(raw["used_percent"]),
        let reset = resetDate(raw, now: now)
      else { continue }
      let window = ClaudeUsageWindow(utilization: used / 100, resetsAt: reset)
      let seconds = number(raw["limit_window_seconds"])
      let isWeekly = seconds.map { $0 >= 6 * 24 * 3600 } ?? (rank == 1)
      if isWeekly { weekly = window } else { fiveHour = window }
    }

    guard fiveHour != nil || weekly != nil else {
      throw CodexUsageServiceError.unrecognizedPayload(keys: limits.keys.sorted())
    }
    return CodexUsageSnapshot(fiveHour: fiveHour, weekly: weekly)
  }

  private static func resetDate(_ window: [String: Any], now: Date) -> Date? {
    if let at = number(window["reset_at"]) {
      return Date(timeIntervalSince1970: at > 10_000_000_000 ? at / 1000 : at)
    }
    return number(window["reset_after_seconds"]).map { now.addingTimeInterval($0) }
  }

  private static func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
  }
}
