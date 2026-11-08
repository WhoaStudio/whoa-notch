import Foundation
import Testing

@testable import whoa_stash

@Suite struct AgentPromptTests {

  private func decode(_ json: String) -> AgentEvent? {
    AgentEvent.decode(Data(json.utf8))
  }

  @Test func permissionPorteLaCommandeEtLaSession() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"session_id":"s1","cwd":"/Users/x/korus","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}}"#
      ))
    #expect(event.kind == .needsInput)
    #expect(event.project == "korus")
    #expect(event.sessionID == "s1")
    #expect(event.prompt == .tool(name: "Bash", detail: "rm -rf node_modules"))
  }

  @Test func permissionSurUnFichierMontreLeChemin() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"tool_name":"Edit","tool_input":{"file_path":"/a/b.swift","old_string":"x"}}}"#
      ))
    #expect(event.prompt == .tool(name: "Edit", detail: "/a/b.swift"))
  }

  @Test func questionPorteLesChoix() throws {
    let event = try #require(
      decode(
        #"{"kind":"question","payload":{"session_id":"s1","tool_input":{"questions":[{"question":"Quel framework ?","header":"F","multiSelect":false,"options":[{"label":"React","description":"UI"},{"label":"Vue","description":""}]}]}}}"#
      ))
    let expected = AgentEvent.Question(
      text: "Quel framework ?",
      options: [.init(label: "React", detail: "UI"), .init(label: "Vue", detail: "")],
      multiSelect: false)
    #expect(event.prompt == .questions([expected]))
  }

  @Test func questionSansChoixNiQuestionEstIgnoree() {
    #expect(decode(#"{"kind":"question","payload":{"tool_input":{}}}"#) == nil)
  }

  @Test func inactiviteNEstPasUneDemandePersistante() throws {
    let event = try #require(
      decode(
        #"{"kind":"notify","payload":{"notification_type":"idle_prompt","message":"waiting"}}"#))
    #expect(event.kind == .needsInput)
    #expect(event.prompt == nil)
  }

  @Test func notificationDePermissionGardeSonTexte() throws {
    let event = try #require(
      decode(
        #"{"kind":"notify","payload":{"notification_type":"permission_prompt","message":"Claude needs your permission"}}"#
      ))
    #expect(event.prompt == .message("Claude needs your permission"))
  }

  @Test func messageEtkindInconnusSontIgnores() {
    #expect(decode("pas du json") == nil)
    #expect(decode(#"{"kind":"autre","payload":{}}"#) == nil)
  }

  // MARK: - AgentPromptStore

  private func ask(_ session: String?, _ detail: String = "ls") -> AgentEvent {
    AgentEvent(
      kind: .needsInput, project: "p", sessionID: session,
      prompt: .tool(name: "Bash", detail: detail))
  }

  @Test func laDemandeLaPlusRecenteEstMontree() {
    var store = AgentPromptStore()
    store.apply(ask("a", "un"))
    store.apply(ask("b", "deux"))
    #expect(store.current?.prompt == .tool(name: "Bash", detail: "deux"))
  }

  @Test func unEvenementDeLaSessionLeveLaDemande() {
    var store = AgentPromptStore()
    store.apply(ask("a"))
    let changed = store.apply(AgentEvent(kind: .clear, project: "p", sessionID: "a"))
    #expect(changed)
    #expect(store.current == nil)
  }

  @Test func laFinDUneSessionLeveSaDemandeMaisPasCelleDUneAutre() {
    var store = AgentPromptStore()
    store.apply(ask("a"))
    store.apply(ask("b"))
    store.apply(AgentEvent(kind: .finished, project: "p", sessionID: "b"))
    #expect(store.current?.sessionID == "a")
  }

  @Test func uneNotificationDoubleNEcrasePasLaDemandeDetaillee() {
    var store = AgentPromptStore()
    store.apply(ask("a", "git push"))
    let doubled = AgentEvent(
      kind: .needsInput, project: "p", sessionID: "a", prompt: .message("needs permission"))
    let changed = store.apply(doubled)
    #expect(!changed)
    #expect(store.current?.prompt == .tool(name: "Bash", detail: "git push"))
  }

  @Test func claudeDesktopNeLevePasLesDemandesDeCode() {
    var store = AgentPromptStore()
    store.apply(ask("a"))
    let changed = store.apply(AgentEvent(kind: .desktopReply, project: "Claude"))
    #expect(!changed)
    #expect(store.current != nil)
  }

  @Test func clearSansSessionLeveLaDemandeSimulee() {
    var store = AgentPromptStore()
    store.apply(ask(nil))
    store.apply(AgentEvent(kind: .clear, project: "p"))
    #expect(store.current == nil)
  }

  @Test func uneDemandeAncienneExpire() {
    var store = AgentPromptStore()
    let start = Date(timeIntervalSince1970: 1_000)
    store.apply(ask("a"), now: start)
    store.apply(ask("b"), now: start.addingTimeInterval(500))
    let changed = store.expire(before: start.addingTimeInterval(100))
    #expect(changed)
    #expect(store.current?.sessionID == "b")
    let again = store.expire(before: start.addingTimeInterval(100))
    #expect(!again)
  }

  // MARK: - Réponses depuis l'encoche

  private func json(_ text: String?) throws -> [String: Any] {
    let data = try #require(text).data(using: .utf8)!
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func laPermissionAUnIdentifiantDeReponse() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}}"#
      ))
    #expect(event.replyID != nil)
  }

  @Test func askUserQuestionVueParPermissionDonneSesQuestions() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Couleur ?","options":[{"label":"Rouge","description":""}]}]}}}"#
      ))
    guard case .questions(let questions) = event.prompt else {
      Issue.record("pas de questions")
      return
    }
    #expect(questions.first?.text == "Couleur ?")
    #expect(event.replyID != nil)
  }

  @Test func autoriserEtRefuserProduisentLaDecisionDeClaudeCode() throws {
    let event = try #require(
      decode(#"{"kind":"permission","payload":{"tool_name":"Bash","tool_input":{"command":"ls"}}}"#)
    )
    let allow = try json(event.replyJSON(for: .allow))
    let output = try #require(allow["hookSpecificOutput"] as? [String: Any])
    #expect(output["hookEventName"] as? String == "PermissionRequest")
    #expect((output["decision"] as? [String: Any])?["behavior"] as? String == "allow")
    let deny = try json(event.replyJSON(for: .deny))
    let denied = try #require(
      (deny["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    #expect(denied["behavior"] as? String == "deny")
  }

  @Test func repondreAUneQuestionRenvoieLEntreeAvecSesReponses() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Couleur ?","options":[{"label":"Rouge","description":""}]}]}}}"#
      ))
    let reply = try json(event.replyJSON(for: .answer(["Couleur ?": "Rouge"])))
    let decision = try #require(
      (reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    let input = try #require(decision["updatedInput"] as? [String: Any])
    #expect((input["answers"] as? [String: String])?["Couleur ?"] == "Rouge")
    #expect((input["questions"] as? [Any])?.count == 1)
  }

  @Test func uneReponseQuiNeRenvoiePasLEntreeEstRefusee() {
    let event = AgentEvent(kind: .needsInput, project: "p", replyID: "x")
    #expect(event.replyJSON(for: .answer(["a": "b"])) == nil)
  }

  @Test func laVersionAffichageSeuleNEcrasePasLaDemandeRepondable() {
    var store = AgentPromptStore()
    var answerable = ask("a", "git push")
    answerable.replyID = "r1"
    store.apply(answerable)
    let changed = store.apply(ask("a", "git push"))
    #expect(!changed)
    #expect(store.current?.replyID == "r1")
  }

  @Test func laDemandeSeLeveAvecSonIdentifiantDeReponse() {
    var store = AgentPromptStore()
    var answerable = ask("a")
    answerable.replyID = "r1"
    store.apply(answerable)
    let unknown = store.remove(replyID: "autre")
    #expect(!unknown)
    let removed = store.remove(replyID: "r1")
    #expect(removed)
    #expect(store.current == nil)
  }
}
