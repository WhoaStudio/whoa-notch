import Foundation

/// Une note, telle qu'elle est écrite sur disque. Le titre affiché est la première ligne du
/// texte : il n'est pas stocké.
struct Note: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    /// Première ligne non vide du texte, ou « New note » pour une note encore vide.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "New note"
    }
}
