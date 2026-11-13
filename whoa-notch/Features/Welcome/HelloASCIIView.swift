import SwiftUI

/// « hello » en caractères colorés. Pas de `trim` ici : chaque case a son instant d'apparition
/// (`HelloASCIIField.Cell.revealTime`), et la vue dessine celles que la plume a déjà croisées.
struct HelloASCIIView: View {

  let animated: Bool

  @State private var startDate = Date()
  @State private var finished: Bool

  static let size = CGSize(width: 360, height: 112)

  init(animated: Bool) {
    self.animated = animated
    _finished = State(initialValue: !animated)
  }

  var body: some View {
    TimelineView(.animation(paused: finished)) { timeline in
      let elapsed = animated ? timeline.date.timeIntervalSince(startDate) : .infinity
      ZStack {
        // Une copie floue dessous : la lueur de la plume, avec les couleurs de chaque case.
        canvas(elapsed: elapsed)
          .blur(radius: 3)
          .opacity(0.55)
        canvas(elapsed: elapsed)
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .accessibilityElement()
    .accessibilityLabel("hello")
    .task {
      guard animated else { return }
      startDate = Date()
      try? await Task.sleep(for: .seconds(HelloASCIIField.duration + 1))
      finished = true
    }
  }

  private func canvas(elapsed: TimeInterval) -> some View {
    Canvas { context, size in
      let cellWidth = size.width / CGFloat(HelloASCIIField.columns)
      let cellHeight = size.height / CGFloat(HelloASCIIField.rows)
      let font = Font.system(size: cellHeight * 1.35, weight: .bold, design: .monospaced)
      let glyphs = HelloASCIIField.glyphs.map { context.resolve(Text(String($0)).font(font)) }

      for cell in HelloASCIIField.shared.cells {
        let age = elapsed - cell.revealTime
        guard age > 0 else { break }  // triées par instant d'apparition
        let alpha = min(1, age / 0.18)
        // Fraîche, la case est presque blanche, comme la pointe de la plume ; elle prend
        // sa couleur en une demi-seconde.
        let glow = max(0, 1 - age / 0.5)
        var glyph = glyphs[cell.glyph]
        glyph.shading = .color(
          Color(
            red: cell.red + (1 - cell.red) * glow * 0.8,
            green: cell.green + (1 - cell.green) * glow * 0.8,
            blue: cell.blue + (1 - cell.blue) * glow * 0.8
          ).opacity(alpha))
        context.draw(
          glyph,
          at: CGPoint(
            x: (CGFloat(cell.column) + 0.5) * cellWidth,
            y: (CGFloat(cell.row) + 0.5) * cellHeight))
      }
    }
  }
}
