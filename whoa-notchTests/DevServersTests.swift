import Foundation
import Testing

@testable import whoa_notch

/// Réglages des actions : un ancien blob, une action abîmée, un aller-retour.
@MainActor
struct DevActionSettingsTests {

  private func decode(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
  }

  @Test("un blob sans la clé des actions garde la liste vide")
  func missingKeyKeepsEmptyList() throws {
    let settings = try decode(#"{"dock":{"autoHide":false}}"#)
    #expect(settings.devActions.actions.isEmpty)
  }

  @Test("une action abîmée est écartée, les autres restent")
  func damagedActionIsDropped() throws {
    let json = """
      {"devActions":{"actions":[
        {"name":"Dev","command":"pnpm dev"},
        {"name":"Sans commande"},
        {"name":"Tests","command":"pnpm test","directory":"/tmp"}
      ]}}
      """
    let actions = try decode(json).devActions.actions
    #expect(actions.map(\.name) == ["Dev", "Tests"])
    #expect(actions[1].directory == "/tmp")
  }

  @Test("les actions survivent à un aller-retour JSON")
  func actionsRoundTrip() throws {
    var settings = AppSettings()
    settings.devActions.actions = [DevAction(name: "Dev", command: "pnpm dev", directory: "/tmp")]
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
  }
}

/// Les vrais processus : lancement, sortie, arrêt du groupe entier, code de sortie.
@MainActor
struct DevProcessManagerTests {

  /// Attend que `condition` soit vraie, au plus `seconds` secondes.
  private func wait(_ seconds: Double = 5, until condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
  }

  @Test("une commande qui se termine donne son code de sortie et sa sortie")
  func finishedCommandKeepsExitCodeAndOutput() async {
    let manager = DevProcessManager()
    let action = DevAction(name: "Écho", command: "echo bonjour; exit 3")
    manager.start(action)
    // La sortie peut arriver un instant après la fin du processus.
    await wait { manager.servers.first?.isRunning == false && manager.servers.first?.output.isEmpty == false }

    let server = manager.servers.first
    #expect(server?.exitCode == 3)
    #expect(server?.output.contains("bonjour") == true)
  }

  @Test("arrêter un serveur arrête aussi ses enfants")
  func stopKillsTheWholeGroup() async throws {
    let manager = DevProcessManager()
    // Le shell lance un enfant (`sleep`) et attend : sans groupe de processus, il survivrait.
    let action = DevAction(name: "Long", command: "sleep 600 & echo $!; wait")
    manager.start(action)
    await wait { manager.servers.first?.output.isEmpty == false }
    let child = try #require(Int32(manager.servers.first?.output.first ?? ""))
    #expect(kill(child, 0) == 0)

    manager.stop(action.id)
    await wait { manager.servers.first?.isRunning == false }
    await wait { kill(child, 0) != 0 }

    #expect(manager.servers.first?.isRunning == false)
    #expect(kill(child, 0) != 0)
  }

  @Test("relancer un serveur en cours le remplace par un nouveau processus")
  func restartReplacesTheProcess() async {
    let manager = DevProcessManager()
    let action = DevAction(name: "Long", command: "sleep 600")
    manager.start(action)
    let first = manager.servers.first?.pid
    manager.restart(action)
    await wait { manager.servers.first?.isRunning == true && manager.servers.first?.pid != first }

    #expect(manager.servers.count == 1)
    #expect(manager.servers.first?.pid != first)
    manager.stopAll()
  }

  @Test("une action déjà en cours n'est pas lancée une seconde fois")
  func startIsIdempotentWhileRunning() async {
    let manager = DevProcessManager()
    let action = DevAction(name: "Long", command: "sleep 600")
    manager.start(action)
    let pid = manager.servers.first?.pid
    manager.start(action)

    #expect(manager.servers.count == 1)
    #expect(manager.servers.first?.pid == pid)
    manager.stopAll()
  }

  @Test("un serveur arrêté s'oublie, un serveur en cours non")
  func removeOnlyForgetsStoppedServers() async {
    let manager = DevProcessManager()
    let action = DevAction(name: "Long", command: "sleep 600")
    manager.start(action)
    manager.remove(action.id)
    #expect(manager.servers.count == 1)

    manager.stop(action.id)
    await wait { manager.servers.first?.isRunning == false }
    manager.remove(action.id)
    #expect(manager.servers.isEmpty)
  }
}
