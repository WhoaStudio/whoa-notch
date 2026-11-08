import Foundation
import Security
import Synchronization

enum ClaudeUsageCredentialError: LocalizedError {
  case notFound
  case unreadable(OSStatus)
  case malformed
  case expired

  var errorDescription: String? {
    switch self {
    case .notFound: return "Claude Code n'est pas connecté sur cette machine."
    case .unreadable(let status): return "Trousseau illisible (OSStatus \(status))."
    case .malformed: return "Jeton Claude Code illisible."
    case .expired: return "Session Claude Code expirée — relance `claude` pour la renouveler."
    }
  }
}

/// Lit le jeton OAuth que Claude Code dépose dans le trousseau de l'utilisateur, sous un item
/// générique dont le service commence par `Claude Code-credentials`.
///
/// L'ACL de cet item appartient à Claude Code et n'autorise que `/usr/bin/security`. Lu
/// directement, il déclencherait une invite du trousseau après chaque rafraîchissement du jeton
/// par Claude Code ; on passe donc par `/usr/bin/security`, comme Claude Code lui-même (détails
/// sur `readPayload`). L'app doit rester fonctionnelle si la lecture échoue, d'où
/// `ClaudeUsageState.unavailable`.
///
/// Deux précautions en plus :
///
/// - une lecture par jeton, pas une par rafraîchissement (`TokenCache`) ;
/// - l'item est repéré par préfixe de service et non par nom exact, pour suivre Claude Code quand
///   il passe de `Claude Code-credentials` à `Claude Code-credentials-<hash>`.
///
/// Le jeton est gardé en mémoire jusqu'à son expiration, et nulle part ailleurs : il n'est ni
/// recopié dans le trousseau, ni écrit sur disque, ni journalisé.
struct ClaudeUsageCredentialStore {

  /// Préfixe commun aux items de Claude Code. Selon l'installation, le service s'appelle
  /// exactement comme ça ou porte un suffixe `-<hash>` propre à l'installation.
  static let keychainServicePrefix = "Claude Code-credentials"

  /// Marge avant expiration : inutile de partir sur une requête qui sera refusée en vol, ni de
  /// servir depuis le cache un jeton qui va expirer pendant l'appel.
  private static let expiryMargin: TimeInterval = 30

  /// Horizon retenu quand le jeton ne porte pas d'`expiresAt` : on ne connaît pas sa durée de
  /// vie, mais relire le trousseau à chaque rafraîchissement n'est pas une option.
  private static let fallbackLifetime: TimeInterval = 5 * 60

  /// Forme du JSON stocké dans l'item : `expiresAt` est un timestamp **en millisecondes**.
  private struct Payload: Decodable {
    struct OAuth: Decodable {
      let accessToken: String
      let expiresAt: Double?
    }
    let claudeAiOauth: OAuth
  }

  /// Item retenu, désigné par ce qu'il faut pour aller relire ses données.
  private struct ItemRef {
    let service: String
    let account: String?
  }

  private let cache = TokenCache()

  /// Explicite parce que `cache` est privé : l'init par membres le serait aussi.
  init() {}

  func accessToken(now: Date = Date()) throws -> String {
    if let cached = cache.token(at: now, margin: Self.expiryMargin) { return cached }

    let payload = try readPayload(from: try locateItem())
    let token = payload.claudeAiOauth.accessToken

    guard let expiresAt = payload.claudeAiOauth.expiresAt else {
      cache.store(token, until: now.addingTimeInterval(Self.fallbackLifetime))
      return token
    }

    let expiry = Date(timeIntervalSince1970: expiresAt / 1000)
    guard expiry.timeIntervalSince(now) > Self.expiryMargin else {
      throw ClaudeUsageCredentialError.expired
    }

    cache.store(token, until: expiry)
    return token
  }

  // MARK: - Trousseau

