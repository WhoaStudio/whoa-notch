import Foundation

/// Relie la source du presse-papiers au store et pousse la liste vers l'interface. Ne tient
/// aucun contrôleur : c'est `AppDelegate` qui branche `onStateChanged`.
@MainActor
final class ClipboardHistoryViewModel {

  var onStateChanged: (([ClipboardItem]) -> Void)?

  let store: ClipboardHistoryStore
  private let provider: ClipboardProviding

  init(provider: ClipboardProviding, store: ClipboardHistoryStore = ClipboardHistoryStore()) {
    self.provider = provider
    self.store = store
  }

  var items: [ClipboardItem] { store.items }

  func activate() {
    provider.onSnapshot = { [weak self] snapshot in
      guard let self, let classification = ClipboardClassifier.classify(snapshot) else { return }
      store.add(classification, sourceBundleID: snapshot.sourceBundleID)
      onStateChanged?(store.items)
    }
    provider.start()
    onStateChanged?(store.items)
  }

  func clear() {
    store.clear()
    onStateChanged?(store.items)
  }

  /// Remet l'élément dans le presse-papiers, et le fait remonter en tête.
  func recopy(_ item: ClipboardItem) {
    let imageData = store.imageURL(for: item).flatMap { try? Data(contentsOf: $0) }
    let classification = ClipboardClassification(
      kind: item.kind, tag: item.tag, text: item.text, fileURL: item.fileURL, imageData: imageData)
    provider.copy(classification)
    store.add(classification, sourceBundleID: item.sourceBundleID)
    onStateChanged?(store.items)
  }
}
