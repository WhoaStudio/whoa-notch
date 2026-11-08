import Foundation
import Security
import Synchronization

enum CopilotUsageCredentialError: LocalizedError {
  case notFound
  case unreadable(OSStatus)
  case malformed

  var errorDescription: String? {
    switch self {
    case .notFound:
      return "GitHub Copilot n'est pas connecté sur cette machine."
    case .unreadable(let status):
      return "Trousseau GitHub illisible (OSStatus \(status))."
    case .malformed:
      return "Jeton GitHub illisible."
    }
  }
}

struct CopilotUsageCredentialStore: Sendable {
  private static let services = ["github-copilot-app", "gh:github.com"]
  private static let fallbackLifetime: TimeInterval = 5 * 60
  private let cache = CopilotTokenCache()

  init() {}

  func accessToken(now: Date = Date()) throws -> String {
    if let token = cache.token(at: now) { return token }

    var lastError: Error?
    for service in Self.services {
      do {
        let token = try readToken(service: service)
        cache.store(token, until: now.addingTimeInterval(Self.fallbackLifetime))
        return token
      } catch {
        lastError = error
      }
    }
    throw lastError ?? CopilotUsageCredentialError.notFound
  }

  private func readToken(service: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else { throw CopilotUsageCredentialError.notFound }
    guard status == errSecSuccess, let data = item as? Data else {
      throw CopilotUsageCredentialError.unreadable(status)
    }

    let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("go-keyring-base64:"),
      let decoded = Data(base64Encoded: String(raw.dropFirst("go-keyring-base64:".count))),
      let token = String(data: decoded, encoding: .utf8)
    {
      return try validate(token)
    }
    return try validate(raw)
  }

  private func validate(_ token: String) throws -> String {
    guard token.hasPrefix("gho_") || token.hasPrefix("ghp_") || token.hasPrefix("github_pat_")
    else {
      throw CopilotUsageCredentialError.malformed
    }
    return token
  }
}

nonisolated private final class CopilotTokenCache: Sendable {
  private let entry = Mutex<(token: String, expiry: Date)?>(nil)

  func token(at now: Date) -> String? {
    entry.withLock { entry in
      guard let current = entry else { return nil }
      guard current.expiry > now else {
        entry = nil
        return nil
      }
      return current.token
    }
  }

  func store(_ token: String, until expiry: Date) {
    entry.withLock { $0 = (token: token, expiry: expiry) }
  }
}
