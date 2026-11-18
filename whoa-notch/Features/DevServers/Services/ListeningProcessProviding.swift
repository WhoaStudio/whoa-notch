import Foundation

/// Les serveurs de développement à l'écoute sur un port, groupés par projet. Lecture seule :
/// aucun processus n'est jamais arrêté ni relancé.
protocol ListeningProcessProviding: Sendable {
  /// - Parameter actionGroups: chef de groupe de processus → nom de l'action de l'app, pour
  ///   reconnaître les serveurs lancés depuis l'onglet Actions.
  nonisolated func detectedServers(actionGroups: [Int32: String]) async -> [DetectedServerGroup]
}

/// `--listening-servers=sample` : un Next.js et un NestJS dans deux projets, un Postgres sans
/// projet, sans rien lire sur la machine.
nonisolated struct MockListeningProcessProvider: ListeningProcessProviding {

  static func fromLaunchArguments() -> MockListeningProcessProvider? {
    CommandLine.arguments.contains("--listening-servers=sample")
      ? MockListeningProcessProvider() : nil
  }

  func detectedServers(actionGroups: [Int32: String]) async -> [DetectedServerGroup] {
    [
      DetectedServerGroup(
        name: "api", path: "/Users/sample/Developer/api",
        servers: [
          DetectedServer(pid: 5102, processName: "node", framework: .nestjs, ports: [3001])
        ]),
      DetectedServerGroup(
        name: "portfolio", path: "/Users/sample/Developer/portfolio",
        servers: [
          DetectedServer(
            pid: 5101, processName: "node", framework: .nextjs, ports: [3000],
            actionName: "Start dev server")
        ]),
      DetectedServerGroup(
        name: DetectedServerGroup.systemName, path: nil,
        servers: [
          DetectedServer(pid: 5103, processName: "postgres", framework: .postgres, ports: [5432])
        ]),
    ]
  }
}
