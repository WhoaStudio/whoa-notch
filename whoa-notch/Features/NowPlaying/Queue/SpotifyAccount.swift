import Combine
import Foundation

/// État de la connexion Spotify pour les Préférences : la vue s'abonne à `status` et ne parle jamais
/// à `SpotifyAuthorizer` elle-même.
@MainActor
final class SpotifyAccount: ObservableObject {

  enum Status: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
  }

  static let shared = SpotifyAccount()

  @Published private(set) var status: Status = .disconnected

  private init() {
    Task { [weak self] in
      if await SpotifyAuthorizer.shared.isConnected() { self?.status = .connected }
    }
  }

  func connect(clientID: String) {
    guard status != .connecting else { return }
    status = .connecting
    Task { [weak self] in
      do {
        try await SpotifyAuthorizer.shared.connect(clientID: clientID)
        self?.status = .connected
      } catch let error as SpotifyAuthorizer.Failure {
        self?.status = .failed(error.localizedDescription)
      } catch is SpotifyLoopbackServer.Failure {
        self?.status = .failed("The sign-in did not complete.")
      } catch {
        self?.status = .failed(error.localizedDescription)
      }
    }
  }

  func disconnect() {
    Task { [weak self] in
      await SpotifyAuthorizer.shared.disconnect()
      self?.status = .disconnected
    }
  }
}
