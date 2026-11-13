import CoreGraphics

/// Le tracé du curseur de luminosité : un arc de cercle, centré sur l'aperçu, qui en longe le bord
/// gauche du bas vers le haut. La valeur 0 est au pied de l'arc, 1 à son sommet.
///
/// Les angles sont en radians, dans le repère d'AppKit (axe y vers le haut, sens trigonométrique),
/// donc l'extrémité haute est plus petite que l'extrémité basse. Tout est pur : la vue ne fait que
/// dessiner ce que ces fonctions calculent.
nonisolated struct ArcSliderGeometry: Equatable {

  var center: CGPoint
  var radius: CGFloat

  /// Angle de la valeur 0, côté bas-gauche.
  var startAngle: CGFloat = 215 * .pi / 180
  /// Angle de la valeur 1, côté haut-gauche.
  var endAngle: CGFloat = 145 * .pi / 180

  /// Position sur l'arc d'une valeur, bornée à `0...1`.
  func point(for value: Double) -> CGPoint {
    let angle = startAngle + (endAngle - startAngle) * CGFloat(min(max(value, 0), 1))
    return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
  }

  /// Valeur d'un point quelconque, projeté sur l'arc : c'est l'angle qui compte, pas la
  /// distance au centre, donc le doigt peut s'écarter de la piste sans perdre le curseur.
  /// Au-delà des extrémités, la valeur reste collée à 0 ou à 1.
  func value(at point: CGPoint) -> Double {
    var angle = atan2(point.y - center.y, point.x - center.x)
    if angle < 0 { angle += 2 * .pi }
    let fraction = (angle - startAngle) / (endAngle - startAngle)
    return Double(min(max(fraction, 0), 1))
  }

  /// Dit si un point est assez près de la piste pour la saisir. L'écart en angle est toléré
  /// d'autant que l'écart en distance, pour que les deux bouts restent faciles à attraper.
  func isNear(_ point: CGPoint, tolerance: CGFloat) -> Bool {
    let distance = hypot(point.x - center.x, point.y - center.y)
    guard abs(distance - radius) <= tolerance else { return false }

    var angle = atan2(point.y - center.y, point.x - center.x)
    if angle < 0 { angle += 2 * .pi }
    let slack = tolerance / radius
    return angle >= endAngle - slack && angle <= startAngle + slack
  }
}

/// Ce que le curseur règle : la luminosité de l'**aperçu** seulement. L'écran n'est jamais touché.
nonisolated enum CameraBrightness {

  /// Valeur de repos : aperçu non retouché.
  static let neutral: Double = 0.5

  /// Opacité du voile noir (sous le neutre) et du voile blanc (au-dessus), à poser sur la
  /// vidéo. Les deux ne sont jamais non nuls ensemble. Les bornes laissent toujours un peu
  /// d'image : à 0 comme à 1 on doit pouvoir encore se voir pour remonter le curseur.
  static func overlay(for value: Double) -> (darkness: Double, lightness: Double) {
    let value = min(max(value, 0), 1)
    let offset = (value - neutral) * 2
    return offset < 0 ? (-offset * 0.8, 0) : (0, offset * 0.55)
  }
}
