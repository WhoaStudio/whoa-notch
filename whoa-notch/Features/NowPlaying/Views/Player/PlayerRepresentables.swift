import SwiftUI

/// Pochette AppKit réutilisée telle quelle : elle porte déjà l'icône de la source (Spotify,
/// Musique, navigateur) et le fond flouté des pochettes non carrées.
struct PlayerArtwork: NSViewRepresentable {
  let artwork: Data?
  let bundleIdentifier: String?

  func makeNSView(context: Context) -> ArtworkView {
    let view = ArtworkView()
    view.cornerRadius = 11
    view.badgeScale = 0.4
    view.badgeInset = -6
    return view
  }

  func updateNSView(_ view: ArtworkView, context: Context) {
    view.setArtwork(artwork)
    if let bundleIdentifier {
      view.setSource(bundleIdentifier: bundleIdentifier)
    } else {
      view.clearSource()
    }
  }
}

/// Les quatre barres du visualiseur AppKit.
struct PlayerVisualizer: NSViewRepresentable {
  let isAnimating: Bool

  func makeNSView(context: Context) -> AudioVisualizerView {
    let view = AudioVisualizerView()
    view.tint = .white.withAlphaComponent(0.45)
    return view
  }

  func updateNSView(_ view: AudioVisualizerView, context: Context) {
    view.setAnimating(isAnimating)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: AudioVisualizerView, context: Context)
    -> CGSize?
  {
    nsView.intrinsicContentSize
  }
}
