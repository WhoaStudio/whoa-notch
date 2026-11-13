import Foundation

/// Ce qui joue en ce moment, tel que le système le rapporte — toutes sources confondues
/// (navigateur, Spotify, Musique).
nonisolated struct NowPlayingState: Equatable, Sendable {
  var title: String
  var artist: String
  var album: String = ""
  /// Image brute (JPEG ou PNG), décodée par la vue seulement quand elle change.
  var artwork: Data?
  var isPlaying: Bool
  var bundleIdentifier: String
  /// Durée du morceau en secondes, absente pour un direct.
  var duration: TimeInterval?
  /// Position à l'instant `timestamp` : le lecteur ne la renvoie qu'aux changements, la vue
  /// l'avance elle-même (voir `position(at:)`).
  var elapsed: TimeInterval?
  var timestamp: Date?
  var playbackRate: Double = 1

  /// Position estimée à `date`, bornée à la durée ; `nil` sans position connue.
  func position(at date: Date = .now) -> TimeInterval? {
    guard let elapsed else { return nil }
    var position = elapsed
    if isPlaying, let timestamp {
      position += max(0, date.timeIntervalSince(timestamp)) * playbackRate
    }
    if let duration { position = min(position, duration) }
    return max(0, position)
  }
}

/// Commande envoyée au lecteur actif. La valeur brute est l'identifiant `send` de l'adaptateur
/// MediaRemote.
nonisolated enum NowPlayingCommand: Int, Sendable {
  case togglePlayPause = 2
  case nextTrack = 4
  case previousTrack = 5
}

/// Reconstitue l'état courant à partir des lignes JSON de `mediaremote-adapter … stream`.
///
/// Le flux envoie des différences : une ligne `diff: false` remplace tout, une ligne `diff: true`
/// fusionne ses clés dans l'état précédent, et une clé à `null` le retire. Un état sans titre,
/// sans `playing` ou sans `bundleIdentifier` n'est pas exploitable : le résultat est alors `nil`.
nonisolated struct NowPlayingStreamParser {

  private var payload: [String: Any] = [:]

  /// Consomme une ligne. Retourne `nil` si elle est illisible (rien n'a changé), sinon le nouvel
  /// état — lui-même `nil` quand plus rien ne joue.
  mutating func ingest(line: Data) -> NowPlayingState?? {
    guard
      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let update = object["payload"] as? [String: Any]
    else { return nil }

    if object["diff"] as? Bool == true {
      for (key, value) in update {
        if value is NSNull { payload.removeValue(forKey: key) } else { payload[key] = value }
      }
    } else {
      payload = update.filter { !($0.value is NSNull) }
    }
    return .some(Self.state(from: payload))
  }

  /// Microsecondes (option `--micros` de l'adaptateur) vers secondes.
  private static func micros(_ value: Any?) -> TimeInterval? {
    (value as? NSNumber).map { $0.doubleValue / 1_000_000 }
  }

  private static func state(from payload: [String: Any]) -> NowPlayingState? {
    guard
      let title = payload["title"] as? String, !title.isEmpty,
      let isPlaying = payload["playing"] as? Bool,
      let bundleIdentifier = payload["bundleIdentifier"] as? String
    else { return nil }

    return NowPlayingState(
      title: title,
      artist: payload["artist"] as? String ?? "",
      album: payload["album"] as? String ?? "",
      artwork: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) },
      isPlaying: isPlaying,
      bundleIdentifier: bundleIdentifier,
      duration: micros(payload["durationMicros"]),
      elapsed: micros(payload["elapsedTimeMicros"]),
      timestamp: (payload["timestampEpochMicros"] as? NSNumber).map {
        Date(timeIntervalSince1970: $0.doubleValue / 1_000_000)
      },
      playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1)
  }
}
