import Combine
import Foundation

/// Expose la section « Privacy & Permissions » à sa vue : l'état de chaque autorisation, relu auprès
/// du système à chaque retour dans l'app (l'utilisateur peut les changer dans Réglages système).
@MainActor
final class PrivacySettingsViewModel: ObservableObject {

  @Published private(set) var states: [PrivacyPermission: PermissionState] = [:]

  init() {
    refresh()
  }

  func refresh() {
    states = Dictionary(
      uniqueKeysWithValues: PrivacyPermission.allCases.map {
        ($0, PrivacyPermissionService.state(for: $0))
      })
  }

  func state(for permission: PrivacyPermission) -> PermissionState {
    states[permission] ?? .notDetermined
  }

  /// Demande l'autorisation si macOS peut encore la poser. Si elle était déjà refusée, ou si son état
  /// n'est pas lisible, ouvre le réglage système, le seul endroit où on peut la changer.
  func act(on permission: PrivacyPermission) {
    let before = state(for: permission)
    Task {
      await PrivacyPermissionService.request(permission)
      refresh()
      if before == .denied || before == .unknown {
        PrivacyPermissionService.openSettings(permission)
      }
    }
  }
}
