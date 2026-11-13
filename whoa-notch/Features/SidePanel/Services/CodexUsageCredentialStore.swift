import Foundation

enum CodexUsageCredentialError: LocalizedError {
  case notSignedIn
  case unreadable

  var errorDescription: String? {
    switch self {
    case .notSignedIn: "Codex n'est pas connecté sur ce Mac."
    case .unreadable: "Le fichier d'authentification de Codex est illisible."
    }
  }
}

/// Lit le jeton de la connexion ChatGPT de Codex dans `auth.json` (`$CODEX_HOME`, sinon
/// `~/.codex`). Le jeton ne sert qu'à interroger le quota : il reste en mémoire le temps de la
/// requête, n'est jamais journalisé et n'est jamais réécrit — le renouveler reste l'affaire de
/// Codex.
struct CodexUsageCredentialStore: Sendable {

  struct Credentials: Sendable {
    let accessToken: String
    let accountID: String?
  }

  private let fileURL: URL

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    let home =
      environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    fileURL = home.appendingPathComponent("auth.json")
  }

  func credentials() throws -> Credentials {
    guard let data = try? Data(contentsOf: fileURL) else {
      throw CodexUsageCredentialError.notSignedIn
    }
    return try Self.parse(data)
  }

  static func parse(_ data: Data) throws -> Credentials {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CodexUsageCredentialError.unreadable
    }
    // Connexion par clé d'API : pas de quota ChatGPT à lire.
    guard let tokens = root["tokens"] as? [String: Any],
      let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty
    else { throw CodexUsageCredentialError.notSignedIn }
    return Credentials(accessToken: accessToken, accountID: tokens["account_id"] as? String)
  }
}
