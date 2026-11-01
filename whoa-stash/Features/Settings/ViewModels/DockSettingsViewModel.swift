import Combine
import Foundation

/// Expose la section "Dock" à sa vue — miroir de `KnockSettingsViewModel`.
@MainActor
final class DockSettingsViewModel: ObservableObject {

    private let storage: SettingsStorage
    private var cancellable: AnyCancellable?

    @Published private(set) var settings: DockSettings

    init(storage: SettingsStorage = .shared) {
        self.storage = storage
        self.settings = storage.settings.dock

        cancellable = storage.$settings
            .map(\.dock)
            .removeDuplicates()
            .sink { [weak self] in self?.settings = $0 }
    }

    func setEnabled(_ enabled: Bool) {
        storage.settings.dock.enabled = enabled
    }

    func setHideSystemDock(_ hide: Bool) {
        storage.settings.dock.hideSystemDock = hide
    }

    /// Ajoute une appli à la liste de lancement (les épingles du dock). Sans effet si le bundle est
    /// illisible ou déjà présent.
    func addApp(at url: URL) {
        guard let app = DockPinnedApp(appURL: url),
              !storage.settings.dock.pinnedApps.contains(where: { $0.bundleID == app.bundleID })
        else { return }
        storage.settings.dock.pinnedApps.append(app)
    }

    func removeApp(bundleID: String) {
        storage.settings.dock.pinnedApps.removeAll { $0.bundleID == bundleID }
        storage.settings.dock.launchExcluded.removeAll { $0 == bundleID }
    }

    func setLaunchIncluded(_ included: Bool, bundleID: String) {
        var excluded = storage.settings.dock.launchExcluded.filter { $0 != bundleID }
        if !included { excluded.append(bundleID) }
        storage.settings.dock.launchExcluded = excluded
    }

    func setAutoHide(_ hide: Bool) {
        storage.settings.dock.autoHide = hide
    }

    func setTheme(_ theme: DockTheme) {
        storage.settings.dock.theme = theme
    }

    func setToggleHotkey(_ hotkey: DockHotkey) {
        storage.settings.dock.toggleHotkey = hotkey
    }
}
