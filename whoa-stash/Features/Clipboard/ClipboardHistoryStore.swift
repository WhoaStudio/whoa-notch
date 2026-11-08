import Foundation
import OSLog

/// L'historique du presse-papiers et sa persistance.
///
/// Le plus récent est en tête. Recopier une chose déjà présente la fait remonter. Le JSON est
/// écrit dans `Application Support/whoa-stash/Clipboard/` ; les images sont des fichiers PNG
/// voisins, nommés d'après l'identifiant de l'élément. Ce store ne touche pas à `UserDefaults`.
@MainActor
final class ClipboardHistoryStore {

  static let defaultLimit = 50

  private let directory: URL
  private let limit: Int
  private let fileManager: FileManager

  private(set) var items: [ClipboardItem] = []

  init(directory: URL? = nil, limit: Int = defaultLimit, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.limit = limit
    self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    load()
  }

  private var indexURL: URL { directory.appendingPathComponent("history.json") }

  func imageURL(for item: ClipboardItem) -> URL? {
    item.imageName.map { directory.appendingPathComponent($0) }
  }

  /// Ajoute un élément en tête, ou remonte celui qui a le même contenu.
  func add(
    _ classification: ClipboardClassification, sourceBundleID: String? = nil, date: Date = .now
  ) {
    let fingerprint = ClipboardItem.fingerprint(of: classification)
    if let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
      var item = items.remove(at: index)
      item.date = date
      item.sourceBundleID = sourceBundleID ?? item.sourceBundleID
      items.insert(item, at: 0)
      persist()
      return
    }

    let id = UUID()
    var imageName: String?
    if let data = classification.imageData {
      let name = id.uuidString + ".png"
      do {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
        imageName = name
      } catch {
        Log.clipboard.error(
          "Écriture de l'image impossible : \(error.localizedDescription, privacy: .public)")
        return
      }
    }

    items.insert(
      ClipboardItem(
        id: id, kind: classification.kind, tag: classification.tag, text: classification.text,
        filePath: classification.fileURL?.path, imageName: imageName,
        fingerprint: fingerprint, date: date, sourceBundleID: sourceBundleID),
      at: 0)
    if items.count > limit {
      items.suffix(from: limit).forEach(deleteImage)
      items.removeLast(items.count - limit)
    }
    persist()
  }

  func clear() {
    items.forEach(deleteImage)
    items = []
    persist()
  }

  // MARK: - Persistance

  private func persist() {
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
    } catch {
      Log.clipboard.error(
        "Écriture de l'historique impossible : \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Relit l'historique en laissant tomber les images dont le fichier a disparu.
  private func load() {
    guard
      let data = try? Data(contentsOf: indexURL),
      let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
    else { return }
    items = decoded.filter { item in
      guard let name = item.imageName else { return true }
      return fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
    }
  }

  private func deleteImage(_ item: ClipboardItem) {
    guard let url = imageURL(for: item) else { return }
    try? fileManager.removeItem(at: url)
  }

  private static func defaultDirectory(fileManager: FileManager) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("whoa-stash", isDirectory: true)
      .appendingPathComponent("Clipboard", isDirectory: true)
  }
}
