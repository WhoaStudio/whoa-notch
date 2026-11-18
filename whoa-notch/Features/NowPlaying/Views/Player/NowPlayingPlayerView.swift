import SwiftUI

nonisolated enum PlayerStyle {
  /// Orange du bouton lecture et des points de volume.
  static let orange = Color(red: 0.93, green: 0.42, blue: 0.17)
  static let space = "nowPlayingPlayer"
  /// Débord du fond du lecteur de chaque côté du contenu : les commandes tombent ainsi sur les
  /// mêmes bords que « Nov », la liste des événements et le glyphe de l'engrenage, et le fond
  /// reste dans l'air de `contentAirX`, sans toucher le flanc du panneau.
  static let bleed: CGFloat = 8
}

/// Lecteur de l'onglet Global : précédent, grand bouton lecture, suivant, carte du morceau,
/// aléatoire et bouton de volume. Une colonne « Playing Next » s'ouvre à droite quand la source
/// sait donner la suite, et le lecteur se resserre à gauche.
struct NowPlayingPlayerView: View {
  let model: NowPlayingPlayerModel

  /// Part de la largeur gardée par le lecteur quand la colonne de droite est ouverte.
  private let playerShare: CGFloat = 0.58

  var body: some View {
    GeometryReader { proxy in
      let hasQueue = !model.queue.isEmpty
      let playerWidth = hasQueue ? (proxy.size.width * playerShare).rounded() : proxy.size.width
      HStack(spacing: 0) {
        PlayerControls(model: model)
          .frame(width: playerWidth)
        if hasQueue {
          PlayerQueueColumn(items: model.queue)
            .transition(.opacity.combined(with: .offset(x: 8)))
        }
      }
      .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasQueue)
    }
    .coordinateSpace(name: PlayerStyle.space)
    .onPreferenceChange(PlayerFramesKey.self) { model.mergeFrames($0) }
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(white: 0.115), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
          Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    )
    .environment(\.colorScheme, .dark)
  }
}

/// Le lecteur ou, à sa place, le panneau des ambiances : le lecteur sort par la droite et le
/// panneau entre par la gauche ; le retour refait le même chemin en sens inverse.
private struct PlayerControls: View {
  let model: NowPlayingPlayerModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if model.showsAmbient {
        AmbientPanelView(model: model)
          .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
      } else {
        controls
          .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
      }
    }
    // Rogné sur les côtés pendant le glissé, mais pas en haut ni en bas : la lueur du bouton
    // lecture déborde.
    .mask(Rectangle().padding(.vertical, -24))
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 1),
      value: model.showsAmbient)
  }

  private var controls: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      HStack(spacing: 16) {
        transport
        PlayerTrackCard(model: model)
          .frame(minWidth: 150, maxWidth: .infinity)
        ambientTrigger
        if width >= 600 {
          shuffle
          Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 40)
        }
        if width >= 500 {
          PlayerVolumeKnob(
            value: Binding(get: { model.volume }, set: { model.setVolume($0) }),
            size: width >= 600 ? 62 : 52)
        }
      }
      .padding(.horizontal, PlayerStyle.bleed)
      .padding(.vertical, 12)
    }
  }

  private var transport: some View {
    HStack(spacing: 8) {
      Button { model.skip(.previousTrack) } label: {
        PlayerRoundGlyph(symbol: "backward.fill", size: 34, glyph: 11)
      }
      .buttonStyle(PlayerPressStyle(scale: 0.88))
      .padding(6)
      .background(PlayerWell())
      .accessibilityLabel("Previous")

      Button { model.togglePlayPause() } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 48, height: 48)
          .background(
            Circle().fill(
              RadialGradient(
                colors: [
                  Color(red: 1.0, green: 0.58, blue: 0.3), PlayerStyle.orange,
                  Color(red: 0.78, green: 0.3, blue: 0.1),
                ], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 2, endRadius: 46))
          )
          // Reflet doux sur le haut du bouton.
          .overlay(
            Circle().fill(
              LinearGradient(
                colors: [Color.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
            ).padding(2)
          )
          .overlay(
            Circle().strokeBorder(
              LinearGradient(
                colors: [Color.white.opacity(0.55), Color(red: 0.5, green: 0.15, blue: 0.0).opacity(0.5)],
                startPoint: .top, endPoint: .bottom), lineWidth: 1)
          )
          .shadow(color: PlayerStyle.orange.opacity(0.55), radius: 12, y: 2)
      }
      .buttonStyle(PlayerPressStyle(scale: 0.9))
      .padding(7)
      .background(PlayerWell())
      .accessibilityLabel(model.isPlaying ? "Pause" : "Play")

      Button { model.skip(.nextTrack) } label: {
        PlayerRoundGlyph(symbol: "forward.fill", size: 34, glyph: 11)
      }
      .buttonStyle(PlayerPressStyle(scale: 0.88))
      .padding(6)
      .background(PlayerWell())
      .accessibilityLabel("Next")
    }
  }

  /// Ouvre le panneau des ambiances ; orange tant qu'une ambiance joue.
  private var ambientTrigger: some View {
    Button { model.showsAmbient = true } label: {
      PlayerRoundGlyph(
        symbol: "wind", size: 34, glyph: 12,
        tint: model.activeAmbient == nil ? .white : PlayerStyle.orange)
    }
    .buttonStyle(PlayerPressStyle(scale: 0.88))
    .padding(6)
    .background(PlayerWell())
    .accessibilityLabel("Ambient sounds")
    .help(model.activeAmbient.map { "Ambient: \($0.title)" } ?? "Ambient sounds")
  }

  /// Dessiné comme sur la maquette, mais éteint : la couche MediaRemote n'a pas de commande
  /// d'aléatoire (voir `NowPlayingCommand`).
  private var shuffle: some View {
    PlayerRoundGlyph(symbol: "shuffle", size: 34, glyph: 12)
      .opacity(0.35)
      .help("Shuffle isn't available yet")
      .accessibilityLabel("Shuffle")
      .accessibilityHint("Not available")
      .accessibilityAddTraits(.isButton)
  }
}

