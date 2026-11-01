import Foundation
import Testing

@testable import whoa_stash

@MainActor
@Suite("Notes : store")
struct NotesStoreTests {

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("whoa-stash-notes-\(UUID().uuidString)")
    }

    @Test("créer une note l'ajoute en tête, vide")
    func create() {
        let store = NotesStore(directory: makeDirectory())
        let first = store.create()
        let second = store.create()
        #expect(store.notes.map(\.id) == [second.id, first.id])
        #expect(second.text.isEmpty)
        #expect(second.title == "New note")
    }

    @Test("modifier une note change son texte et la remonte en tête")
    func edit() {
        let store = NotesStore(directory: makeDirectory())
        let older = store.create()
        _ = store.create()
        store.update(id: older.id, text: "Courses\nlait")
        #expect(store.notes.first?.id == older.id)
        #expect(store.notes.first?.text == "Courses\nlait")
        #expect(store.notes.first?.title == "Courses")
    }

    @Test("supprimer une note la retire")
    func delete() {
        let store = NotesStore(directory: makeDirectory())
        let note = store.create()
        let other = store.create()
        store.delete(id: note.id)
        #expect(store.notes.map(\.id) == [other.id])
    }

    @Test("les notes survivent à un rechargement depuis le disque")
    func reload() {
        let directory = makeDirectory()
        let store = NotesStore(directory: directory)
        let kept = store.create()
        store.update(id: kept.id, text: "Idée")
        let removed = store.create()
        store.delete(id: removed.id)

        let reloaded = NotesStore(directory: directory)
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.id == kept.id)
        #expect(reloaded.notes.first?.text == "Idée")
    }

    @Test("un fichier illisible donne une liste vide")
    func corruptFile() throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: directory.appendingPathComponent("notes.json"))
        #expect(NotesStore(directory: directory).notes.isEmpty)
    }
}
