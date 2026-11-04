import AppKit

/// Une couleur prélevée à l'écran, en sRGB 8 bits, avec les trois écritures que l'onglet Color
/// affiche et copie.
nonisolated struct PickedColor: Equatable, Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    /// Bleu de l'aperçu de départ, tant qu'aucune couleur n'a été prélevée.
    static let placeholder = PickedColor(red: 10, green: 111, blue: 232)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#RRGGBB`, `#` facultatif ; `nil` si la chaîne n'est pas de l'hexadécimal sur six chiffres.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// `nil` si la couleur ne se convertit pas en sRGB (couleur de motif, par exemple).
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt8 { UInt8(min(max((component * 255).rounded(), 0), 255)) }
        self.init(red: byte(rgb.redComponent), green: byte(rgb.greenComponent), blue: byte(rgb.blueComponent))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    var hexString: String { String(format: "#%02X%02X%02X", red, green, blue) }

    var rgbString: String { "rgb(\(red), \(green), \(blue))" }

    var hslString: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low
        let lightness = (high + low) / 2
        var hue = 0.0
        var saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch high {
            case r: hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = 60 * ((b - r) / delta + 2)
            default: hue = 60 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        let degrees = Int(hue.rounded()) % 360
        return "hsl(\(degrees), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }
}
