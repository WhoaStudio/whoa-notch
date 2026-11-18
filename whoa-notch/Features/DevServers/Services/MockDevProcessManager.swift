import Foundation

/// Serveurs simulés : l'état change comme avec de vrais processus, mais rien n'est lancé.
final class MockDevProcessManager: DevProcessProviding {

  private(set) var servers: [DevServer] = []
  var onChange: (() -> Void)?

  /// `--dev-servers=sample` : un serveur déjà en cours et un autre arrêté ; sinon `nil`.
  static func fromLaunchArguments() -> MockDevProcessManager? {
    guard CommandLine.arguments.contains("--dev-servers=sample") else { return nil }
    let mock = MockDevProcessManager()
    mock.servers = sampleActions.prefix(2).enumerated().map { index, action in
      var server = DevServer(
        id: action.id, name: action.name, command: action.command, directory: nil,
        pid: index == 0 ? 4242 : nil, startedAt: Date().addingTimeInterval(-134))
      server.output = ["ready in 312 ms", "Local: http://localhost:5173/"]
      if index == 1 { server.exitCode = 0 }
      return server
    }
    return mock
  }

  /// Actions montrées avec `--dev-servers=sample`, sans toucher aux réglages.
  static let sampleActions = [
    DevAction(name: "dev", command: "pnpm dev", directory: "/Users/sample/Developer/portfolio"),
    DevAction(name: "test", command: "pnpm test", directory: "/Users/sample/Developer/portfolio"),
    DevAction(name: "Start local DB", command: "docker compose up db"),
  ]

  func start(_ action: DevAction) {
    var server = DevServer(
      id: action.id, name: action.name, command: action.command, directory: action.directory,
      pid: Int32.random(in: 2000...9000), startedAt: Date())
    server.output = ["started"]
    replace(server)
  }

  func stop(_ id: UUID) {
    guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
    servers[index].pid = nil
    servers[index].exitCode = 143
    onChange?()
  }

  func restart(_ action: DevAction) { start(action) }

  func remove(_ id: UUID) {
    servers.removeAll { $0.id == id && !$0.isRunning }
    onChange?()
  }

  func stopAll() {}

  private func replace(_ server: DevServer) {
    if let index = servers.firstIndex(where: { $0.id == server.id }) {
      servers[index] = server
    } else {
      servers.append(server)
    }
    onChange?()
  }
}
