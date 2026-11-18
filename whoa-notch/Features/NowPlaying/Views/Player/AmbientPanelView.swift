import SwiftUI

/// Panneau des ambiances, à la place du lecteur : retour, filet, puis les tuiles qui défilent
/// horizontalement et se calent sur une tuile.
struct AmbientPanelView: View {
  let model: NowPlayingPlayerModel

  var body: some View {
    GeometryReader { proxy in
      let side = max(0, proxy.size.height - 24)
      HStack(spacing: 14) {
        Button { model.showsAmbient = false } label: {
          PlayerRoundGlyph(symbol: "arrow.left", size: 34, glyph: 12)
        }
        .buttonStyle(PlayerPressStyle(scale: 0.88))
        .padding(6)
        .background(PlayerWell())
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Back to player")

        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 40)

        ScrollView(.horizontal) {
          LazyHStack(spacing: 12) {
            ForEach(AmbientSound.allCases) { sound in
              AmbientTile(
                sound: sound, side: side, isSelected: model.activeAmbient == sound
              ) { model.toggleAmbient(sound) }
            }
          }
          .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
        // Le bord droit s'efface : on devine qu'il reste des tuiles.
        .mask(
          LinearGradient(
            stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing)
        )
      }
      .padding(.horizontal, PlayerStyle.bleed)
      .padding(.vertical, 12)
    }
  }
}

/// Une tuile : appuyée ou survolée, son titre grossit et « Preview » apparaît dessous.
private struct AmbientTile: View {
  let sound: AmbientSound
  let side: CGFloat
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) { EmptyView() }
      .buttonStyle(
        AmbientTileStyle(sound: sound, side: side, isSelected: isSelected, isHovered: isHovered)
      )
      .onHover { isHovered = $0 }
      .accessibilityLabel(sound.title)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .help(isSelected ? "Stop \(sound.title)" : "Play \(sound.title)")
  }
}

private struct AmbientTileStyle: ButtonStyle {
  let sound: AmbientSound
  let side: CGFloat
  let isSelected: Bool
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    AmbientTileFace(
      sound: sound, side: side, isSelected: isSelected,
      emphasized: isHovered || configuration.isPressed
    )
    .scaleEffect(configuration.isPressed ? 0.95 : 1)
    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

private struct AmbientTileFace: View {
  let sound: AmbientSound
  let side: CGFloat
  let isSelected: Bool
  let emphasized: Bool

  private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

  var body: some View {
    fullBleed
      .frame(width: side, height: side)
    .contentShape(shape)
    .animation(.easeOut(duration: 0.16), value: emphasized)
    .animation(.easeOut(duration: 0.2), value: isSelected)
  }

  private var fullBleed: some View {
    ZStack {
      artwork
      LinearGradient(
        colors: [.black.opacity(0.05), .black.opacity(emphasized ? 0.55 : 0.4)], startPoint: .top,
        endPoint: .bottom)
      label(font: .system(size: 17, weight: .regular, design: .serif))
    }
    .clipShape(shape)
    .overlay(
      shape.strokeBorder(
        isSelected ? PlayerStyle.orange : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
    )
    .overlay(alignment: .topTrailing) { playingDot.padding(7) }
  }

  @ViewBuilder private var artwork: some View {
    if let image = NSImage(named: sound.imageName) {
      Image(nsImage: image).resizable().scaledToFill()
    } else {
      LinearGradient(colors: sound.placeholderColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private func label(font: Font) -> some View {
    VStack(spacing: 1) {
      Text(sound.title)
        .font(font)
        .foregroundStyle(.white)
        .scaleEffect(emphasized ? 1.1 : 1)
      if emphasized {
        Text("Preview")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.white.opacity(0.6))
          .transition(.opacity.combined(with: .offset(y: 3)))
      }
    }
    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
  }

  /// Point orange de l'ambiance qui joue.
  @ViewBuilder private var playingDot: some View {
    if isSelected {
      Circle()
        .fill(PlayerStyle.orange)
        .frame(width: 6, height: 6)
        .shadow(color: PlayerStyle.orange.opacity(0.9), radius: 3)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
  }
}
