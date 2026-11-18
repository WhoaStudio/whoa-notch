import Combine
import Foundation

/// Relie les actions enregistrées (réglages) et les processus qu'elles lancent : pousse l'état
/// aux onglets Actions et Servers, et applique leurs gestes.
final class DevServersViewModel {

  var onStateChanged: ((DevServersState) -> Void)?

  private let storage: SettingsStorage
  private let provider: DevProcessProviding
  private let scanner: ListeningProcessProviding
  private var detected: [DetectedServerGroup] = []
  private var isScanning = false
  /// `--dev-servers=sample` : les actions viennent de la maquette, pas des réglages.
  private var sampleActions: [DevAction]?
  private var cancellable: AnyCancellable?

  init(
    storage: SettingsStorage, provider: DevProcessProviding,
    scanner: ListeningProcessProviding = ListeningProcessScanner()
  ) {
    self.storage = storage
    self.provider = provider
    self.scanner = scanner
    if provider is MockDevProcessManager { sampleActions = MockDevProcessManager.sampleActions }
  }

  var state: DevServersState {
    DevServersState(actions: actions, servers: provider.servers, detected: detected)
  }

  private var actions: [DevAction] {
    sampleActions ?? storage.settings.devActions.actions
  }

  func activate() {
    provider.onChange = { [weak self] in self?.push() }
    cancellable = storage.$settings
      .map(\.devActions)
      .removeDuplicates()
      .sink { [weak self] _ in self?.push() }
    push()
  }

  func stopAll() { provider.stopAll() }

  /// Les gestes à brancher sur les fenêtres du panneau.
  var commands: DevServersCommands {
    DevServersCommands(
      add: { [weak self] in self?.add(name: $0, command: $1, directory: $2) },
      delete: { [weak self] in self?.delete($0) },
      run: { [weak self] in self?.run($0) },
      stop: { [weak self] in self?.provider.stop($0) },
      restart: { [weak self] in self?.restart($0) },
      remove: { [weak self] in self?.provider.remove($0) },
      refreshDetected: { [weak self] in self?.refreshDetected() })
  }

  // MARK: - Serveurs à l'écoute

  /// Relit les serveurs à l'écoute. Un seul balayage à la fois : le suivant attend le retour du
  /// premier. Les serveurs lancés depuis l'app sont reconnus à leur groupe de processus.
  func refreshDetected() {
    guard !isScanning else { return }
    isScanning = true
    let groups = Dictionary(
      provider.servers.compactMap { server in server.pid.map { ($0, server.name) } },
      uniquingKeysWith: { first, _ in first })
    Task { [weak self, scanner] in
      let result = await scanner.detectedServers(actionGroups: groups)
      guard let self else { return }
      isScanning = false
      guard result != detected else { return }
      detected = result
      push()
    }
  }

  // MARK: - Gestes

  private func add(name: String, command: String, directory: String?) {
    let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    // Ajouter deux fois le même script du même projet ne crée pas de doublon.
    guard !actions.contains(where: { $0.command == command && $0.directory == directory }) else {
      return
    }
    let action = DevAction(
      name: trimmed.isEmpty ? command : trimmed, command: command, directory: directory)
    if sampleActions != nil {
      sampleActions?.append(action)
      push()
    } else {
      storage.settings.devActions.actions.append(action)
    }
  }

  private func delete(_ id: UUID) {
    provider.stop(id)
    provider.remove(id)
    if sampleActions != nil {
      sampleActions?.removeAll { $0.id == id }
      push()
    } else {
      storage.settings.devActions.actions.removeAll { $0.id == id }
    }
  }

  private func run(_ id: UUID) {
    guard let action = actions.first(where: { $0.id == id }) else { return }
    provider.start(action)
  }

  private func restart(_ id: UUID) {
    guard let action = actions.first(where: { $0.id == id }) else { return }
    provider.restart(action)
  }

  private func push() {
    onStateChanged?(state)
  }
}
