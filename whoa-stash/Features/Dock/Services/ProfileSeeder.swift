import Foundation

/// Garantit au moins un profil — « Building », rempli des applis épinglées du Dock
/// macOS — et un profil actif : le groupe de gauche du dock montre toujours où l'on est.
@MainActor
enum ProfileSeeder {
  static func seedIfNeeded(_ storage: SettingsStorage) {
    if storage.settings.dock.profiles.isEmpty {
      storage.settings.dock.profiles = [
        DockProfile(
          name: "Building", symbol: "hammer.fill", apps: storage.settings.dock.pinnedApps)
      ]
    }
    if storage.settings.dock.activeProfile == nil {
      storage.settings.dock.activeProfileID = storage.settings.dock.profiles.first?.id
    }
  }
}
