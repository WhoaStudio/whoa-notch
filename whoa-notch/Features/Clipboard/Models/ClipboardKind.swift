import Foundation

/// Famille d'un élément du presse-papiers : elle décide de la pastille, du filtre qui le
/// retient et de la couleur de la bordure de sa carte.
enum ClipboardKind: String, Codable, CaseIterable {
  case text
  case link
  case image
  case video
  case file
}

/// Les filtres de la rangée du haut. « All Clips » les laisse tous passer ; un fichier
/// quelconque (ZIP, PDF…) n'a pas de filtre à lui et ne se voit que sous « All Clips ».
enum ClipboardFilter: Int, CaseIterable {
  case all
  case text
  case links
  case images
  case videos

  var title: String {
    switch self {
    case .all: "All Clips"
    case .text: "Text"
    case .links: "Links"
    case .images: "Images"
    case .videos: "Videos"
    }
  }

  /// Glyphe SF Symbols du filtre dans la capsule.
  var symbolName: String {
    switch self {
    case .all: "square.grid.2x2"
    case .text: "text.alignleft"
    case .links: "link"
    case .images: "photo"
    case .videos: "film"
    }
  }

  func matches(_ kind: ClipboardKind) -> Bool {
    switch self {
    case .all: true
    case .text: kind == .text
    case .links: kind == .link
    case .images: kind == .image
    case .videos: kind == .video
    }
  }
}
