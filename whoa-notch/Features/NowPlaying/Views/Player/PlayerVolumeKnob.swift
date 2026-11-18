import SwiftUI

/// Bouton de volume : on le tourne en glissant autour de son centre, et les points orange de
/// l'arc s'allument jusqu'au niveau choisi. Métal brossé, cuvette creuse et reflet : le relief
/// vient des couches, seul le métal et le repère tournent.
struct PlayerVolumeKnob: View {
  @Binding var value: Double
  let size: CGFloat

  @State private var lastAngle: Double?

  private let dotCount = 13
  /// Ouverture de l'arc en degrés, centrée sur le haut ; le bas reste libre.
  private let sweep: Double = 270

  var body: some View {
    let knobSize = size * 0.62
    let radius = size / 2 - 5
    let turn = Angle.degrees(-sweep / 2 + sweep * value)
    ZStack {
      PlayerWell()
      ForEach(0..<dotCount, id: \.self) { index in
        let fraction = Double(index) / Double(dotCount - 1)
        let lit = value > 0 && fraction <= value + 0.0001
        Circle()
          .fill(lit ? PlayerStyle.orange : Color.white.opacity(0.16))
          .frame(width: 3, height: 3)
          .shadow(color: lit ? PlayerStyle.orange.opacity(0.9) : .clear, radius: 3)
          .offset(y: -radius)
          .rotationEffect(.degrees(-sweep / 2 + sweep * fraction))
          .animation(.easeOut(duration: 0.12), value: lit)
      }
      knob(size: knobSize, turn: turn)
    }
    .frame(width: size, height: size)
    .contentShape(Circle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { drag in
          let dx = drag.location.x - size / 2
          let dy = drag.location.y - size / 2
          // Trop près du centre, l'angle n'a plus de sens.
          guard hypot(dx, dy) > 4 else { return }
          let angle = atan2(dx, -dy) * 180 / .pi
          if let lastAngle {
            var delta = angle - lastAngle
            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
            value = min(1, max(0, value + delta / sweep))
          }
          lastAngle = angle
        }
        .onEnded { _ in lastAngle = nil }
    )
    .accessibilityElement()
    .accessibilityLabel("Volume")
    .accessibilityValue("\(Int((value * 100).rounded())) %")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: value = min(1, value + 0.0625)
      case .decrement: value = max(0, value - 0.0625)
      @unknown default: break
      }
    }
  }

  private func knob(size knobSize: CGFloat, turn: Angle) -> some View {
    ZStack {
      // Ombre portée : elle ne tourne pas avec le bouton.
      Circle().fill(Color.black)
        .shadow(color: .black.opacity(0.9), radius: 6, y: 4)

      // Métal brossé : le reflet en cône tourne avec le bouton.
      Circle().fill(
        AngularGradient(
          colors: [
            Color(white: 0.34), Color(white: 0.08), Color(white: 0.28), Color(white: 0.06),
            Color(white: 0.34),
          ], center: .center)
      )
      .rotationEffect(turn)

      // Biseau : lumière en haut, ombre en bas.
      Circle().strokeBorder(
        LinearGradient(
          colors: [Color.white.opacity(0.55), Color.black.opacity(0.7)], startPoint: .top,
          endPoint: .bottom), lineWidth: 1.5)

      // Cuvette du dessus, légèrement creusée.
      Circle()
        .fill(
          LinearGradient(
            colors: [Color(white: 0.05), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(
          Circle().strokeBorder(
            LinearGradient(
              colors: [Color.black.opacity(0.8), Color.white.opacity(0.12)], startPoint: .top,
              endPoint: .bottom), lineWidth: 1)
        )
        .padding(knobSize * 0.13)

      // Repère orange, lumineux.
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(PlayerStyle.orange)
        .frame(width: 3, height: knobSize * 0.2)
        .shadow(color: PlayerStyle.orange.opacity(0.9), radius: 3)
        .offset(y: -(knobSize / 2 - knobSize * 0.2))
        .rotationEffect(turn)

      // Reflet spéculaire fixe, en haut à gauche.
      Circle().fill(
        RadialGradient(
          colors: [Color.white.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.2),
          startRadius: 0, endRadius: knobSize * 0.6)
      )
      .allowsHitTesting(false)
    }
    .frame(width: knobSize, height: knobSize)
  }
}
