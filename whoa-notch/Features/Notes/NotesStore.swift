import Foundation
import OSLog

/// Les notes de l'onglet Notes et leur persistance.
///
/// La plus récemment modifiée est en tête. Le JSON est écrit dans
/// `Application Support/whoa-notch/Notes/`. Ce store ne touche pas à `UserDefaults`.
@MainActor
final class NotesStore {

  private let directory: URL
  private let fileManager: FileManager

  private(set) var notes: [Note] = []

  init(directory: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    load()
  }

  private var indexURL: URL { directory.appendingPathComponent("notes.json") }

  /// Ajoute une note vide en tête et la renvoie.
  @discardableResult
  func create(date: Date = .now) -> Note {
    let note = Note(id: UUID(), text: "", createdAt: date, updatedAt: date)
    notes.insert(note, at: 0)
    persist()
    return note
  }

  /// Remplace le texte d'une note et la remonte en tête. Sans effet si le texte n'a pas changé.
  func update(id: UUID, text: String, date: Date = .now) {
    guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else {
      return
    }
    var note = notes.remove(at: index)
    note.text = text
    note.updatedAt = date
    notes.insert(note, at: 0)
    persist()
  }

  func delete(id: UUID) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    notes.remove(at: index)
    persist()
  }

  // MARK: - Persistance

  private func persist() {
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(notes).write(to: indexURL, options: .atomic)
    } catch {
      Log.notes.error(
        "Écriture des notes impossible : \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Relit les notes ; un fichier absent ou illisible donne une liste vide.
  private func load() {
    guard
      let data = try? Data(contentsOf: indexURL),
      let decoded = try? JSONDecoder().decode([Note].self, from: data)
    else { return }
    notes = decoded
  }

  private static func defaultDirectory(fileManager: FileManager) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("whoa-notch", isDirectory: true)
      .appendingPathComponent("Notes", isDirectory: true)
  }
}
