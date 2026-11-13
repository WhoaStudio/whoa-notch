import Foundation

/// Mise en forme des temps du lecteur : `m:ss` jusqu'à une heure, `h:mm:ss` au-delà (un
/// podcast ou une longue vidéo ne doit pas s'afficher « 174:42 »).
nonisolated enum NowPlayingClock {

  static func format(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  /// Temps restant, précédé d'un signe moins ; jamais « -0:00 » : à zéro, il reste « 0:00 ».
  static func formatRemaining(_ seconds: TimeInterval) -> String {
    let text = format(seconds)
    return text == "0:00" ? text : "-" + text
  }
}