/// Face d'un bouton sombre : dégradé léger, glyphe blanc et liseré de lumière en haut.
struct PlayerRoundGlyph: View {
  let symbol: String
  let size: CGFloat
  let glyph: CGFloat
  var tint: Color = .white

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: glyph, weight: .bold))
      .foregroundStyle(tint)
      .shadow(color: tint.opacity(0.35), radius: 3)
      .frame(width: size, height: size)
      .background(
        Circle().fill(
          LinearGradient(
            colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
      )
      .overlay(
        Circle().strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.03)], startPoint: .top,
            endPoint: .bottom), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
  }
}

/// Cuvette noire et creuse dans laquelle un bouton est posé : l'ombre est en haut, la lumière
/// accroche le bord du bas.
struct PlayerWell: View {
  var body: some View {
    Circle()
      .fill(Color.black)
      .overlay(
        Circle().stroke(Color.white.opacity(0.05), lineWidth: 7).blur(radius: 3.5)
          .clipShape(Circle())
      )
      .overlay(
        Circle().strokeBorder(
          LinearGradient(
            colors: [Color.black, Color.white.opacity(0.14)], startPoint: .top, endPoint: .bottom),
          lineWidth: 1.5)
      )
  }
}

/// Le bouton rétrécit à l'appui et revient avec un ressort.
struct PlayerPressStyle: ButtonStyle {
  let scale: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
  }
}

#Preview("Player") {
  let model = NowPlayingPlayerModel()
  model.state = NowPlayingState(
    title: "Gasoline", artist: "Audioslave", isPlaying: true,
    bundleIdentifier: "com.spotify.client", duration: 279, elapsed: 83, timestamp: .now)
  model.volume = 0.7
  return NowPlayingPlayerView(model: model)
    .frame(width: 640, height: 96)
    .padding(24)
    .background(Color.black)
}

#Preview("Ambient panel") {
  let model = NowPlayingPlayerModel()
  model.state = NowPlayingState(
    title: "Gasoline", artist: "Audioslave", isPlaying: true,
    bundleIdentifier: "com.spotify.client", duration: 279, elapsed: 83, timestamp: .now)
  model.volume = 0.7
  model.showsAmbient = true
  model.activeAmbient = .study
  return NowPlayingPlayerView(model: model)
    .frame(width: 640, height: 96)
    .padding(24)
    .background(Color.black)
}
