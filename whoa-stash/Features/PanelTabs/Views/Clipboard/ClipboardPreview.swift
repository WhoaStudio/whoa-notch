import AppKit

/// Ce que la carte montre d'un texte copié, sans toucher à ce qui est stocké ni recopié : le
/// nettoyage n'est que pour l'affichage. Fonctions pures, testées.
enum ClipboardPreview {

  /// Longueur maximale gardée pour l'aperçu : un texte de plusieurs Mo ne passe pas par le label.
  static let maxDisplayLength = 400

  /// Texte d'aperçu : fins de ligne unifiées, lignes vides retirées, retrait commun enlevé,
  /// tabulations ramenées à deux espaces. La première ligne est donc toujours du texte visible.
  static func displayText(_ raw: String) -> String {
    let head = String(raw.prefix(maxDisplayLength * 4))
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\t", with: "  ")
    let lines = head.split(separator: "\n", omittingEmptySubsequences: true)
      .map { String($0).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
      .filter { !$0.isEmpty }
    let indent = lines.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
    let text = lines.map { String($0.dropFirst(indent)) }.joined(separator: "\n")
    return String(text.prefix(maxDisplayLength))
  }

  /// Vrai pour du code ou des données en colonnes : l'aperçu passe alors en chasse fixe.
  static func looksLikeCode(_ display: String) -> Bool {
    guard display.contains("\n") else { return false }
    let markers = ["{", "}", ";", "=>", "</", "func ", "def ", "import ", "const ", "let "]
    return markers.contains { display.contains($0) }
      || display.split(separator: "\n").contains { $0.hasPrefix("  ") }
  }

  /// Une couleur quand le texte entier n'est que cela : `#RGB`, `#RRGGBB`, `#RRGGBBAA` ou
  /// `rgb(r, g, b)`.
  struct ColorValue: Equatable {
    let color: NSColor
    /// « #RRGGBB » en capitales, ou le texte `rgb(…)` tel que copié.
    let label: String

    /// Encre lisible sur cette couleur.
    var ink: NSColor {
      let rgb = color.usingColorSpace(.sRGB) ?? color
      let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
        + 0.0722 * rgb.blueComponent
      return luminance > 0.6 ? .black : .white
    }
  }

  /// Groupes capturés si `pattern` couvre tout `text`, sinon `nil`.
  private static func captures(_ pattern: String, in text: String) -> [String]? {
    guard
      let expression = try? NSRegularExpression(pattern: "^" + pattern + "$"),
      let match = expression.firstMatch(
        in: text, range: NSRange(text.startIndex..., in: text)),
      match.numberOfRanges > 1
    else { return nil }
    return (1..<match.numberOfRanges).compactMap {
      Range(match.range(at: $0), in: text).map { String(text[$0]) }
    }
  }

  static func colorValue(in text: String) -> ColorValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= 40 else { return nil }

    if let groups = captures(#"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})"#, in: trimmed) {
      var digits = groups[0]
      if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
      guard let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
      let alpha =
        digits.count == 8 ? (Double(UInt8(digits.suffix(2), radix: 16) ?? 255) / 255) : 1
      return ColorValue(
        color: NSColor(
          srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255, alpha: alpha),
        label: "#" + digits.uppercased())
    }

    if let groups = captures(
      #"rgb\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*\)"#, in: trimmed)
    {
      let channels = groups.compactMap { Int($0) }
      guard channels.count == 3, channels.allSatisfy({ $0 <= 255 }) else { return nil }
      return ColorValue(
        color: NSColor(
          srgbRed: CGFloat(channels[0]) / 255, green: CGFloat(channels[1]) / 255,
          blue: CGFloat(channels[2]) / 255, alpha: 1),
        label: trimmed)
    }
    return nil
  }

  /// Domaine puis reste de l'adresse, pour la carte d'un lien. Sans schéma, `https://` est
  /// supposé (le classement accepte `www.exemple.com`).
  static func linkParts(_ text: String) -> (host: String, rest: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
    guard let components = URLComponents(string: full), let host = components.host else {
      return (trimmed, "")
    }
    var rest = components.percentEncodedPath
    if rest == "/" { rest = "" }
    if let query = components.percentEncodedQuery { rest += "?" + query }
    if let fragment = components.percentEncodedFragment { rest += "#" + fragment }
    return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, rest)
  }

  /// Adresse à déposer quand on glisse un lien hors de la carte.
  static func url(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
  }
}
