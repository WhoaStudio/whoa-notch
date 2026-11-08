import CoreGraphics
import Foundation

/// Géométrie pure du menu radial : où poser le disque et quel secteur vise un déplacement.
/// Les éléments se suivent dans le sens horaire à partir du haut ; coordonnées AppKit (y vers le haut).
enum RadialMenuGeometry {

  static let diameter: CGFloat = 300
  static let centerDiameter: CGFloat = 132
  /// Sous cette distance de l'ancre, aucun élément n'est visé : relâcher là annule.
  static let deadZone: CGFloat = 24

  /// Centre du disque : le curseur, ramené pour que le disque entier reste dans `visibleFrame`.
  static func center(
    forCursor cursor: CGPoint, diameter: CGFloat = diameter, in visibleFrame: CGRect
  ) -> CGPoint {
    let radius = diameter / 2
    return CGPoint(
      x: clamp(cursor.x, visibleFrame.minX + radius, visibleFrame.maxX - radius),
      y: clamp(cursor.y, visibleFrame.minY + radius, visibleFrame.maxY - radius))
  }

  /// Angle du milieu du secteur `index`, en radians AppKit (0 = droite, sens trigonométrique).
  static func angle(ofItem index: Int, count: Int) -> CGFloat {
    .pi / 2 - CGFloat(index) * 2 * .pi / CGFloat(count)
  }

  /// Secteur visé par le déplacement `offset` depuis l'ancre ; `nil` dans la zone morte.
  static func index(forOffset offset: CGVector, count: Int) -> Int? {
    guard count > 0, hypot(offset.dx, offset.dy) >= deadZone else { return nil }
    let step = 2 * CGFloat.pi / CGFloat(count)
    var clockwiseFromTop = .pi / 2 - atan2(offset.dy, offset.dx)
    clockwiseFromTop = clockwiseFromTop.truncatingRemainder(dividingBy: 2 * .pi)
    if clockwiseFromTop < 0 { clockwiseFromTop += 2 * .pi }
    return Int((clockwiseFromTop + step / 2) / step) % count
  }

  private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    // Écran plus petit que le disque : on le centre plutôt que de laisser min > max.
    guard low <= high else { return (low + high) / 2 }
    return min(max(value, low), high)
  }
}
