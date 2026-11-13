import Foundation
import Testing

@testable import whoa_notch

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
    let reply = try json(event.replyJSON(for: .answer(["Couleur ?": ["Rouge"]])))
    let decision = try #require(
      (reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    let input = try #require(decision["updatedInput"] as? [String: Any])
    #expect((input["answers"] as? [String: String])?["Couleur ?"] == "Rouge")
    #expect((input["questions"] as? [Any])?.count == 1)
  }

  @Test func uneReponseQuiNeRenvoiePasLEntreeEstRefusee() {
    let event = AgentEvent(kind: .needsInput, project: "p", replyID: "x")
    #expect(event.replyJSON(for: .answer(["a": ["b"]])) == nil)
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

  // MARK: - Always, plan, questions à choix multiple

  private func output(_ event: AgentEvent, _ decision: AgentEvent.Decision) throws -> [String: Any] {
    try #require(
      try json(event.replyJSON(for: decision))["hookSpecificOutput"] as? [String: Any])
  }

  @Test func alwaysReprendLesReglesProposeesParClaude() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","payload":{"tool_name":"Bash","tool_input":{"command":"npm test"},"permission_suggestions":[{"type":"addRules","behavior":"allow","destination":"localSettings","rules":[{"toolName":"Bash","ruleContent":"npm test"}]}]}}"#
      ))
    #expect(event.offersAlways)
    let decision = try #require(try output(event, .allowAlways)["decision"] as? [String: Any])
    #expect(decision["behavior"] as? String == "allow")
    let rules = try #require(decision["updatedPermissions"] as? [[String: Any]])
    #expect(rules.first?["type"] as? String == "addRules")
    // Un simple « Allow » n'en retient aucune.
    let plain = try #require(try output(event, .allow)["decision"] as? [String: Any])
    #expect(plain["updatedPermissions"] == nil)
  }

  @Test func sansRegleProposeeAlwaysNEstPasOffert() throws {
    let event = try #require(
      decode(#"{"kind":"permission","payload":{"tool_name":"Bash","tool_input":{"command":"ls"}}}"#)
    )
    #expect(!event.offersAlways)
    let decision = try #require(try output(event, .allowAlways)["decision"] as? [String: Any])
    #expect(decision["updatedPermissions"] == nil)
  }

  private let planJSON =
    ###"{"kind":"permission","payload":{"session_id":"s","tool_name":"ExitPlanMode","tool_input":{"plan":"## Refaire le login\n1. Extraire l'état\n2. Ajouter un store","planFilePath":"/tmp/p.md"}}}"###

  @Test func unPlanMontreSonTitreEtSonTexte() throws {
    let event = try #require(decode(planJSON))
    guard case .plan(let title, let body) = event.prompt else {
      Issue.record("pas un plan")
      return
    }
    #expect(title == "Refaire le login")
    #expect(body.contains("Ajouter un store"))
    #expect(event.replyID != nil)
  }

  @Test func autoriserUnPlanRenvoieSonEntreeSansQuoiClaudeLIgnore() throws {
    let event = try #require(decode(planJSON))
    let decision = try #require(try output(event, .allow)["decision"] as? [String: Any])
    let input = try #require(decision["updatedInput"] as? [String: Any])
    #expect(input["planFilePath"] as? String == "/tmp/p.md")
  }

  @Test func leChoixDuPlanFixeLeModeDeLaSession() throws {
    let event = try #require(decode(planJSON))
    for (choice, mode) in [(AgentEvent.PlanChoice.auto, "auto"), (.manual, "default")] {
      let decision = try #require(try output(event, .plan(choice))["decision"] as? [String: Any])
      #expect(decision["behavior"] as? String == "allow")
      #expect(decision["updatedInput"] != nil)
      let updates = try #require(decision["updatedPermissions"] as? [[String: Any]])
      #expect(updates.first?["type"] as? String == "setMode")
      #expect(updates.first?["mode"] as? String == mode)
      #expect(updates.first?["destination"] as? String == "session")
    }
    let change = try #require(try output(event, .plan(.change))["decision"] as? [String: Any])
    #expect(change["behavior"] as? String == "deny")
    #expect(change["interrupt"] as? Bool == true)
  }

  @Test func leChoixDUnPlanNEstPasUneReponseAUnOutil() throws {
    let event = try #require(
      decode(#"{"kind":"permission","payload":{"tool_name":"Bash","tool_input":{"command":"ls"}}}"#)
    )
    #expect(event.replyJSON(for: .plan(.auto)) == nil)
  }

  private let questionsJSON =
    #"{"kind":"question","payload":{"session_id":"s","tool_input":{"questions":[{"question":"Quelles vérifications ?","header":"V","multiSelect":true,"options":[{"label":"Lint","description":""},{"label":"Types","description":""}]},{"question":"Où ?","header":"O","multiSelect":false,"options":[{"label":"Terminal","description":""},{"label":"Fichier","description":""}]}]}}}"#

  @Test func laQuestionDuHookPreToolUseAttendUneReponse() throws {
    let event = try #require(decode(questionsJSON))
    #expect(event.replyID != nil)
    #expect(event.response == .question)
  }

  @Test func reponseAuHookPreToolUseRenvoieLesQuestionsEtLesReponses() throws {
    let event = try #require(decode(questionsJSON))
    let answers = ["Quelles vérifications ?": ["Lint", "Types"], "Où ?": ["Fichier"]]
    let out = try output(event, .answer(answers))
    #expect(out["hookEventName"] as? String == "PreToolUse")
    #expect(out["permissionDecision"] as? String == "allow")
    let input = try #require(out["updatedInput"] as? [String: Any])
    #expect((input["questions"] as? [Any])?.count == 2)
    let joined = try #require(input["answers"] as? [String: String])
    // Un choix multiple joint ses libellés ; un choix simple reste tel quel.
    #expect(joined["Quelles vérifications ?"] == "Lint, Types")
    #expect(joined["Où ?"] == "Fichier")
  }

  @Test func rendreLaMainLaisseClaudeCodeDemanderLuiMeme() throws {
    for json in [questionsJSON, planJSON] {
      let event = try #require(decode(json))
      #expect(event.replyJSON(for: .handBack) == "{}")
    }
  }

  // MARK: - Formulaires MCP (Elicitation)

  private let elicitJSON =
    #"{"kind":"elicit","payload":{"session_id":"s","cwd":"/Users/x/korus","mcp_server_name":"jira","message":"Créer un ticket","mode":"form","requested_schema":{"type":"object","required":["key"],"properties":{"key":{"type":"string","title":"Clé du projet"},"priority":{"type":"string","enum":["Low","High"]},"notify":{"type":"boolean"},"points":{"type":"integer"}}}}}"#

  @Test func unFormulaireMCPDevientUneQuestionParChamp() throws {
    let event = try #require(decode(elicitJSON))
    #expect(event.response == .elicitation)
    #expect(event.replyID != nil)
    guard case .questions(let questions) = event.prompt else {
      Issue.record("pas de questions")
      return
    }
    // Dans l'ordre des clés : key, notify, points, priority.
    #expect(questions.map(\.field) == ["key", "notify", "points", "priority"])
    #expect(questions[0].freeText)
    #expect(questions[0].text == "Clé du projet — Créer un ticket")
    #expect(questions[1].options.map(\.label) == ["Yes", "No"])
    #expect(questions[2].fieldType == .integer)
    #expect(questions[3].options.map(\.label) == ["Low", "High"])
  }

  @Test func repondreAUnFormulaireRenvoieAcceptEtLesValeursTypees() throws {
    let event = try #require(decode(elicitJSON))
    let answers = [
      "Clé du projet — Créer un ticket": ["DOCS"], "notify": ["Yes"], "points": ["3"],
      "priority": ["High"],
    ]
    let out = try output(event, .answer(answers))
    #expect(out["hookEventName"] as? String == "Elicitation")
    #expect(out["action"] as? String == "accept")
    let content = try #require(out["content"] as? [String: Any])
    #expect(content["key"] as? String == "DOCS")
    #expect(content["notify"] as? Bool == true)
    #expect(content["points"] as? Int == 3)
    #expect(content["priority"] as? String == "High")
  }

  @Test func unNombreQuiNEnEstPasUnEstRefuse() throws {
    let event = try #require(decode(elicitJSON))
    #expect(event.replyJSON(for: .answer(["points": ["3"]])) != nil)
    #expect(event.replyJSON(for: .answer(["points": ["trois"]])) == nil)
  }

  @Test func refuserUnFormulaireEnvoieDecline() throws {
    let event = try #require(decode(elicitJSON))
    let out = try output(event, .deny)
    #expect(out["action"] as? String == "decline")
  }

  @Test func unFormulaireQueLaCarteNeSaitPasMontrerEstIgnore() {
    // Mode URL, plus de quatre champs, type inconnu : Claude Code montre sa propre boîte.
    #expect(
      decode(
        #"{"kind":"elicit","payload":{"mode":"url","url":"https://x.test","message":"Connexion"}}"#)
        == nil)
    #expect(
      decode(
        #"{"kind":"elicit","payload":{"requested_schema":{"properties":{"a":{"type":"array"}}}}}"#)
        == nil)
    let five = (1...5).map { "\"f\($0)\":{\"type\":\"string\"}" }.joined(separator: ",")
    let json =
      "{\"kind\":\"elicit\",\"payload\":{\"requested_schema\":{\"properties\":{\(five)}}}}"
    #expect(decode(json) == nil)
  }

  // MARK: - Réponse libre après un tour (Stop)

  private let stopJSON =
    #"{"kind":"stop","payload":{"session_id":"s","cwd":"/Users/x/korus","stop_hook_active":false,"last_assistant_message":"J'ai refait le login.\nTests ajoutés."}}"#

  @Test func sansLaReponseLibreUneFinDeTourNAttendRien() throws {
    let event = try #require(decode(stopJSON))
    #expect(event.kind == .finished)
    #expect(event.prompt == nil)
    #expect(event.replyID == nil)
  }

  @Test func avecLaReponseLibreUneFinDeTourResteOuverte() throws {
    let event = try #require(AgentEvent.decode(Data(stopJSON.utf8), holdStopReply: true))
    #expect(event.kind == .finished)
    #expect(event.prompt == .reply("J'ai refait le login. Tests ajoutés."))
    #expect(event.replyID != nil)
    #expect(event.response == .stopReply)
  }

  @Test func unStopDejaPrisEnChargeParUnHookNEstJamaisRetenu() throws {
    let json = stopJSON.replacingOccurrences(of: "\"stop_hook_active\":false", with: "\"stop_hook_active\":true")
    let event = try #require(AgentEvent.decode(Data(json.utf8), holdStopReply: true))
    #expect(event.replyID == nil)
  }

  @Test func laReponseLibreFaitRepartirClaude() throws {
    let event = try #require(AgentEvent.decode(Data(stopJSON.utf8), holdStopReply: true))
    let reply = try json(event.replyJSON(for: .reply("  ajoute aussi un test  ")))
    #expect(reply["decision"] as? String == "block")
    #expect((reply["reason"] as? String)?.hasSuffix("ajoute aussi un test") == true)
    #expect(event.replyJSON(for: .reply("   ")) == nil)
    #expect(event.replyJSON(for: .handBack) == "{}")
  }

  // MARK: - Claude Desktop

  @Test func laSessionDeClaudeDesktopPorteSaSource() throws {
    let event = try #require(
      decode(
        #"{"kind":"permission","entrypoint":"claude-desktop","payload":{"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}}"#
      ))
    #expect(event.source == .claudeDesktop)
    #expect(event.source.label == "Claude Desktop")
    let code = try #require(
      decode(
        #"{"kind":"permission","entrypoint":"cli","payload":{"tool_name":"Bash","tool_input":{"command":"ls"}}}"#
      ))
    #expect(code.source == .claudeCode)
  }

  @Test func sansDossierLeProjetPortelaSource() throws {
    let event = try #require(
      decode(#"{"kind":"stop","entrypoint":"claude-desktop","payload":{"session_id":"s"}}"#))
    #expect(event.project == "Claude Desktop")
  }

  // MARK: - Question rendue au terminal

  @Test func uneQuestionRendueAuTerminalNeRevientPasSurLaCarte() throws {
    var store = AgentPromptStore()
    let asked = try #require(decode(questionsJSON))
    store.apply(asked)
    store.noteHandedBack(asked)
    store.remove(replyID: try #require(asked.replyID))
    // La boîte du terminal s'ouvre : le hook de permission relaie la même question.
    let relayed = try #require(
      decode(
        #"{"kind":"permission","payload":{"session_id":"s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Où ?","options":[{"label":"Terminal","description":""}]}]}}}"#
      ))
    let shownAgain = store.apply(relayed)
    #expect(!shownAgain)
    #expect(store.current == nil)
    // Un nouvel événement de la session lève la mémoire.
    store.apply(AgentEvent(kind: .turnStart, project: "p", sessionID: "s"))
    let shownAfter = store.apply(relayed)
    #expect(shownAfter)
  }

  // MARK: - Simulation

  @Test func lesEvenementsSimulesSontRepondables() throws {
    for name in ["permission", "desktop", "question", "question-multi", "plan", "elicit", "reply"] {
      let event = try #require(
        AgentEvent.fromLaunchArguments(["app", "--agent-event=\(name)"]), "\(name)")
      #expect(event.replyID != nil, "\(name)")
      #expect(event.prompt != nil, "\(name)")
    }
    let desktop = AgentEvent.fromLaunchArguments(["app", "--agent-event=desktop"])
    #expect(desktop?.source == .claudeDesktop)
  }

  // MARK: - Pastille repliée

  private func event(_ prompt: AgentEvent.Prompt, response: AgentEvent.Response = .permission, replyID: String? = "r")
    -> AgentEvent
  {
    AgentEvent(
      kind: .needsInput, project: "p", sessionID: "s", prompt: prompt, replyID: replyID,
      response: response)
  }

  @Test func laPastilleDitCeQuiEstDemande() {
    let tool = event(.tool(name: "Bash", detail: "ls"))
    #expect(AgentEventPillView.status(for: tool, queued: 0).text == "Allow?")
    let readOnly = event(.tool(name: "Bash", detail: "ls"), replyID: nil)
    #expect(AgentEventPillView.status(for: readOnly, queued: 0).text == "Permission")
    #expect(AgentEventPillView.status(for: event(.plan(title: "t", body: "b")), queued: 0).text == "Plan ready")

    let one = AgentEvent.Question(text: "?", options: [], multiSelect: false)
    #expect(AgentEventPillView.status(for: event(.questions([one]), response: .question), queued: 0).text == "Question")
    #expect(
      AgentEventPillView.status(for: event(.questions([one, one, one]), response: .question), queued: 0).text
        == "3 questions")
    #expect(
      AgentEventPillView.status(for: event(.questions([one]), response: .elicitation), queued: 0).text == "Form")
  }

  @Test func laPastilleCompteLesDemandesEnAttente() {
    let tool = event(.tool(name: "Bash", detail: "ls"))
    #expect(AgentEventPillView.status(for: tool, queued: 2).text == "Allow? +2")
  }

  @Test func unStoreCompteSesDemandesEtDonneLEcheanceDUneQuestion() throws {
    var store = AgentPromptStore()
    let now = Date(timeIntervalSince1970: 1_000)
    let question = AgentEvent(
      kind: .needsInput, project: "p", sessionID: "a",
      prompt: .questions([.init(text: "?", options: [], multiSelect: false)]), replyID: "q",
      response: .question)
    let permission = AgentEvent(
      kind: .needsInput, project: "p", sessionID: "b", prompt: .tool(name: "Bash", detail: "ls"),
      replyID: "t")
    store.apply(question, now: now)
    store.apply(permission, now: now.addingTimeInterval(5))
    #expect(store.count == 2)
    #expect(
      store.handBackDeadline(of: question)
        == now.addingTimeInterval(AgentHookServer.defaultQuestionWait))
    // Une permission attend sans limite : pas de compte à rebours.
    #expect(store.handBackDeadline(of: permission) == nil)
  }
}
