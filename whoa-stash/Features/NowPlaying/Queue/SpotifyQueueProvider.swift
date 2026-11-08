import Foundation
import OSLog

/// Les titres à venir de Spotify, par l'API web (`GET /v1/me/player/queue`), avec le compte relié
/// dans les Préférences. Vide tant que le compte n'est pas connecté.
nonisolated struct SpotifyQueueProvider: PlayingNextProviding {

  static let bundleIdentifier = "com.spotify.client"

  /// Lu à chaque appel : l'identifiant se règle dans les Préférences, sur le fil principal.
  let clientID: @MainActor @Sendable () -> String

  func supports(bundleIdentifier: String) -> Bool { bundleIdentifier == Self.bundleIdentifier }

  func upcoming(limit: Int) async -> [QueueItem] {
    let clientID = await clientID()
    guard !clientID.isEmpty,
      let token = try? await SpotifyAuthorizer.shared.accessToken(clientID: clientID)
    else { return [] }

    var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 8

    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return [] }
    if status == 401 { await SpotifyAuthorizer.shared.invalidateAccessToken() }
    guard status == 200 else {
      Log.nowPlaying.error("file Spotify : statut \(status, privacy: .public)")
      return []
    }

    let entries = Self.parse(data, limit: limit)
    return await withTaskGroup(of: (Int, Data?).self) { group in
      for (index, entry) in entries.enumerated() {
        group.addTask { (index, await Self.download(entry.artworkURL)) }
      }
      var artwork: [Int: Data] = [:]
      for await (index, data) in group { if let data { artwork[index] = data } }
      return entries.enumerated().map {
        QueueItem(title: $0.element.title, artist: $0.element.artist, artwork: artwork[$0.offset])
      }
    }
  }

  struct Entry: Equatable {
    var title: String
    var artist: String
    var artworkURL: URL?
  }

  /// Lit `{"queue": [{name, artists: [{name}], album: {images: [{url, width}]}}, …]}`. La plus
  /// petite image d'au moins 64 px suffit : la colonne les affiche à moins de 40 pt.
  static func parse(_ data: Data, limit: Int) -> [Entry] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let queue = object["queue"] as? [[String: Any]]
    else { return [] }

    return queue.prefix(limit).compactMap { track in
      guard let title = track["name"] as? String, !title.isEmpty else { return nil }
      let artists =
        (track["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
      let images = ((track["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? []
      let sized = images.compactMap { image -> (width: Int, url: URL)? in
        guard let string = image["url"] as? String, let url = URL(string: string) else {
          return nil
        }
        return ((image["width"] as? Int) ?? 0, url)
      }
      let chosen = sized.filter { $0.width >= 64 }.min { $0.width < $1.width } ?? sized.last
      return Entry(title: title, artist: artists.joined(separator: ", "), artworkURL: chosen?.url)
    }
  }

  private static func download(_ url: URL?) async -> Data? {
    guard let url, let (data, response) = try? await URLSession.shared.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return data
  }
}
