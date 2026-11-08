import CryptoKit
import Foundation

/// Un élément de l'historique, tel qu'il est écrit sur disque. Les images ne sont pas dans le
/// JSON : elles vivent dans des fichiers à côté (`imageName`), un fichier copié n'est retenu que
/// par son chemin.
struct ClipboardItem: Codable, Equatable, Identifiable {
  let id: UUID
  let kind: ClipboardKind
  let tag: String
  let text: String?
  let filePath: String?
  let imageName: String?
  /// Empreinte du contenu : recopier la même chose fait remonter la carte au lieu d'en ajouter
  /// une.
  let fingerprint: String
  var date: Date
  /// Absent des historiques écrits avant l'ajout de la source : le décodage le tolère.
  var sourceBundleID: String?

  var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }

  /// « now », « 23 min ago », « 3 h ago », « 2 d ago ».
  static func ageText(since date: Date, now: Date = .now) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60)) min ago"
    case ..<86_400: return "\(Int(seconds / 3600)) h ago"
    default: return "\(Int(seconds / 86_400)) d ago"
    }
  }

  static func fingerprint(of classification: ClipboardClassification) -> String {
    if let text = classification.text { return "t:" + text }
    if let url = classification.fileURL { return "f:" + url.path }
    if let data = classification.imageData {
      return "i:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    return ""
  }
}
