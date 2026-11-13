import Foundation

/// Source des titres à venir. MediaRemote ne les donne pas : chaque application qui sait les
/// fournir a donc la sienne (Apple Musique, Spotify). Derrière un protocole, comme les autres
/// sources externes — `MockPlayingNextProvider` permet de vérifier la colonne sans lecteur.
protocol PlayingNextProviding: Sendable {
  /// Cette source sait-elle lire la file de l'application qui joue ?
  func supports(bundleIdentifier: String) -> Bool

  /// Les `limit` prochains titres ; vide si la file est inconnue, indisponible ou non fiable.
  func upcoming(limit: Int) async -> [QueueItem]
}

/// `--playing-next=mock` : trois titres fixes pour n'importe quelle application.
nonisolated struct MockPlayingNextProvider: PlayingNextProviding {

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockPlayingNextProvider?
  {
    arguments.contains("--playing-next=mock") ? MockPlayingNextProvider() : nil
  }

  func supports(bundleIdentifier: String) -> Bool { true }

  func upcoming(limit: Int) async -> [QueueItem] {
    Array(
      [
        QueueItem(title: "The Temple", artist: "Phuture Noize", artwork: nil),
        QueueItem(
          title: "Lotje (Lil Kleine Remix)", artist: "Roeland Beelen & Lil Kleine", artwork: nil),
        QueueItem(title: "Geen Nummer 2", artist: "Lil Kleine", artwork: nil),
      ].prefix(limit))
  }
}
