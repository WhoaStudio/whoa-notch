import SwiftUI

/// Carte noire du morceau : pochette portant l'icône de la source, titre, artiste, progression
/// et visualiseur. Un balayage horizontal (souris ou deux doigts) change de piste, et le morceau
/// suivant arrive du côté d'où l'on vient.
struct PlayerTrackCard: View {
  let model: NowPlayingPlayerModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

  var body: some View {
    ZStack {
      content
        .id(model.trackIdentity)
        .transition(trackTransition)
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
      value: model.trackIdentity
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(shape.fill(Color.black))
    .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    .clipShape(shape)
    .background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: PlayerFramesKey.self,
          value: PlayerFrames(card: proxy.frame(in: .named(PlayerStyle.space))))
      }
    )
    .gesture(swipe)
  }

  private var trackTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    let shift = model.skipDirection * 28
    return .asymmetric(
      insertion: .offset(x: shift).combined(with: .opacity),
      removal: .offset(x: -shift).combined(with: .opacity))
  }

  private var content: some View {
    GeometryReader { proxy in
      let art = max(0, proxy.size.height - 16)
      HStack(spacing: 10) {
        PlayerArtwork(artwork: model.state?.artwork, bundleIdentifier: model.state?.bundleIdentifier)
          .frame(width: art, height: art)
          .opacity(model.sharedHidden ? 0 : 1)
          .background(
            GeometryReader { art in
              Color.clear.preference(
                key: PlayerFramesKey.self,
                value: PlayerFrames(artwork: art.frame(in: .named(PlayerStyle.space))))
            })
        texts
      }
      .padding(8)
    }
    .offset(x: model.swipeOffset)
    .opacity(max(0.4, 1 - abs(model.swipeOffset) / 160))
  }

  private var texts: some View {
    let state = model.state
    // L'artiste seul : l'album allonge la ligne pour rien, il reste dans l'infobulle.
    let artist = state?.artist ?? ""
    let subtitle = artist.isEmpty ? (state?.album ?? "") : artist
    let tooltip = [state?.title ?? "", artist, state?.album ?? ""].filter { !$0.isEmpty }
      .joined(separator: "\n")
    return VStack(alignment: .leading, spacing: 2) {
      // Le titre a toute la largeur : le visualiseur est passé sur la ligne de l'artiste.
      Text(state?.title ?? "Nothing playing")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)
      HStack(spacing: 8) {
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        PlayerVisualizer(isAnimating: model.isPlaying)
          .opacity(model.sharedHidden ? 0 : 1)
          .background(
            GeometryReader { viz in
              Color.clear.preference(
                key: PlayerFramesKey.self,
                value: PlayerFrames(visualizer: viz.frame(in: .named(PlayerStyle.space))))
            })
      }
      // La progression n'apparaît que si la carte a la hauteur de la loger.
      ViewThatFits(in: .vertical) {
        if let duration = state?.duration, duration > 0 {
          PlayerProgress(model: model, duration: duration).padding(.top, 4)
        }
        Color.clear.frame(height: 0)
      }
    }
    .help(tooltip)
  }

  private var swipe: some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { drag in
        guard model.state != nil, abs(drag.translation.width) > abs(drag.translation.height)
        else { return }
        model.follow(rawOffset: drag.translation.width)
      }
      .onEnded { drag in
        let width = drag.translation.width
        let committed = abs(width) >= TabSwipeTracker.commitThreshold
        model.settleSwipe(committed ? (width < 0 ? .next : .previous) : nil)
      }
  }
}

/// Temps écoulé, barre qu'on peut faire glisser, temps restant.
struct PlayerProgress: View {
  let model: NowPlayingPlayerModel
  let duration: TimeInterval

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.5, paused: !model.isPlaying || model.scrubFraction != nil)) {
      context in
      let position =
        model.scrubFraction.map { $0 * duration } ?? model.state?.position(at: context.date) ?? 0
      HStack(spacing: 6) {
        time(NowPlayingClock.format(position))
        bar(fraction: duration > 0 ? position / duration : 0)
        time(NowPlayingClock.formatRemaining(duration - position))
      }
    }
  }

  private func time(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 10).monospacedDigit())
      .foregroundStyle(.white.opacity(0.5))
      .lineLimit(1)
      .fixedSize()
  }

  private func bar(fraction: Double) -> some View {
    GeometryReader { proxy in
      let dragging = model.scrubFraction != nil
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.15))
        Capsule()
          .fill(Color.white.opacity(model.isPlaying ? 0.9 : 0.5))
          .frame(width: proxy.size.width * min(1, max(0, fraction)))
      }
      .frame(height: dragging ? 5 : 3)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .animation(.easeOut(duration: 0.12), value: dragging)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            model.scrubFraction = min(1, max(0, drag.location.x / max(1, proxy.size.width)))
          }
          .onEnded { drag in
            model.commitScrub(drag.location.x / max(1, proxy.size.width))
          }
      )
    }
    .frame(height: 12)
    .accessibilityLabel("Playback position")
  }
}
