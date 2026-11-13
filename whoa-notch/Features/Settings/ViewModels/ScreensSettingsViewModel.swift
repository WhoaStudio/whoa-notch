import Combine
import Foundation

/// Expose la section "Screens" à sa vue : sur quels écrans le dock apparaît. Toute écriture passe
/// par `SettingsStorage`.
@MainActor
final class ScreensSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var dock: DockSettings

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.dock = storage.settings.dock

    cancellable = storage.$settings
      .map(\.dock)
      .removeDuplicates()
      .sink { [weak self] in self?.dock = $0 }
  }

  func setScreenMode(_ mode: DockScreenMode) {
    storage.settings.dock.screenMode = mode
  }

  /// Coche ou décoche « Attached » pour l'écran d'identifiant `uuid`.
  func setDisplay(uuid: String, attached: Bool) {
    var detached = storage.settings.dock.detachedDisplays.filter { $0 != uuid }
    if !attached { detached.append(uuid) }
    storage.settings.dock.detachedDisplays = detached
  }
}
