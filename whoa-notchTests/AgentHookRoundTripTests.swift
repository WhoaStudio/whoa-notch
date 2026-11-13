import Foundation
import Testing

@testable import whoa_notch

/// Le vrai script de hook (`ClaudeHookInstaller.scriptContents`), lancé comme Claude Code le fait,
/// contre un vrai `AgentHookServer` sur un socket temporaire : de la ligne JSON du hook jusqu'à la
/// réponse qu'il imprime pour Claude Code.
@Suite(.serialized) struct AgentHookRoundTripTests {

  /// Un `HOME` temporaire, court (`sun_path` tient en 104 octets), où le script trouve son socket.
  /// Ce que le serveur remet au main actor : seuls les rappels du main actor y écrivent, le test lit sur lui aussi.
  private final class Recorder: @unchecked Sendable {
    var events: [AgentEvent] = []
    var cancelled: [String] = []
  }

  private final class Harness {
    let home: URL
    let script: URL
    let server: AgentHookServer
    private let recorder: Recorder
    var events: [AgentEvent] { recorder.events }
    var cancelled: [String] { recorder.cancelled }

    init(listening: Bool = true) throws {
      home = URL(fileURLWithPath: "/tmp/ws\(UUID().uuidString.prefix(6))")
      let support = home.appendingPathComponent("Library/Application Support/whoa-notch")
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      script = support.appendingPathComponent("whoa-hook")
      try ClaudeHookInstaller.scriptContents.write(to: script, atomically: true, encoding: .utf8)
      server = AgentHookServer(socketPath: support.appendingPathComponent("agent.sock").path)
      let recorder = Recorder()
      self.recorder = recorder
      server.onEvent = { recorder.events.append($0) }
      server.onCancel = { recorder.cancelled.append($0) }
      if listening { server.start() }
    }

    deinit {
      server.stop()
      try? FileManager.default.removeItem(at: home)
    }

    /// Lance le script comme Claude Code : l'argument en `$1`, le JSON du hook sur l'entrée.
    func run(_ kind: String, payload: String, entrypoint: String? = nil) throws -> Running {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = [script.path, kind]
      var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
      if let entrypoint { environment["CLAUDE_CODE_ENTRYPOINT"] = entrypoint }
      process.environment = environment
      let input = Pipe()
      let output = Pipe()
      process.standardInput = input
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      try process.run()
      input.fileHandleForWriting.write(Data(payload.utf8))
      try input.fileHandleForWriting.close()
      return Running(process: process, output: output)
    }

