import Foundation
import Security

/// Mot de passe IMAP (ou mot de passe d'application) de l'utilisateur, dans le trousseau de l'app —
/// jamais dans `UserDefaults` ni dans un journal.
nonisolated enum IMAPCredentialStore {

  private static let service = "ugolin-olle.whoa-stash.imap"

  private static func baseQuery(for account: IMAPAccount) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "\(account.username)@\(account.host)",
    ]
  }

  static func load(for account: IMAPAccount) -> String? {
    var query = baseQuery(for: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ password: String, for account: IMAPAccount) {
    let data = Data(password.utf8)
    let status = SecItemUpdate(
      baseQuery(for: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = baseQuery(for: account)
      item[kSecValueData as String] = data
      SecItemAdd(item as CFDictionary, nil)
    }
  }

  static func delete(for account: IMAPAccount) {
    SecItemDelete(baseQuery(for: account) as CFDictionary)
  }
}
