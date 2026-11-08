import AppKit

/// Couronne de graduations du cadran de volume : la barre de luminosité enroulée sur un cercle.
/// Comme elle, une `CALayer` indépendante par graduation, chacune portant son propre `shadow*` —
/// le glow reste strictement local au trait qui l'émet, jamais une lueur partagée façon anneau
/// de progression.
///
/// Ce n'est ni une `NSView` comme `BrightnessTicksView`, ni une sous-classe de `CALayer`, mais
/// un simple propriétaire de calques. Une sous-vue aurait son calque fils de celui de la vue, et
/// non du calque que l'apparition fait grandir depuis le curseur : elle resterait sur place
/// pendant que le reste du cadran jaillit. Une sous-classe de `CALayer`, elle, se heurterait à
/// l'isolation par défaut du module — tout y est sur l'acteur principal, là où les méthodes
/// héritées de Core Animation ne le sont pas.
final class VolumeTicksRing {

  /// Le calque à parenter dans le cadran. La couronne ne se met jamais en page toute seule :
  /// c'est la vue qui lui passe son cadre, au même moment que tout le reste.
  let layer = CALayer()

  private let tickCount: Int
  private var tickLayers: [CALayer] = []
  private var activeCount = 0
  private var palette: OverlayPalette

  init(tickCount: Int, palette: OverlayPalette) {
    self.tickCount = tickCount
    self.palette = palette

    tickLayers = (0..<tickCount).map { _ in
      let tick = CALayer()
      tick.shadowOffset = .zero
      tick.shadowColor = palette.activeTickColor
      tick.backgroundColor = palette.inactiveTickColor
      layer.addSublayer(tick)
      return tick
    }
  }

  /// Chaque graduation est posée sur le rayon qui lui revient puis tournée pour pointer vers
  /// le centre. La transaction est muselée : une mise en page arrive avant l'apparition, et
  /// les animations implicites feraient tourner toute la couronne sur place à chaque passage.
  func layout(in bounds: CGRect) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    layer.frame = bounds

    guard tickCount > 1, bounds.width > 0, bounds.height > 0 else {
      CATransaction.commit()
      return
    }

    let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    let outer = min(bounds.width, bounds.height) / 2 - VolumeDialGeometry.tickOuterInset

    for (index, tick) in tickLayers.enumerated() {
      let fraction = CGFloat(index) / CGFloat(tickCount - 1)
      let angle = VolumeDialGeometry.angle(forFraction: fraction)
      let length = VolumeDialGeometry.tickLength * lengthRatio(for: index)

      tick.bounds = CGRect(x: 0, y: 0, width: length, height: VolumeDialGeometry.tickThickness)
      tick.cornerRadius = VolumeDialGeometry.tickThickness / 2

      // Le trait est couché le long du rayon : son centre est donc posé à une demi-longueur
      // du bord, et non sur le bord lui-même, pour que son bout extérieur affleure la
      // marge voulue quelle que soit sa longueur.
      let radius = outer - length / 2
      tick.position = CGPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
      )
      tick.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
    }

    CATransaction.commit()
  }

  /// Alterne traits longs et courts, comme la barre de luminosité : c'est ce motif irrégulier
  /// qui donne à la couronne sa lecture de cadran plutôt que de pointillé.
  private func lengthRatio(for index: Int) -> CGFloat {
    index % 4 == 0 ? 1.0 : 0.55
  }

  func setActiveCount(_ newCount: Int, animated: Bool) {
    let clamped = max(0, min(tickCount, newCount))
    guard clamped != activeCount else { return }

    // Seules les graduations franchies changent d'état : repeindre toute la couronne à
    // chaque cran relancerait trente-six ressorts pour en bouger un.
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
