import Foundation
import os

/// Épingles du dock. Copiées **une fois** depuis `persistent-apps` de `com.apple.dock` (lecture
/// seule), puis uniquement lues et écrites dans nos propres réglages : `persistent-apps` n'est
/// jamais écrit.
@MainActor
final class PinnedAppsStore {

  private let storage: SettingsStorage

  init(storage: SettingsStorage = .shared) { self.storage = storage }

  var pinned: [DockPinnedApp] { storage.settings.dock.pinnedApps }

  func seedIfNeeded(source: () -> [[String: Any]]? = PinnedAppsStore.readSystemPersistentApps) {
    guard !storage.settings.dock.didSeedPinnedApps else { return }
    storage.settings.dock.pinnedApps = Self.parse(persistentApps: source() ?? [])
    storage.settings.dock.didSeedPinnedApps = true
    Log.dock.info(
      "Épingles copiées depuis le Dock macOS : \(self.storage.settings.dock.pinnedApps.count, privacy: .public)"
    )
  }

  nonisolated static func readSystemPersistentApps() -> [[String: Any]]? {
    CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString)
      as? [[String: Any]]
  }

  /// Les entrées sans `bundle-identifier` (séparateurs, piles) sont ignorées.
  nonisolated static func parse(persistentApps: [[String: Any]]) -> [DockPinnedApp] {
    persistentApps.compactMap { entry in
      guard let tile = entry["tile-data"] as? [String: Any],
        let bundleID = tile["bundle-identifier"] as? String, !bundleID.isEmpty,
        let file = tile["file-data"] as? [String: Any],
        let urlString = file["_CFURLString"] as? String,
        let path = URL(string: urlString)?.path, !path.isEmpty
      else { return nil }
      return DockPinnedApp(bundleID: bundleID, path: path)
    }
  }
}
