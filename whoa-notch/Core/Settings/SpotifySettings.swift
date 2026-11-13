import Foundation

/// Compte Spotify, pour la colonne « Playing Next » : seul l'identifiant client de l'application
/// que l'utilisateur crée sur developer.spotify.com se règle ici. Il n'a rien de secret (la
/// connexion est en PKCE, sans secret client) ; les jetons, eux, vivent dans le trousseau.
struct SpotifySettings: Codable, Equatable, Sendable {
  var clientID: String = ""
}
