import Foundation
import UniformTypeIdentifiers

/// Résultat du classement d'un instantané : de quoi bâtir une carte, rien de plus.
struct ClipboardClassification: Equatable {
  let kind: ClipboardKind
  /// Pastille de la carte : « TEXT », « LINK », ou l'extension du fichier en capitales.
  let tag: String
  let text: String?
  let fileURL: URL?
  let imageData: Data?
}

/// Décide de la nature d'un instantané du presse-papiers. Fonction pure.
///
/// L'ordre compte, le premier cas qui s'applique l'emporte : un fichier copié dans le Finder
/// porte aussi son nom en texte et son icône en image, il doit donc être reconnu avant eux.
enum ClipboardClassifier {

  static func classify(_ snapshot: ClipboardSnapshot) -> ClipboardClassification? {
    if let url = snapshot.fileURLs.first {
      return classify(fileURL: url)
    }
    if let data = snapshot.imageData, !data.isEmpty {
      return ClipboardClassification(
        kind: .image, tag: "PNG", text: nil, fileURL: nil, imageData: data)
    }
    guard let string = snapshot.string else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if isLink(trimmed) {
      return ClipboardClassification(
        kind: .link, tag: "LINK", text: trimmed, fileURL: nil, imageData: nil)
    }
    return ClipboardClassification(
      kind: .text, tag: "TEXT", text: string, fileURL: nil, imageData: nil)
  }

  private static func classify(fileURL url: URL) -> ClipboardClassification {
    let ext = url.pathExtension
    let type = UTType(filenameExtension: ext)
    let kind: ClipboardKind =
      if type?.conforms(to: .image) == true { .image } else if type?.conforms(to: .movie) == true {
        .video
      } else { .file }
    let tag = ext.isEmpty ? "FILE" : ext.uppercased()
    return ClipboardClassification(kind: kind, tag: tag, text: nil, fileURL: url, imageData: nil)
  }

  /// Une seule URL `http(s)://` ou `www.`, et rien d'autre : une phrase qui en contient une
  /// reste un texte.
  static func isLink(_ string: String) -> Bool {
    guard !string.contains(where: \.isWhitespace) else { return false }
    let lowered = string.lowercased()
    let candidate = lowered.hasPrefix("www.") ? "https://" + string : string
    guard
      lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("www."),
      let host = URLComponents(string: candidate)?.host
    else { return false }
    return host.contains(".") && !host.hasSuffix(".")
  }
}
