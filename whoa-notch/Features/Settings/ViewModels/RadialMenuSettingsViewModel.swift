import Combine
import Foundation

/// Expose la section "Radial Menu" à sa vue : le bouton, et la liste d'éléments à éditer.
@MainActor
final class RadialMenuSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: RadialMenuSettings

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.settings = storage.settings.radialMenu

    cancellable = storage.$settings
      .map(\.radialMenu)
      .removeDuplicates()
      .sink { [weak self] in self?.settings = $0 }
  }

  var isFull: Bool { settings.items.count >= RadialMenuSettings.maxItems }

  func setEnabled(_ enabled: Bool) { storage.settings.radialMenu.enabled = enabled }

  func setButton(_ button: RadialMouseButton) { storage.settings.radialMenu.button = button }

  func add(_ item: RadialMenuItem) {
    guard !isFull else { return }
    storage.settings.radialMenu.items.append(item)
  }

  func addApp(at url: URL) {
    guard let item = RadialMenuItem(appURL: url) else { return }
    add(item)
  }

  func remove(id: String) {
    storage.settings.radialMenu.items.removeAll { $0.id == id }
  }

  /// Décale l'élément d'un cran (`offset` = ±1) ; sans effet en bout de liste.
  func move(id: String, by offset: Int) {
    var items = storage.settings.radialMenu.items
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let target = index + offset
    guard items.indices.contains(target) else { return }
    items.swapAt(index, target)
    storage.settings.radialMenu.items = items
  }
}
