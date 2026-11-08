import Foundation
import Testing

@testable import whoa_stash

/// Le chemin d'écriture des Préférences : chaque contrôle de l'écran « General » passe par ce
/// view model, qui est le seul à écrire dans `SettingsStorage`. Les tests l'exercent avec un
/// stockage injecté, donc sans toucher aux réglages réels de la machine.
@MainActor
struct GeneralSettingsViewModelTests {

  private static func makeStorage() -> (SettingsStorage, UserDefaults) {
    let suite = "whoa-stash.tests.vm.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (SettingsStorage(defaults: defaults), defaults)
  }

  @Test("chaque écriture atterrit dans le stockage et survit au relancement")
  func writesReachStorageAndPersist() {
    let (storage, defaults) = Self.makeStorage()
    let viewModel = GeneralSettingsViewModel(storage: storage)

    viewModel.setAccentColor(.orange)
    viewModel.setPanelOpacity(0.6)
    viewModel.setTogglePanelShortcut(.controlCommandN)
    viewModel.setEnableAnimations(false)
    viewModel.setNotchPanelEnabled(false)

    #expect(storage.settings.general.accentColor == .orange)
    #expect(storage.settings.general.panelOpacity == 0.6)

    // Le relancement : une instance neuve sur la même suite.
    let reloaded = SettingsStorage(defaults: defaults)
    #expect(reloaded.settings.general.accentColor == .orange)
    #expect(reloaded.settings.general.panelOpacity == 0.6)
    #expect(reloaded.settings.general.togglePanelShortcut == .controlCommandN)
    #expect(reloaded.settings.general.enableAnimations == false)
    #expect(reloaded.settings.notchPanel.enabled == false)
  }

  @Test("le view model republie ce que le stockage reçoit d'ailleurs")
  func viewModelFollowsStorage() {
    let (storage, _) = Self.makeStorage()
    let viewModel = GeneralSettingsViewModel(storage: storage)

    // Écriture venue d'un autre écran des Préférences, ou de la remise à zéro.
    storage.settings.general.accentColor = .pink
    #expect(viewModel.settings.accentColor == .pink)

    storage.settings.notchPanel.enabled = false
    #expect(viewModel.notchPanel.enabled == false)
  }

  /// `launchAtLogin` reste faux d'un bout à l'autre : le remettre à faux est déjà sa valeur
  /// par défaut, donc la remise à zéro ne touche pas `SMAppService` et le test n'a aucun
  /// effet sur la session.
  @Test("la remise à zéro repart des valeurs d'origine, et les persiste")
  func resetRestoresDefaults() {
    let (storage, defaults) = Self.makeStorage()
    let viewModel = GeneralSettingsViewModel(storage: storage)

    viewModel.setAccentColor(.blue)
    viewModel.setPanelOpacity(0.4)
    viewModel.setTogglePanelShortcut(.optionCommandB)

    viewModel.resetToDefaults()

    #expect(viewModel.settings == GeneralSettings())
    #expect(viewModel.settings.launchAtLogin == false)
    #expect(SettingsStorage(defaults: defaults).settings == .default)
  }
}
