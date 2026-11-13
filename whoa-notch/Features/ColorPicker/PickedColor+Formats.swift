import AppKit

/// L'écriture que la copie et le champ de valeur utilisent.
nonisolated enum ColorFormat: String, Codable, CaseIterable, Sendable {
  case hex, rgb, hsl

  var title: String { rawValue.uppercased() }
}

/// Écritures et mesures dérivées d'une couleur prélevée : le prélèvement et les trois chaînes de
/// `PickedColor` ne changent pas.
nonisolated extension PickedColor {

  func string(for format: ColorFormat) -> String {
    switch format {
    case .hex: hexString
    case .rgb: rgbString
    case .hsl: hslString
    }
  }

  private var unitComponents: (r: Double, g: Double, b: Double) {
    (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
  }

  private func formatted(_ value: Double) -> String { String(format: "%.3f", value) }

  /// `Color(red: 0.039, green: 0.435, blue: 0.910)`, à coller dans du SwiftUI.
  var swiftUICode: String {
    let c = unitComponents
    return "Color(red: \(formatted(c.r)), green: \(formatted(c.g)), blue: \(formatted(c.b)))"
  }

  /// `NSColor(srgbRed: …, green: …, blue: …, alpha: 1)`.
  var nsColorCode: String {
    let c = unitComponents
    return
      "NSColor(srgbRed: \(formatted(c.r)), green: \(formatted(c.g)), blue: \(formatted(c.b)), alpha: 1)"
  }

  /// Teinte (0–360°), saturation et luminosité (0–1).
  var hsb: (hue: Double, saturation: Double, brightness: Double) {
    let c = unitComponents
    let high = max(c.r, c.g, c.b)
    let delta = high - min(c.r, c.g, c.b)
    var hue = 0.0
    if delta > 0 {
      switch high {
      case c.r: hue = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
      case c.g: hue = 60 * ((c.b - c.r) / delta + 2)
      default: hue = 60 * ((c.r - c.g) / delta + 4)
      }
      if hue < 0 { hue += 360 }
    }
    return (hue, high > 0 ? delta / high : 0, high)
  }

  /// La couleur à `hue` (0–360°, ramenée dans le cercle), `saturation` et `brightness` (bornées
  /// à 0–1), en sRGB comme le reste.
  init(hue: Double, saturation: Double, brightness: Double) {
    var wrapped = hue.truncatingRemainder(dividingBy: 360)
    if wrapped < 0 { wrapped += 360 }
    let s = min(max(saturation, 0), 1)
    let v = min(max(brightness, 0), 1)
    let chroma = v * s
    let x = chroma * (1 - abs((wrapped / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = v - chroma
    let (r, g, b): (Double, Double, Double)
    switch Int(wrapped / 60) {
    case 0: (r, g, b) = (chroma, x, 0)
    case 1: (r, g, b) = (x, chroma, 0)
    case 2: (r, g, b) = (0, chroma, x)
    case 3: (r, g, b) = (0, x, chroma)
    case 4: (r, g, b) = (x, 0, chroma)
    default: (r, g, b) = (chroma, 0, x)
    }
    func byte(_ value: Double) -> UInt8 { UInt8(min(max(((value + m) * 255).rounded(), 0), 255)) }
    self.init(red: byte(r), green: byte(g), blue: byte(b))
  }

  /// Luminance relative au sens de WCAG 2.
  var relativeLuminance: Double {
    func linear(_ value: UInt8) -> Double {
      let c = Double(value) / 255
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// Rapport de contraste WCAG avec le blanc ou le noir, celui qui lit le mieux, et la mention
  /// atteinte (AAA ≥ 7, AA ≥ 4,5, AA Large ≥ 3).
  var contrast: (ratio: Double, onWhite: Bool, grade: String) {
    let l = relativeLuminance
    let white = 1.05 / (l + 0.05)
    let black = (l + 0.05) / 0.05
    let onWhite = white >= black
    let ratio = onWhite ? white : black
    let grade = ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "AA Large" : "Fail"
    return (ratio, onWhite, grade)
  }
}
