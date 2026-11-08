import Foundation

/// Décodage du courrier brut tel que le serveur le livre : en-têtes (RFC 5322, mots encodés
/// RFC 2047) et début du corps (multipart, base64, quoted-printable, jeux de caractères).
/// Fonctions pures, sans état — c'est ce qui les rend testables sans serveur.
nonisolated enum MailBodyDecoder {

  // MARK: - En-têtes

  /// En-têtes dépliés, clés en minuscules ; la première occurrence l'emporte. S'arrête à la
  /// première ligne vide.
  static func parseHeaders(_ raw: String) -> [String: String] {
    var result: [String: String] = [:]
    var currentKey: String?
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
    for line in normalized.components(separatedBy: "\n") {
      if line.isEmpty {
        if result.isEmpty { continue }
        break
      }
      if let first = line.first, first == " " || first == "\t" {
        if let key = currentKey {
          result[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
        }
        continue
      }
      guard let colon = line.firstIndex(of: ":") else {
        currentKey = nil
        continue
      }
      let key = line[..<colon].lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      if result[key] == nil {
        result[key] = value
        currentKey = key
      } else {
        currentKey = nil
      }
    }
    return result
  }

  /// Décode les mots encodés (`=?utf-8?B?…?=`, `=?iso-8859-1?Q?…?=`) d'une valeur d'en-tête.
  static func decodeHeader(_ value: String) -> String {
    guard value.contains("=?"),
      let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#)
    else { return value }

    let ns = value as NSString
    var output = ""
    var cursor = 0
    var previousWasEncoded = false
    for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
      let gap = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      // Deux mots encodés qui se suivent se recollent : l'espace entre eux n'est que du pliage.
      if !(previousWasEncoded && gap.allSatisfy(\.isWhitespace)) { output += gap }
      let charset = ns.substring(with: match.range(at: 1))
      let kind = ns.substring(with: match.range(at: 2)).lowercased()
      let text = ns.substring(with: match.range(at: 3))
      let data =
        kind == "b"
        ? base64Data(text)
        : decodeQuotedPrintable(Data(text.replacingOccurrences(of: "_", with: " ").utf8))
      output += string(from: data, charset: charset)
      cursor = match.range.location + match.range.length
      previousWasEncoded = true
    }
    output += ns.substring(from: cursor)
    return output
  }

  /// Le nom affiché d'un `From` : `"Ada" <ada@x.org>` → `Ada`, `<ada@x.org>` → `ada@x.org`.
  static func displayName(fromHeader value: String) -> String {
    let decoded = decodeHeader(value).trimmingCharacters(in: .whitespaces)
    guard let open = decoded.lastIndex(of: "<"), let close = decoded.lastIndex(of: ">"),
      open < close
    else { return decoded }
    let name = decoded[..<open]
      .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
    return name.isEmpty ? String(decoded[decoded.index(after: open)..<close]) : name
  }

  // MARK: - Corps

  /// Le début du texte du message sur une ligne, d'au plus `limit` caractères. `body` est le corps
  /// (`BODY[TEXT]`), éventuellement tronqué ; `headers` sont ceux du message entier.
  static func preview(headers: [String: String], body: Data, limit: Int = 160) -> String {
    // Latin-1 relie octet et caractère un à un : la structure MIME se découpe en texte sans rien
    // perdre, et chaque feuille est reconvertie en octets avant d'être décodée.
    let raw = (String(data: body, encoding: .isoLatin1) ?? "").replacingOccurrences(
      of: "\r\n", with: "\n")
    let text = plainText(headers: headers, raw: raw, depth: 0)?.text ?? ""
    let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
  }

  private static func plainText(headers: [String: String], raw: String, depth: Int) -> (
    text: String, isHTML: Bool
  )? {
    let contentType = headers["content-type"] ?? "text/plain"
    let mime =
      contentType.split(separator: ";").first
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"

    if mime.hasPrefix("multipart/") {
      guard depth < 4, let boundary = parameter("boundary", in: contentType) else { return nil }
      var htmlFallback: (text: String, isHTML: Bool)?
      for part in splitMultipart(raw, boundary: boundary) {
        let (partHeaders, partBody) = splitHeaders(part)
        if partHeaders["content-disposition"]?.lowercased().hasPrefix("attachment") == true {
          continue
        }
        guard let found = plainText(headers: partHeaders, raw: partBody, depth: depth + 1) else {
          continue
        }
        if !found.isHTML { return found }
        htmlFallback = htmlFallback ?? found
      }
      return htmlFallback
    }
    guard mime == "text/plain" || mime == "text/html" else { return nil }

    let transfer =
      headers["content-transfer-encoding"]?.trimmingCharacters(in: .whitespaces).lowercased()
      ?? "7bit"
    let bytes = raw.data(using: .isoLatin1) ?? Data()
    let decoded: Data
    switch transfer {
    case "base64": decoded = base64Data(raw)
    case "quoted-printable": decoded = decodeQuotedPrintable(bytes)
    default: decoded = bytes
    }
    let text = string(from: decoded, charset: parameter("charset", in: contentType))
    return mime == "text/html" ? (stripHTML(text), true) : (text, false)
  }

  // MARK: - Briques

  /// La valeur du paramètre `name` d'un en-tête (`boundary="x"`, `charset=utf-8`).
  static func parameter(_ name: String, in header: String) -> String? {
    for segment in header.split(separator: ";").dropFirst() {
      let trimmed = segment.trimmingCharacters(in: .whitespaces)
      guard trimmed.lowercased().hasPrefix(name + "=") else { continue }
      let value = trimmed.dropFirst(name.count + 1).trimmingCharacters(
        in: CharacterSet(charactersIn: "\" "))
      return value.isEmpty ? nil : value
    }
    return nil
  }

  private static func splitMultipart(_ raw: String, boundary: String) -> [String] {
    var pieces = raw.components(separatedBy: "--" + boundary)
    guard pieces.count > 1 else { return [] }
    pieces.removeFirst()
    var parts: [String] = []
    for piece in pieces {
      if piece.hasPrefix("--") { break }
      // Le reste de la ligne de délimitation (espaces) précède le premier saut de ligne.
      if let newline = piece.firstIndex(of: "\n") {
        parts.append(String(piece[piece.index(after: newline)...]))
      }
    }
    return parts
  }

  private static func splitHeaders(_ text: String) -> ([String: String], String) {
    if text.hasPrefix("\n") { return ([:], String(text.dropFirst())) }
    if let range = text.range(of: "\n\n") {
      return (parseHeaders(String(text[..<range.lowerBound])), String(text[range.upperBound...]))
    }
    return (parseHeaders(text), "")
  }

  /// Décode du base64 en tolérant espaces, sauts de ligne et troncature en milieu de bloc.
  static func base64Data(_ text: String) -> Data {
    let alphabet = text.filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    let usable = alphabet.count - alphabet.count % 4
    return Data(base64Encoded: String(alphabet.prefix(usable))) ?? Data()
  }

  static func decodeQuotedPrintable(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    var output = Data()
    output.reserveCapacity(bytes.count)
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x3D {  // "="
        if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
          index += 2
          continue
        }
        if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
          index += 3
          continue
        }
        if index + 2 < bytes.count, let high = hexValue(bytes[index + 1]),
          let low = hexValue(bytes[index + 2])
        {
          output.append(UInt8(high << 4 | low))
          index += 3
          continue
        }
      }
      output.append(byte)
      index += 1
    }
    return output
  }

  private static func hexValue(_ byte: UInt8) -> Int? {
    switch byte {
    case 0x30...0x39: Int(byte) - 0x30
    case 0x41...0x46: Int(byte) - 0x41 + 10
    case 0x61...0x66: Int(byte) - 0x61 + 10
    default: nil
    }
  }

  /// Octets → texte selon le jeu de caractères annoncé ; UTF-8 par défaut, en tolérant un
  /// caractère coupé par la troncature.
  static func string(from data: Data, charset: String?) -> String {
    if let charset, let encoding = encoding(for: charset), encoding != .utf8,
      let text = String(data: data, encoding: encoding)
    {
      return text
    }
    var text = String(decoding: data, as: UTF8.self)
    while text.hasSuffix("\u{FFFD}") { text.removeLast() }
    return text
  }

  private static func encoding(for charset: String) -> String.Encoding? {
    let converted = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    guard converted != kCFStringEncodingInvalidId else { return nil }
    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(converted))
  }

  /// Retire balises, `<style>`/`<script>` et entités courantes d'un HTML, éventuellement tronqué.
  static func stripHTML(_ html: String) -> String {
    var text = html
    for pattern in [#"(?is)<(style|script|head)\b.*?(</\1>|$)"#, #"(?s)<[^>]*(>|$)"#] {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      text = regex.stringByReplacingMatches(
        in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
    }
    let entities = [
      "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&",
    ]
    for (entity, replacement) in entities {
      text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text
  }
}