    /// Attend qu'une condition du main actor soit vraie, au plus `timeout`.
    func wait(timeout: Duration = .seconds(5), until condition: () -> Bool) async -> Bool {
      let deadline = ContinuousClock.now + timeout
      while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
      }
      return condition()
    }
  }

  private final class Running {
    let process: Process
    let output: Pipe
    init(process: Process, output: Pipe) {
      self.process = process
      self.output = output
    }

    /// Ce que le script a imprimé, une fois sorti ; `nil` s'il tourne encore après `timeout`.
    func finished(within timeout: Duration = .seconds(5)) async -> String? {
      let deadline = ContinuousClock.now + timeout
      while process.isRunning, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
      }
      guard !process.isRunning else { return nil }
      let data = output.fileHandleForReading.readDataToEndOfFile()
      return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private func object(_ text: String?) throws -> [String: Any] {
    let data = try #require(text).data(using: .utf8)!
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // MARK: - Permission

  @Test("une permission autorisée dans l'encoche revient à Claude Code")
  func permissionRoundTrip() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "permission",
      payload:
        #"{"session_id":"s","cwd":"/Users/x/korus","tool_name":"Bash","tool_input":{"command":"git push"},"permission_suggestions":[{"type":"addRules","behavior":"allow","destination":"localSettings","rules":[{"toolName":"Bash","ruleContent":"git push"}]}]}"#
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.prompt == .tool(name: "Bash", detail: "git push"))
    #expect(event.offersAlways)
    // La demande attend : le script ne s'est pas terminé tout seul.
    #expect(running.process.isRunning)

    harness.server.reply(to: try #require(event.replyID), json: try #require(event.replyJSON(for: .allowAlways)))
    let printed = try object(await running.finished())
    let decision = try #require(
      (printed["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    #expect(decision["behavior"] as? String == "allow")
    #expect((decision["updatedPermissions"] as? [Any])?.count == 1)
  }

  @Test("fermer le script (réponse donnée dans le terminal) lève la demande")
  func hangingUpCancelsThePrompt() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "permission", payload: #"{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
    #expect(await harness.wait { !harness.events.isEmpty })
    let id = try #require(harness.events.first?.replyID)
    running.process.terminate()
    #expect(await harness.wait { harness.cancelled == [id] })
  }

  @Test("un plan approuvé en mode auto renvoie son entrée et le mode de la session")
  func planRoundTrip() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "permission",
      payload:
        ###"{"session_id":"s","tool_name":"ExitPlanMode","tool_input":{"plan":"## Refaire le login\n1. Un"}}"###
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.prompt == .plan(title: "Refaire le login", body: "## Refaire le login\n1. Un"))
    harness.server.reply(to: try #require(event.replyID), json: try #require(event.replyJSON(for: .plan(.auto))))
    let printed = try object(await running.finished())
    let decision = try #require(
      (printed["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    #expect((decision["updatedInput"] as? [String: Any])?["plan"] != nil)
    let updates = try #require(decision["updatedPermissions"] as? [[String: Any]])
    #expect(updates.first?["mode"] as? String == "auto")
  }

  // MARK: - Question, formulaire

  @Test("un choix multiple répondu dans l'encoche arrive à AskUserQuestion")
  func questionRoundTrip() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "question",
      payload:
        #"{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Quoi ?","header":"Q","multiSelect":true,"options":[{"label":"A","description":""},{"label":"B","description":""}]}]}}"#
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.response == .question)
    harness.server.reply(
      to: try #require(event.replyID),
      json: try #require(event.replyJSON(for: .answer(["Quoi ?": ["A", "B"]]))))
    let output = try #require(
      (try object(await running.finished()))["hookSpecificOutput"] as? [String: Any])
    #expect(output["permissionDecision"] as? String == "allow")
    let input = try #require(output["updatedInput"] as? [String: Any])
    #expect((input["answers"] as? [String: String])?["Quoi ?"] == "A, B")
    #expect((input["questions"] as? [Any])?.count == 1)
  }

  @Test("« Reply in terminal » rend la main : le script n'imprime que {}")
  func handBackPrintsAnEmptyObject() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "question",
      payload:
        #"{"session_id":"s","tool_input":{"questions":[{"question":"Q ?","options":[{"label":"A"},{"label":"B"}]}]}}"#
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    harness.server.reply(to: try #require(event.replyID), json: try #require(event.replyJSON(for: .handBack)))
    #expect(await running.finished() == "{}")
  }

  @Test("une question sans réponse est rendue à Claude Code après le délai")
  func unansweredQuestionIsHandedBack() async throws {
    let harness = try Harness()
    harness.server.questionWait = 0.4
    let running = try harness.run(
      "question",
      payload:
        #"{"session_id":"s","tool_input":{"questions":[{"question":"Q ?","options":[{"label":"A"},{"label":"B"}]}]}}"#
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let id = try #require(harness.events.first?.replyID)
    #expect(await running.finished() == "{}")
    #expect(await harness.wait { harness.cancelled == [id] })
  }

  @Test("un formulaire MCP rempli dans l'encoche revient en accept avec ses valeurs")
  func elicitationRoundTrip() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "elicit",
      payload:
        #"{"session_id":"s","mcp_server_name":"jira","message":"Clé ?","mode":"form","requested_schema":{"type":"object","properties":{"key":{"type":"string"}}}}"#
    )
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.response == .elicitation)
    harness.server.reply(
      to: try #require(event.replyID),
      json: try #require(event.replyJSON(for: .answer(["Clé ?": ["DOCS"]]))))
    let output = try #require(
      (try object(await running.finished()))["hookSpecificOutput"] as? [String: Any])
    #expect(output["hookEventName"] as? String == "Elicitation")
    #expect(output["action"] as? String == "accept")
    #expect((output["content"] as? [String: Any])?["key"] as? String == "DOCS")
  }

  @Test("un formulaire en mode URL n'ouvre aucune carte")
  func urlElicitationIsIgnored() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "elicit", payload: #"{"session_id":"s","mode":"url","url":"https://x.test","message":"Connexion"}"#)
    #expect(await running.finished() == "")
    #expect(harness.events.isEmpty)
  }

  // MARK: - Réponse libre après un tour

  private let stopPayload =
    #"{"session_id":"s","cwd":"/Users/x/korus","stop_hook_active":false,"last_assistant_message":"Fini."}"#

  @Test("réponse libre désactivée : un Stop passe sans attendre")
  func stopIsNotHeldByDefault() async throws {
    let harness = try Harness()
    let running = try harness.run("stop", payload: stopPayload)
    #expect(await running.finished(within: .seconds(2)) == "")
    #expect(await harness.wait { !harness.events.isEmpty })
    #expect(harness.events.first?.replyID == nil)
    #expect(harness.events.first?.kind == .finished)
  }

  @Test("réponse libre activée : le texte tapé fait repartir Claude par le hook Stop")
  func stopReplyRoundTrip() async throws {
    let harness = try Harness()
    harness.server.setStopReplyEnabled(true)
    let running = try harness.run("stop", payload: stopPayload)
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.prompt == .reply("Fini."))
    // Retenu : le script attend la réponse.
    try await Task.sleep(for: .milliseconds(600))
    #expect(running.process.isRunning)

    harness.server.reply(
      to: try #require(event.replyID), json: try #require(event.replyJSON(for: .reply("ajoute un test"))))
    let printed = try object(await running.finished())
    #expect(printed["decision"] as? String == "block")
    #expect((printed["reason"] as? String)?.hasSuffix("ajoute un test") == true)
  }

  @Test("sans réponse, la fin de tour se libère d'elle-même et Claude s'arrête")
  func unansweredStopReplyIsReleased() async throws {
    let harness = try Harness()
    harness.server.setStopReplyEnabled(true)
    harness.server.stopReplyWait = 0.5
    let running = try harness.run("stop", payload: stopPayload)
    #expect(await harness.wait { !harness.events.isEmpty })
    let id = try #require(harness.events.first?.replyID)
    // Le serveur rend `{}` : le script l'imprime, Claude Code n'y voit aucune décision.
    #expect(await running.finished() == "{}")
    #expect(await harness.wait { harness.cancelled == [id] })
  }

  @Test("un Stop déjà prolongé par un hook n'est jamais retenu")
  func continuedStopIsNeverHeld() async throws {
    let harness = try Harness()
    harness.server.setStopReplyEnabled(true)
    let payload = stopPayload.replacingOccurrences(
      of: "\"stop_hook_active\":false", with: "\"stop_hook_active\":true")
    let running = try harness.run("stop", payload: payload)
    #expect(await running.finished(within: .seconds(2)) == "")
    #expect(await harness.wait { !harness.events.isEmpty })
    #expect(harness.events.first?.replyID == nil)
  }

  // MARK: - Claude Desktop, app absente

  @Test("une session de Claude Desktop arrive étiquetée Claude Desktop")
  func desktopSessionIsTagged() async throws {
    let harness = try Harness()
    let running = try harness.run(
      "permission", payload: #"{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#,
      entrypoint: "claude-desktop")
    #expect(await harness.wait { !harness.events.isEmpty })
    let event = try #require(harness.events.first)
    #expect(event.source == .claudeDesktop)
    #expect(event.project == "Claude Desktop")
    running.process.terminate()
  }

  @Test("sans l'app, le script sort tout de suite et n'imprime rien")
  func scriptWithoutTheAppDoesNothing() async throws {
    let harness = try Harness(listening: false)
    for kind in ["permission", "question", "elicit", "stop"] {
      let running = try harness.run(kind, payload: #"{"session_id":"s","tool_name":"Bash"}"#)
      #expect(await running.finished(within: .seconds(2)) == "", "\(kind)")
    }
  }

  // MARK: - Consignes en cours de route

  private final class Delivered: @unchecked Sendable {
    var items: [String] = []
  }

  @Test("une consigne pour la session A sort par son hook PostToolUse, et B ne reçoit rien")
  func steerReachesOnlyItsSession() async throws {
    let harness = try Harness()
    let delivered = Delivered()
    harness.server.onSteerDelivered = { session, text in delivered.items.append("\(session):\(text)") }
    harness.server.steer(sessionID: "A", text: "use yarn, not npm")

    let other = try harness.run(
      "post", payload: #"{"session_id":"B","cwd":"/Users/x/b","tool_name":"Bash"}"#)
    #expect(await other.finished() == "")

    let target = try harness.run(
      "post", payload: #"{"session_id":"A","cwd":"/Users/x/a","tool_name":"Bash"}"#)
    let printed = try object(await target.finished())
    let output = try #require(printed["hookSpecificOutput"] as? [String: Any])
    #expect(output["hookEventName"] as? String == "PostToolUse")
    #expect((output["additionalContext"] as? String)?.contains("use yarn, not npm") == true)
    #expect(await harness.wait { delivered.items == ["A:use yarn, not npm"] })

    // Remise une fois : le hook suivant de A n'a plus rien à rendre.
    let again = try harness.run(
      "post", payload: #"{"session_id":"A","cwd":"/Users/x/a","tool_name":"Read"}"#)
    #expect(await again.finished() == "")
  }
}
