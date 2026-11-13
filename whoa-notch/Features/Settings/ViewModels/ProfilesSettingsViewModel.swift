import Combine
import Foundation

/// Expose la section "Profiles" à sa vue : la liste des profils et le profil en cours d'édition.
@MainActor
final class ProfilesSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: DockSettings
  /// Le profil affiché dans le formulaire — pas forcément le profil actif du dock.
  @Published var selectedID: String?

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.settings = storage.settings.dock
    self.selectedID =
      storage.settings.dock.activeProfileID ?? storage.settings.dock.profiles.first?.id

    cancellable = storage.$settings
      .map(\.dock)
      .removeDuplicates()
      .sink { [weak self] dock in
        guard let self else { return }
        self.settings = dock
        if let id = self.selectedID, !dock.profiles.contains(where: { $0.id == id }) {
          self.selectedID = dock.profiles.first?.id
        }
      }
  }

  var selected: DockProfile? {
    selectedID.flatMap { id in settings.profiles.first { $0.id == id } }
  }

  func create() {
    let profile = DockProfile(name: "Profile \(settings.profiles.count + 1)")
    storage.settings.dock.profiles.append(profile)
    selectedID = profile.id
  }

  func deleteSelected() {
    guard let id = selectedID else { return }
    storage.settings.dock.profiles.removeAll { $0.id == id }
    if storage.settings.dock.activeProfileID == id { storage.settings.dock.activeProfileID = nil }
  }

  func update(_ change: (inout DockProfile) -> Void) {
    guard let id = selectedID,
      let index = storage.settings.dock.profiles.firstIndex(where: { $0.id == id })
    else { return }
    change(&storage.settings.dock.profiles[index])
  }

  func setApp(_ app: DockPinnedApp, selected: Bool) {
    update { profile in
      let present = profile.apps.contains { $0.bundleID == app.bundleID }
      if selected && !present { profile.apps.append(app) }
      if !selected { profile.apps.removeAll { $0.bundleID == app.bundleID } }
    }
  }

  /// Met l'appli à `index` du dock du profil — la déplace si elle y est déjà, l'ajoute sinon.
  func placeApp(_ app: DockPinnedApp, at index: Int) {
    update { $0.apps.place(app, at: index) }
  }

  func addWidget(kind: String) { update { $0.addWidget(kind: kind) } }

  func removeWidget(id: String) { update { $0.removeWidget(id: id) } }

  func setActive(_ active: Bool) {
    guard let id = selectedID else { return }
    storage.settings.dock.activeProfileID =
      active
      ? id
      : (storage.settings.dock.activeProfileID == id ? nil : storage.settings.dock.activeProfileID)
  }
}
