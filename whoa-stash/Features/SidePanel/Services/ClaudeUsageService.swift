import Foundation

enum ClaudeUsageServiceError: LocalizedError {
  case badStatus(Int)
  case unrecognizedPayload(keys: [String])

  var errorDescription: String? {
    switch self {
    case .badStatus(let code): return "Réponse inattendue du serveur (HTTP \(code))."
    case .unrecognizedPayload(let keys):
      return "Réponse illisible (clés reçues : \(keys.joined(separator: ", ")))."
    }
  }
}

/// Interroge le même point d'entrée que `/usage` dans Claude Code, avec le jeton OAuth du
/// trousseau.
///
/// Ce point d'entrée n'est pas documenté publiquement : sa forme peut changer sans préavis. Tout
/// le décodage passe donc par `JSONSerialization` et une liste de clés acceptées plutôt que par un
/// `Codable` rigide, et un échec de lecture remonte les clés réellement reçues
/// (`unrecognizedPayload`) — de quoi réparer en une passe le jour où elles bougent, au lieu de
/// n'avoir qu'un « decoding error » muet.
struct ClaudeUsageService: ClaudeUsageProviding {

  private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
  private let credentials = ClaudeUsageCredentialStore()
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchSnapshot() async throws -> ClaudeUsageSnapshot {
    let token = try credentials.accessToken()

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw ClaudeUsageServiceError.badStatus(http.statusCode)
    }

    return try Self.parse(data)
  }

  // MARK: - Décodage tolérant

  /// Clés acceptées pour chacune des deux fenêtres, de la plus probable à la plus défensive.
  private static let sessionKeys = ["five_hour", "fiveHour", "session"]
  private static let allModelsKeys = ["seven_day", "sevenDay", "all_models", "week"]

  static func parse(_ data: Data) throws -> ClaudeUsageSnapshot {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ClaudeUsageServiceError.unrecognizedPayload(keys: [])
    }
    guard
      let session = window(in: root, keys: sessionKeys),
      let allModels = window(in: root, keys: allModelsKeys)
    else {
      throw ClaudeUsageServiceError.unrecognizedPayload(keys: root.keys.sorted())
    }
    return ClaudeUsageSnapshot(session: session, allModels: allModels)
  }

  private static func window(in root: [String: Any], keys: [String]) -> ClaudeUsageWindow? {
    guard
      let raw = keys.lazy.compactMap({ root[$0] as? [String: Any] }).first,
      let utilization = number(
        in: raw, keys: ["utilization", "used_percent", "percent_used", "percentage"]),
      let resetsAt = date(in: raw, keys: ["resets_at", "resetsAt", "reset_at"])
    else { return nil }

    // Échelle supposée 0–100, comme l'affiche `/usage`. `ClaudeUsageWindow` borne ensuite.
    return ClaudeUsageWindow(utilization: utilization / 100, resetsAt: resetsAt)
  }

  private static func number(in raw: [String: Any], keys: [String]) -> Double? {
    for key in keys {
      if let value = raw[key] as? Double { return value }
      if let value = raw[key] as? Int { return Double(value) }
      if let string = raw[key] as? String, let value = Double(string) { return value }
    }
    return nil
  }

  private static let iso8601 = ISO8601DateFormatter()
  private static let iso8601Fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static func date(in raw: [String: Any], keys: [String]) -> Date? {
    for key in keys {
      if let string = raw[key] as? String {
        if let date = iso8601.date(from: string) ?? iso8601Fractional.date(from: string) {
          return date
        }
      }
      // Époque en secondes ; les valeurs en millisecondes (> an 2286 lues en secondes) sont
      // ramenées à l'échelle attendue.
      if let epoch = raw[key] as? Double {
        return Date(timeIntervalSince1970: epoch > 10_000_000_000 ? epoch / 1000 : epoch)
      }
      if let epoch = raw[key] as? Int {
        let value = Double(epoch)
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
      }
    }
    return nil
  }
}