  /// Repère l'item de Claude Code sans lire son contenu.
  ///
  /// La requête ne demande que les attributs : elle ne déclenche donc aucune autorisation du
  /// trousseau, seule la lecture des données en déclenche une. On ne la fera que sur l'item
  /// retenu — le plus récemment modifié, c'est-à-dire celui que Claude Code tient à jour quand
  /// plusieurs installations ont laissé leur item derrière elles.
  private func locateItem() throws -> ItemRef {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status != errSecItemNotFound else { throw ClaudeUsageCredentialError.notFound }
    guard status == errSecSuccess, let items = result as? [[String: Any]] else {
      throw ClaudeUsageCredentialError.unreadable(status)
    }

    let candidates = items.compactMap { attributes -> (ref: ItemRef, modified: Date)? in
      guard
        let service = attributes[kSecAttrService as String] as? String,
        service == Self.keychainServicePrefix
          || service.hasPrefix(Self.keychainServicePrefix + "-")
      else { return nil }

      let ref = ItemRef(service: service, account: attributes[kSecAttrAccount as String] as? String)
      // Un item sans date de modification ne doit pas gagner contre un item daté.
      let modified = attributes[kSecAttrModificationDate as String] as? Date ?? .distantPast
      return (ref, modified)
    }

    guard let newest = candidates.max(by: { $0.modified < $1.modified })?.ref else {
      throw ClaudeUsageCredentialError.notFound
    }
    return newest
  }

  /// Lecture effective des données, déléguée à `/usr/bin/security` — comme le fait Claude Code.
  ///
  /// Un `SecItemCopyMatching` direct redemanderait l'autorisation après chaque rafraîchissement
  /// du jeton : Claude Code réécrit l'item avec `security add-generic-password -U`, ce qui ramène
  /// sa liste de partitions à `apple-tool:` et efface le `teamid:` ajouté par « Toujours
  /// autoriser ». `/usr/bin/security` figure dans l'ACL de l'item et relève de `apple-tool:` :
  /// il le lit sans invite.
  private func readPayload(from ref: ItemRef) throws -> Payload {
    var arguments = ["find-generic-password", "-s", ref.service]
    // Le compte lève l'ambiguïté si le même service existe pour plusieurs comptes.
    if let account = ref.account {
      arguments += ["-a", account]
    }
    arguments.append("-w")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw ClaudeUsageCredentialError.unreadable(errSecInternalComponent)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    // `security` sort avec le code 44 (`errSecItemNotFound` tronqué) quand l'item manque.
    guard process.terminationStatus != 44 else { throw ClaudeUsageCredentialError.notFound }
    guard process.terminationStatus == 0 else {
      throw ClaudeUsageCredentialError.unreadable(OSStatus(process.terminationStatus))
    }

    guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
      throw ClaudeUsageCredentialError.malformed
    }
    return payload
  }
}

/// Jeton déjà lu, gardé jusqu'à son expiration.
///
/// C'est ce qui ramène les lectures du trousseau à une par jeton — quelques heures — au lieu
/// d'une par rafraîchissement : `ClaudeUsageViewModel` rafraîchit au lancement, chaque minute, à
/// chaque ouverture du panneau et à chaque réveil, et chaque lecture est une évaluation d'ACL,
/// donc une autorisation de plus à accorder tant que l'app n'est pas dans l'ACL de l'item.
///
/// `Mutex` plutôt qu'une simple variable : la lecture part d'une `Task` et le store doit rester
/// `Sendable` pour traverser la frontière d'isolation, comme le reste de `ClaudeUsageProviding`.
/// `nonisolated` pour la même raison que les `Logger` de `Log` — le module est compilé avec
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, qui isolerait sinon ce cache sur le main actor.
nonisolated private final class TokenCache: Sendable {

  private let entry = Mutex<(token: String, expiry: Date)?>(nil)

  func token(at now: Date, margin: TimeInterval) -> String? {
    entry.withLock { entry in
      guard let current = entry else { return nil }
      guard current.expiry.timeIntervalSince(now) > margin else {
        // Périmé : on l'oublie tout de suite plutôt que de garder un jeton mort en mémoire.
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
