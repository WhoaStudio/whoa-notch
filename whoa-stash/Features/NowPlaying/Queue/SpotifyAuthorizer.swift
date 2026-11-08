import AppKit
import CryptoKit
import Foundation
import OSLog

/// Connexion au compte Spotify de l'utilisateur (OAuth 2 avec PKCE, sans secret client) et jetons
/// à jour pour l'API web. La file de lecture n'existe que là : AppleScript n'y donne pas accès.
///
/// L'utilisateur crée une application sur developer.spotify.com, y déclare `redirectURI`, et colle
/// son identifiant client dans les Préférences ; le navigateur s'ouvre une fois pour l'accord.
actor SpotifyAuthorizer {

  static let shared = SpotifyAuthorizer()

  /// À déclarer tel quel dans l'application Spotify : Spotify n'accepte `http` que sur 127.0.0.1.
  static let redirectURI = "http://127.0.0.1:48731/callback"
  private static let port: UInt16 = 48731
  private static let scope = "user-read-playback-state"

  enum Failure: Error, LocalizedError {
    case missingClientID
    case exchangeFailed
    case notConnected

    var errorDescription: String? {
      switch self {
      case .missingClientID: "Enter your Spotify Client ID first."
      case .exchangeFailed: "Spotify refused the sign-in."
      case .notConnected: "Not connected to Spotify."
      }
    }
  }

  private var tokens: SpotifyTokens? = SpotifyTokenStore.load()

  func isConnected() -> Bool { tokens != nil }

  func connect(clientID: String) async throws {
    guard !clientID.isEmpty else { throw Failure.missingClientID }

    let verifier = Self.randomString(length: 64)
    let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    let state = Self.randomString(length: 16)

    var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "scope", value: Self.scope),
      URLQueryItem(name: "state", value: state),
    ]
    let authorizeURL = components.url!

    let server = SpotifyLoopbackServer(port: Self.port)
    let code = try await server.receiveCode(expectedState: state, timeout: .seconds(180)) {
      Task { @MainActor in NSWorkspace.shared.open(authorizeURL) }
    }

    let granted = try await requestTokens(
      [
        "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
        "client_id": clientID, "code_verifier": verifier,
      ], previousRefreshToken: nil)
    store(granted)
    Log.nowPlaying.info("compte Spotify connecté")
  }

  func disconnect() {
    tokens = nil
    SpotifyTokenStore.delete()
  }

  /// Un jeton d'accès valable, renouvelé si besoin. Un refus de renouvellement vaut déconnexion.
  func accessToken(clientID: String) async throws -> String {
    guard let current = tokens else { throw Failure.notConnected }
    if !current.isExpired { return current.accessToken }
    guard !clientID.isEmpty else { throw Failure.missingClientID }

    do {
      let refreshed = try await requestTokens(
        [
          "grant_type": "refresh_token", "refresh_token": current.refreshToken,
          "client_id": clientID,
        ], previousRefreshToken: current.refreshToken)
      store(refreshed)
      return refreshed.accessToken
    } catch {
      disconnect()
      throw error
    }
  }

  /// Spotify a refusé le jeton (401) : on le tient pour périmé, le prochain appel le renouvelle.
  func invalidateAccessToken() {
    guard var current = tokens else { return }
    current.expiresAt = .distantPast
    tokens = current
  }

  // MARK: - Jetons

  private func store(_ newTokens: SpotifyTokens) {
    tokens = newTokens
    SpotifyTokenStore.save(newTokens)
  }

  private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws
    -> SpotifyTokens
  {
    var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(
      form.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
      }.joined(separator: "&").utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let granted = Self.tokens(fromTokenResponse: data, previousRefreshToken: previousRefreshToken)
    else { throw Failure.exchangeFailed }
    return granted
  }

  /// Lit la réponse du point d'accès `token`. Un renouvellement ne renvoie pas toujours un nouveau
  /// jeton de renouvellement : on garde alors l'ancien.
  static func tokens(fromTokenResponse data: Data, previousRefreshToken: String?, now: Date = .now)
    -> SpotifyTokens?
  {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let access = object["access_token"] as? String,
      let refresh = (object["refresh_token"] as? String) ?? previousRefreshToken
    else { return nil }
    let lifetime = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
    return SpotifyTokens(
      accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(lifetime))
  }

  // MARK: - PKCE

  private static func randomString(length: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
