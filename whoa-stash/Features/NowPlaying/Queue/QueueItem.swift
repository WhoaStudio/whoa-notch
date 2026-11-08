import Foundation

/// Un titre à venir, tel qu'il s'affiche dans la colonne « Playing Next ».
nonisolated struct QueueItem: Equatable, Sendable {
  var title: String
  var artist: String
  /// Image brute (JPEG ou PNG) ; absente tant qu'elle n'est pas arrivée ou si la source n'en a pas.
  var artwork: Data?
}
