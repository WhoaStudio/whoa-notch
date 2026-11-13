import CoreGraphics
import Foundation

/// Zoom numérique de l'aperçu Mirror (les Mac n'ont pas de zoom optique), entre 1× et 3×.
///
/// Pendant un geste, la valeur brute peut sortir de l'intervalle : l'image suit le doigt avec une
/// résistance croissante (`displayed`), puis revient au ressort sur la borne au relâchement
/// (`settle()`). C'est ce qui fait « sentir » la butée.
nonisolated struct MirrorZoom: Equatable {

  static let range: ClosedRange<Double> = 1...3

  /// Distance maximale dont l'image peut dépasser une borne, en facteur de zoom. Plus courte en
  /// bas : sous 1×, l'image rétrécit et laisse voir le fond du cercle.
  private static let overshootBelow = 0.05
  private static let overshootAbove = 0.25

  /// Garde-fous de la valeur brute : un geste emballé ne s'éloigne pas indéfiniment.
  private static let rawBounds: ClosedRange<Double> = 0.5...8

  private(set) var raw: Double = 1

  /// Facteur à poser sur l'image : la valeur brute, freinée au-delà des bornes.
  var displayed: Double {
    let low = Self.range.lowerBound
    let high = Self.range.upperBound
    if raw > high { return high + Self.resist(raw - high, limit: Self.overshootAbove) }
    if raw < low { return low - Self.resist(low - raw, limit: Self.overshootBelow) }
    return raw
  }

  /// Valeur de repos la plus proche.
  var settled: Double { min(max(raw, Self.range.lowerBound), Self.range.upperBound) }

  var isOutOfRange: Bool { raw != settled }
  var isZoomed: Bool { settled > Self.range.lowerBound + 0.01 }

  /// Pincement : `magnification` est celle de `NSEvent.magnification` (0,1 = +10 %).
  mutating func magnify(by magnification: Double) {
    set(raw * (1 + magnification))
  }

  /// Molette ou défilement à deux doigts : `delta` en points, vers le haut = rapprocher.
  mutating func scroll(by delta: Double) {
    set(raw * exp(delta * 0.012))
  }

  /// Fin de geste : la valeur brute revient dans l'intervalle.
  mutating func settle() { raw = settled }

  mutating func reset() { raw = Self.range.lowerBound }

  private mutating func set(_ value: Double) {
    raw = min(max(value, Self.rawBounds.lowerBound), Self.rawBounds.upperBound)
  }

  /// Courbe de résistance : proche de l'identité au départ, plafonnée à `limit`.
  private static func resist(_ overshoot: Double, limit: Double) -> Double {
    limit * (1 - exp(-overshoot / limit))
  }

  /// Rectangle de l'image caméra que montre le cercle : un carré centré, de plus en plus petit
  /// quand on zoome. Sert à recadrer l'image copiée comme on la voit.
  static func visibleRect(imageSize: CGSize, zoom: Double) -> CGRect {
    let side = min(imageSize.width, imageSize.height) / max(zoom, 1)
    return CGRect(
      x: (imageSize.width - side) / 2,
      y: (imageSize.height - side) / 2,
      width: side,
      height: side
    )
  }
}
