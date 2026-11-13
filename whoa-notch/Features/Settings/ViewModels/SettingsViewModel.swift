import Combine
import Foundation

/// État de sélection de la fenêtre de Préférences — la seule chose que `SettingsWindowController`
/// et `SettingsSidebarViewController` partagent.
@MainActor
final class SettingsViewModel: ObservableObject {
  @Published var selectedCategory: SettingsCategory = .general
}
