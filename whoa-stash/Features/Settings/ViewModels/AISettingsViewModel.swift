import Combine
import Foundation
import OSLog

/// Expose l'onglet "AI" à sa vue : l'état des hooks Claude Code et l'interrupteur de Claude Desktop.
@MainActor
final class AISettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private let installer: ClaudeHookInstaller
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: AISettings
  @Published private(set) var hookStatus: ClaudeHookInstaller.Status
  @Published private(set) var errorMessage: String?

  var scriptPath: String { installer.scriptURL.path }
  var settingsPath: String { installer.settingsURL.path }

  init(storage: SettingsStorage = .shared, installer: ClaudeHookInstaller = .standard) {
    self.storage = storage
    self.installer = installer
    self.settings = storage.settings.ai
    self.hookStatus = installer.status()

    cancellable = storage.$settings
      .map(\.ai)
      .removeDuplicates()
      .sink { [weak self] in self?.settings = $0 }
  }

  func refresh() {
    hookStatus = installer.status()
  }

  func installHooks() { run { try installer.install() } }

  func uninstallHooks() { run { try installer.uninstall() } }

  func setDesktopWatcherEnabled(_ enabled: Bool) {
    storage.settings.ai.desktopWatcherEnabled = enabled
  }

  private func run(_ action: () throws -> Void) {
    do {
      try action()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      Log.agents.error("Hooks Claude Code : \(error.localizedDescription)")
    }
    hookStatus = installer.status()
  }
}
