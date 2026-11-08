import AppKit

/// Dessine les graduations de la barre de luminosité, une `CALayer` indépendante par
/// graduation. Chaque calque porte son propre `shadow*` : le glow est donc strictement
/// local à la graduation qui l'émet, jamais une lueur partagée façon progress bar.
final class BrightnessTicksView: NSView {

  private let tickCount: Int
  private var tickLayers: [CALayer] = []
  private var activeCount = 0
  private var palette: OverlayPalette

  init(tickCount: Int, palette: OverlayPalette) {
    self.tickCount = tickCount
    self.palette = palette
    super.init(frame: .zero)
    wantsLayer = true
    setUpTicks()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUpTicks() {
    tickLayers = (0..<tickCount).map { _ in
      let tick = CALayer()
      tick.shadowOffset = .zero
      tick.shadowColor = palette.activeTickColor
      layer?.addSublayer(tick)
      return tick
    }
  }

  override func layout() {
    super.layout()
    positionTicks()
  }

  private func positionTicks() {
    guard tickCount > 0 else { return }
    let spacing: CGFloat = 3
    let count = CGFloat(tickCount)
    let height = max(1.5, (bounds.height - spacing * (count - 1)) / count)

    for (index, tick) in tickLayers.enumerated() {
      let widthRatio = tickWidthRatio(for: index)
      let width = bounds.width * widthRatio
      let y = CGFloat(index) * (height + spacing)
      tick.frame = CGRect(x: (bounds.width - width) / 2, y: y, width: width, height: height)
      tick.cornerRadius = height / 2
    }
  }

  /// Alterne des traits longs et courts pour reproduire un motif de graduations irrégulier.
  private func tickWidthRatio(for index: Int) -> CGFloat {
    index % 4 == 0 ? 1.0 : 0.55
  }

  func setActiveCount(_ newCount: Int, animated: Bool) {
    let clamped = max(0, min(tickCount, newCount))
    guard clamped != activeCount else { return }

    let lower = min(activeCount, clamped)
    let upper = max(activeCount, clamped)
    activeCount = clamped

    for index in lower..<upper where tickLayers.indices.contains(index) {
      apply(active: index < clamped, to: tickLayers[index], animated: animated)
    }
  }

  func apply(palette: OverlayPalette) {
    self.palette = palette
    for (index, tick) in tickLayers.enumerated() {
      tick.shadowColor = palette.activeTickColor
      apply(active: index < activeCount, to: tick, animated: false)
    }
  }

  private func apply(active: Bool, to tick: CALayer, animated: Bool) {
    let color = active ? palette.activeTickColor : palette.inactiveTickColor
    let shadowOpacity: Float = active ? palette.glowOpacity : 0
    let shadowRadius: CGFloat = active ? palette.glowRadius : 0

    if animated {
      tick.springAnimate(keyPath: "backgroundColor", to: color)
      tick.springAnimate(keyPath: "shadowOpacity", to: shadowOpacity)
      tick.springAnimate(keyPath: "shadowRadius", to: shadowRadius)
    } else {
      tick.backgroundColor = color
      tick.shadowOpacity = shadowOpacity
      tick.shadowRadius = shadowRadius
    }
  }
}
