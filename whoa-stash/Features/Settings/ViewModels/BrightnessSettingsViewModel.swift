import Combine
import Foundation

/// Expose la section "Brightness" à sa vue — miroir de `GeneralSettingsViewModel`.
@MainActor
final class BrightnessSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: BrightnessSettings

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.settings = storage.settings.brightness

    cancellable = storage.$settings
      .map(\.brightness)
      .removeDuplicates()
      .sink { [weak self] in self?.settings = $0 }
  }

  func setShowPercentage(_ enabled: Bool) {
    storage.settings.brightness.showPercentage = enabled
  }

  func setAutoHideDelay(_ value: Double) {
    storage.settings.brightness.autoHideDelay = value
  }

  func setGlowIntensity(_ value: Double) {
    storage.settings.brightness.glowIntensity = value
  }

  func setScrollSensitivity(_ value: Double) {
    storage.settings.brightness.scrollSensitivity = value
  }

  func setWidgetPosition(_ position: EdgePosition) {
    storage.settings.brightness.widgetPosition = position
  }

  func setWidgetSize(_ size: WidgetSize) {
    storage.settings.brightness.widgetSize = size
  }

  func setEnableOverlay(_ enabled: Bool) {
    storage.settings.brightness.enableOverlay = enabled
  }
}
