import Foundation
import Security

/// Jetons Spotify de l'utilisateur, dans le trousseau de l'app — jamais dans `UserDefaults` ni dans
/// un journal.
nonisolated struct SpotifyTokens: Codable, Equatable, Sendable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Date

  /// Une marge évite d'envoyer un jeton qui expire pendant la requête.
  var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

nonisolated enum SpotifyTokenStore {

  private static let service = "ugolin-olle.whoa-notch.spotify"
  private static let account = "tokens"

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func load() -> SpotifyTokens? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
  }

  static func save(_ tokens: SpotifyTokens) {
    guard let data = try? JSONEncoder().encode(tokens) else { return }
    let status = SecItemUpdate(
      baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = baseQuery
      item[kSecValueData as String] = data
      SecItemAdd(item as CFDictionary, nil)
    }
  }

  static func delete() {
    SecItemDelete(baseQuery as CFDictionary)
  }
}
