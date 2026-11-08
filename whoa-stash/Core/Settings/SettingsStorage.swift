import Combine
import Foundation

/// Source unique de vérité pour `AppSettings` : charge/persiste un unique blob JSON dans
/// `UserDefaults` et publie chaque changement. Remplace toute lecture/écriture directe de
/// `UserDefaults` ailleurs dans l'app — vues et contrôleurs ne connaissent que ce service.
@MainActor
final class SettingsStorage: ObservableObject {

  static let shared = SettingsStorage()

  private static let defaultsKey = "com.whoastudio.whoa-stash.appSettings"

  @Published var settings: AppSettings {
    didSet {
      guard oldValue != settings else { return }
      persist()
    }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.defaultsKey),
      let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
    {
      settings = decoded
    } else {
      settings = .default
    }
  }

  /// Remet toutes les préférences à leur valeur d'origine. Passe par `settings` et non par
  /// une suppression de la clé : les abonnés doivent voir le changement comme n'importe quel
  /// autre, et les effets de bord système (lancement au démarrage) rester du ressort de leurs
  /// services.
  func resetToDefaults() {
    settings = .default
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
