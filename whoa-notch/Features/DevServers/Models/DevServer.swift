import Foundation

/// Un processus lancé depuis une action : en cours (`pid`) ou arrêté (`exitCode`).
struct DevServer: Equatable, Identifiable, Sendable {
  /// Identifiant de l'action d'origine : une action n'a qu'un serveur à la fois.
  let id: UUID
  var name: String
  var command: String
  var directory: String?
  var pid: Int32?
  var startedAt: Date
  var exitCode: Int32?
  /// Arrêt demandé, en attente de la fin du processus.
  var isStopping = false
  /// Dernières lignes écrites (stdout et stderr), les plus récentes à la fin.
  var output: [String] = []

  var isRunning: Bool { pid != nil }
}

/// Ce que montrent les onglets Actions et Servers.
struct DevServersState: Equatable, Sendable {
  var actions: [DevAction] = []
  var servers: [DevServer] = []
  /// Serveurs de développement à l'écoute en ce moment, groupés par projet (lecture seule).
  var detected: [DetectedServerGroup] = []

  func server(for action: DevAction) -> DevServer? {
    servers.first { $0.id == action.id }
  }
}

/// Les gestes des onglets Actions et Servers, branchés par `AppDelegate` sur le modèle.
struct DevServersCommands {
  var add: (_ name: String, _ command: String, _ directory: String?) -> Void = { _, _, _ in }
  var delete: (UUID) -> Void = { _ in }
  var run: (UUID) -> Void = { _ in }
  var stop: (UUID) -> Void = { _ in }
  var restart: (UUID) -> Void = { _ in }
  var remove: (UUID) -> Void = { _ in }
  /// Relit les serveurs à l'écoute ; appelé par la page Actions tant qu'elle est visible.
  var refreshDetected: () -> Void = {}
}
