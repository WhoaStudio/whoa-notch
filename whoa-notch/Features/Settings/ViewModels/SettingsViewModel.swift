import Combine
import Foundation

/// État de sélection de la fenêtre de Préférences — la seule chose que `SettingsWindowController`
/// et `SettingsSidebarViewController` partagent. Le dernier volet ouvert est conservé dans
/// `AppSettings.lastSettingsPane` ; une valeur inconnue retombe sur « General ».
@MainActor
final class SettingsViewModel: ObservableObject {
  @Published var selectedCategory: SettingsCategory {
    didSet {
      guard SettingsStorage.shared.settings.lastSettingsPane != selectedCategory.rawValue else {
        return
      }
      SettingsStorage.shared.settings.lastSettingsPane = selectedCategory.rawValue
    }
  }

  init() {
    selectedCategory =
      SettingsCategory(rawValue: SettingsStorage.shared.settings.lastSettingsPane) ?? .general
  }
}
