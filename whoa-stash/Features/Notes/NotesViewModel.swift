import Foundation

/// Relie le store des notes à l'interface. Ne tient aucun contrôleur : c'est `AppDelegate` qui
/// branche `onStateChanged`.
@MainActor
final class NotesViewModel {

    var onStateChanged: (([Note]) -> Void)?

    let store: NotesStore

    init(store: NotesStore = NotesStore()) {
        self.store = store
    }

    var notes: [Note] { store.notes }

    func activate() {
        onStateChanged?(store.notes)
    }

    func create() {
        store.create()
        onStateChanged?(store.notes)
    }

    func update(id: UUID, text: String) {
        store.update(id: id, text: text)
        onStateChanged?(store.notes)
    }

    func delete(id: UUID) {
        store.delete(id: id)
        onStateChanged?(store.notes)
    }
}
