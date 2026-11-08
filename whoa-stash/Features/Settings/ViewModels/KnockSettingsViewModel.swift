import Combine
import Foundation

/// Expose la section "Knock" à sa vue — miroir de `BrightnessSettingsViewModel`.
@MainActor
final class KnockSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: KnockSettings

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.settings = storage.settings.knock

    cancellable = storage.$settings
      .map(\.knock)
      .removeDuplicates()
      .sink { [weak self] in self?.settings = $0 }
  }

  func setEnabled(_ enabled: Bool) {
    storage.settings.knock.enabled = enabled
  }

  func setAction(_ action: KnockAction, taps: Int) {
    if taps == 1 {
      storage.settings.knock.single = action
    } else {
      storage.settings.knock.double = action
    }
  }

  func setSensitivity(_ value: Double) {
    storage.settings.knock.sensitivity = value
  }
}
