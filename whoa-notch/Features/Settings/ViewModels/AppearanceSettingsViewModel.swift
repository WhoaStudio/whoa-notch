import Combine
import Foundation

/// Expose la section "Appearance" à sa vue : taille, espacement, coins, ombre, couleurs des widgets,
/// fond des icônes, transparence, icônes et ajustement à l'écran du dock, plus l'animation (partagée
/// avec « Enable animations » de General). Toute écriture passe par `SettingsStorage`.
@MainActor
final class AppearanceSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var dock: DockSettings
  @Published private(set) var animationsEnabled: Bool

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.dock = storage.settings.dock
    self.animationsEnabled = storage.settings.general.enableAnimations

    cancellable = storage.$settings
      .sink { [weak self] settings in
        self?.dock = settings.dock
        self?.animationsEnabled = settings.general.enableAnimations
      }
  }

  func setDockSize(_ percent: Double) { storage.settings.dock.dockSize = percent }
  func setWidgetSpacing(_ points: Double) { storage.settings.dock.widgetSpacing = points }
  func setCornerRadius(_ points: Double) { storage.settings.dock.cornerRadius = points }
  func setAdaptsToFit(_ on: Bool) { storage.settings.dock.adaptsToFit = on }
  func setMonochromeWidgets(_ on: Bool) { storage.settings.dock.monochromeWidgets = on }
  func setTileBackgrounds(_ on: Bool) { storage.settings.dock.tileBackgrounds = on }
  func setDockShadow(_ on: Bool) { storage.settings.dock.dockShadow = on }
  func setGrayscaleIcons(_ on: Bool) { storage.settings.dock.grayscaleIcons = on }
  func setReduceTransparency(_ on: Bool) { storage.settings.dock.reduceTransparency = on }
  func setAnimationsEnabled(_ enabled: Bool) { storage.settings.general.enableAnimations = enabled }
}
