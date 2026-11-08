import Foundation
import OSLog
import ServiceManagement

/// Enregistre ou désenregistre l'app comme élément de lancement au démarrage de session.
/// Isolé dans un service dédié pour que `SettingsStorage` reste une simple persistance,
/// sans effet de bord système dans son `didSet`.
final class LaunchAtLoginService {

  static let shared = LaunchAtLoginService()

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      Log.settings.info(
        "lancement au démarrage → \(enabled ? "activé" : "désactivé", privacy: .public)")
    } catch {
      Log.settings.error(
        "échec de la configuration du lancement au démarrage — \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
