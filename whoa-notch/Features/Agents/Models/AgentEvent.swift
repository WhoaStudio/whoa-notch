import Foundation

/// Ce qu'un agent IA signale à l'encoche : une session terminée, une question ou une permission
/// en attente, ou une réponse de Claude Desktop prête.
nonisolated struct AgentEvent: Equatable, Sendable {

  nonisolated enum Kind: String, Sendable {
    case finished
    case needsInput
    case desktopReply
    /// La session n'attend plus rien (outil exécuté, prompt envoyé, session close) : ne s'affiche pas.
    case clear
    /// Un outil démarre : fait avancer la carte d'activité, sans pastille.
    case toolStart
    /// Un nouveau prompt part : la carte d'activité repart de zéro.
    case turnStart
    case sessionEnd

    var statusText: String {
      switch self {
      case .finished: "Finished"
      case .needsInput: "Needs input"
      case .desktopReply: "Reply ready"
      case .clear, .toolStart, .turnStart, .sessionEnd: ""
      }
    }

    /// Les événements qui lèvent la demande en attente de leur session.
    var resolvesPrompt: Bool {
      self == .clear || self == .turnStart || self == .sessionEnd
    }

    var symbolName: String {
      switch self {
      case .finished, .desktopReply, .clear, .toolStart, .turnStart, .sessionEnd:
        "checkmark.circle.fill"
      case .needsInput: "questionmark.bubble.fill"
      }
    }
  }

  /// D'où vient la session : Claude Code dans un terminal ou un éditeur, ou l'onglet Code de Claude Desktop.
  nonisolated enum Source: Equatable, Sendable {
    case claudeCode
    case claudeDesktop

    var label: String {
      switch self {
      case .claudeCode: "Claude Code"
      case .claudeDesktop: "Claude Desktop"
      }
    }
  }

  /// Le hook auquel la réponse est rendue ; elle n'a pas la même forme pour chacun.
  nonisolated enum Response: Equatable, Sendable {
    /// `PermissionRequest` : un outil, un plan, ou une question.
    case permission
    /// `PreToolUse` sur `AskUserQuestion`.
    case question
    /// `Elicitation` : un formulaire demandé par un serveur MCP.
    case elicitation
    /// `Stop` : la réponse libre qui fait repartir Claude.
    case stopReply
  }

  /// Ce que Claude demande : une permission pour un outil, un plan à approuver, une ou plusieurs
  /// questions (ou les champs d'un formulaire MCP), une réponse libre, ou le simple texte d'une notification.
  nonisolated enum Prompt: Equatable, Sendable {
    case tool(name: String, detail: String)
    case plan(title: String, body: String)
    case questions([Question])
    case reply(String)
    case message(String)
  }

  nonisolated enum FieldType: String, Sendable {
    case string
    case number
    case integer
    case boolean
  }

  nonisolated struct Question: Equatable, Sendable {
    var text: String
    var options: [Option]
    var multiSelect: Bool
    /// Pas de choix à cocher : la réponse se tape (champ de formulaire MCP).
    var freeText: Bool = false
    /// Nom du champ d'un formulaire MCP ; `nil` pour une question d'`AskUserQuestion`.
    var field: String?
    var fieldType: FieldType = .string
  }

  nonisolated struct Option: Equatable, Sendable {
    var label: String
    var detail: String
  }

  /// Le choix d'un plan (`ExitPlanMode`), les mêmes que la boîte de dialogue du terminal.
  nonisolated enum PlanChoice: Equatable, Sendable {
    case auto
    case manual
    /// Rejette le plan et arrête Claude : le changement se tape dans Claude Code.
    case change
  }

  /// Ce que l'utilisateur répond depuis l'encoche.
  nonisolated enum Decision: Equatable, Sendable {
    case allow
    /// Autoriser et retenir : reprend la règle que Claude Code propose (`permission_suggestions`).
    case allowAlways
    case deny
    /// Réponses aux questions (ou champs d'un formulaire), par texte de question ; plusieurs
    /// libellés pour un choix multiple.
    case answer([String: [String]])
    case plan(PlanChoice)
    /// Texte tapé après la fin d'un tour : Claude repart avec.
    case reply(String)
    /// Rend la main à l'agent : il redemande dans son terminal, ou s'arrête.
    case handBack
  }

  var kind: Kind
  /// Nom du dossier du projet, ou « Claude » pour Claude Desktop.
  var project: String
  /// Identifiant de session Claude Code ; `nil` pour Claude Desktop et les événements simulés.
  var sessionID: String?
  /// Présent seulement pour une demande qui reste affichée jusqu'à sa résolution.
  var prompt: Prompt?
  /// Présent quand le script de hook attend une réponse sur sa connexion : on peut alors répondre
  /// depuis l'encoche (`AgentHookServer.reply`). Absent des événements qui n'attendent rien.
  var replyID: String?
  /// `tool_input` tel que reçu : une réponse à `AskUserQuestion` ou un plan le renvoie.
  var toolInput: Data?
  /// L'appel d'outil d'un événement `toolStart`.
  var tool: ToolCall?
  var response: Response = .permission
  var source: Source = .claudeCode
  /// `permission_suggestions` tel que reçu : « Always » en reprend les règles.
  var permissionSuggestions: Data?
  /// Le texte du prompt de l'utilisateur (`turnStart`) ou le dernier message de l'agent (`finished`).
  var text: String?
  /// Le hook peut recevoir une consigne en attente pour la session (`PostToolUse`).
  var acceptsSteer = false

  init(
    kind: Kind, project: String, sessionID: String? = nil, prompt: Prompt? = nil,
    replyID: String? = nil, toolInput: Data? = nil, tool: ToolCall? = nil,
    response: Response = .permission, source: Source = .claudeCode,
    permissionSuggestions: Data? = nil, text: String? = nil, acceptsSteer: Bool = false
  ) {
    self.kind = kind
    self.project = project
    self.sessionID = sessionID
    self.prompt = prompt
    self.replyID = replyID
    self.toolInput = toolInput
    self.tool = tool
    self.response = response
    self.source = source
    self.permissionSuggestions = permissionSuggestions
    self.text = text
    self.acceptsSteer = acceptsSteer
  }

  /// Une règle à retenir est proposée : le bouton « Always » a un sens.
  var offersAlways: Bool {
    guard let permissionSuggestions,
      let list = (try? JSONSerialization.jsonObject(with: permissionSuggestions)) as? [Any]
    else { return false }
    return !list.isEmpty
  }

  // MARK: - Réponse au hook

  /// La ligne que le script de hook rend à Claude Code pour appliquer la décision, ou `nil` si elle
  /// n'a pas de sens pour cette demande. `{}` rend la main : aucun hook ne tranche, Claude Code
  /// montre sa propre boîte de dialogue (ou s'arrête, pour un `Stop`).
  func replyJSON(for decision: Decision) -> String? {
    if decision == .handBack { return "{}" }
    let root: [String: Any]?
    switch response {
    case .permission: root = permissionReply(decision)
    case .question: root = questionReply(decision)
    case .elicitation: root = elicitationReply(decision)
    case .stopReply: root = stopReply(decision)
    }
    guard let root,
      let data = try? JSONSerialization.data(
        withJSONObject: root, options: [.withoutEscapingSlashes, .sortedKeys])
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private var toolInputObject: [String: Any]? {
    guard let toolInput else { return nil }
    return (try? JSONSerialization.jsonObject(with: toolInput)) as? [String: Any]
  }

  private var isPlan: Bool {
    if case .plan = prompt { return true }
    return false
  }

  private func permissionReply(_ decision: Decision) -> [String: Any]? {
    var body: [String: Any]
    switch decision {
    case .allow, .allowAlways:
      body = ["behavior": "allow"]
      // Claude Code ignore un « allow » d'`ExitPlanMode` sans l'entrée renvoyée.
      if isPlan {
        guard let input = toolInputObject else { return nil }
        body["updatedInput"] = input
      }
      if decision == .allowAlways, let permissionSuggestions,
        let rules = (try? JSONSerialization.jsonObject(with: permissionSuggestions)) as? [Any],
        !rules.isEmpty
      {
        body["updatedPermissions"] = rules
      }
    case .deny:
      body = ["behavior": "deny", "message": "Denied from the Whoa Notch notch."]
    case .plan(let choice):
      guard isPlan, let input = toolInputObject else { return nil }
      switch choice {
      case .auto, .manual:
        body = [
          "behavior": "allow", "updatedInput": input,
          "updatedPermissions": [
            [
              "type": "setMode", "mode": choice == .auto ? "auto" : "default",
              "destination": "session",
            ]
          ],
        ]
      case .change:
        body = [
          "behavior": "deny", "interrupt": true,
          "message": "The user wants to change the plan and will type the changes in Claude Code.",
        ]
      }
    case .answer(let answers):
      // Une question d'`AskUserQuestion` reçue par `PermissionRequest`.
      guard var input = toolInputObject else { return nil }
      input["answers"] = Self.joined(answers)
      body = ["behavior": "allow", "updatedInput": input]
    case .reply, .handBack:
      return nil
    }
    return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
  }

  private func questionReply(_ decision: Decision) -> [String: Any]? {
    guard case .answer(let answers) = decision, var input = toolInputObject else { return nil }
    input["answers"] = Self.joined(answers)
    return [
      "hookSpecificOutput": [
        "hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input,
      ]
    ]
  }

  private func elicitationReply(_ decision: Decision) -> [String: Any]? {
    let output: [String: Any]
    switch decision {
    case .deny:
      output = ["hookEventName": "Elicitation", "action": "decline"]
    case .answer(let answers):
      guard case .questions(let questions) = prompt else { return nil }
      var content: [String: Any] = [:]
      for question in questions {
        guard let field = question.field, let text = answers[question.text]?.first else {
          continue
        }
        guard let value = Self.fieldValue(text, type: question.fieldType) else { return nil }
        content[field] = value
      }
      output = ["hookEventName": "Elicitation", "action": "accept", "content": content]
    default:
      return nil
    }
    return ["hookSpecificOutput": output]
  }

  private func stopReply(_ decision: Decision) -> [String: Any]? {
    guard case .reply(let text) = decision else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return [
      "decision": "block",
      "reason": "The user replied from the Whoa Notch notch: \(String(trimmed.prefix(2000)))",
    ]
  }

  /// `AskUserQuestion` attend une chaîne par question ; un choix multiple joint ses libellés.
  private static func joined(_ answers: [String: [String]]) -> [String: String] {
    answers.mapValues { $0.joined(separator: ", ") }
  }

  /// La valeur JSON d'un champ de formulaire tapé ou choisi ; `nil` si elle n'a pas le bon type.
  static func fieldValue(_ text: String, type: FieldType) -> Any? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch type {
    case .string: return text
    case .boolean: return ["yes", "true", "1"].contains(text.lowercased())
    case .integer: return Int(text)
    case .number:
      if let whole = Int(text) { return whole }
      return Double(text)
    }
  }

  // MARK: - Décodage

  /// Décode une ligne du script de hook :
  /// `{"kind":"stop"|"notify"|"permission"|"question"|"elicit"|"clear"…,"entrypoint":"…","payload":{…entrée du hook…}}`.
  /// Renvoie `nil` pour tout ce qui n'est pas reconnu — un message étranger sur le socket est ignoré.
  ///
  /// `holdStopReply` : la réponse libre après un tour est activée ; une fin de tour reste alors
  /// ouverte, avec son identifiant de réponse.
  static func decode(_ data: Data, holdStopReply: Bool = false) -> AgentEvent? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawKind = root["kind"] as? String
    else { return nil }

    let payload = root["payload"] as? [String: Any]
    let cwd = (payload?["cwd"] as? String) ?? ""
    let name = URL(fileURLWithPath: cwd).lastPathComponent
    let source: Source = root["entrypoint"] as? String == "claude-desktop" ? .claudeDesktop : .claudeCode
    let project = name.isEmpty || name == "/" ? source.label : name
    let session = (payload?["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }

    switch rawKind {
    case "stop":
      if holdStopReply, (payload?["stop_hook_active"] as? Bool) != true {
        let last = clip(oneLine(payload?["last_assistant_message"] as? String ?? ""), limit: 300)
        return AgentEvent(
          kind: .finished, project: project, sessionID: session, prompt: .reply(last),
          replyID: UUID().uuidString, response: .stopReply, source: source, text: last)
      }
      let message = (payload?["last_assistant_message"] as? String).map { clip(oneLine($0), limit: 300) }
      return AgentEvent(
        kind: .finished, project: project, sessionID: session, source: source, text: message)
    case "clear":
      return AgentEvent(kind: .clear, project: project, sessionID: session, source: source)
    case "post":
      return AgentEvent(
        kind: .clear, project: project, sessionID: session, source: source, acceptsSteer: true)
    case "turn":
      let task = (payload?["prompt"] as? String).map { clip(oneLine($0), limit: 300) }
      return AgentEvent(
        kind: .turnStart, project: project, sessionID: session, source: source, text: task)
    case "end":
      return AgentEvent(kind: .sessionEnd, project: project, sessionID: session, source: source)
    case "tool":
      guard let name = payload?["tool_name"] as? String, name != "AskUserQuestion" else {
        return nil
      }
      let call = ToolCall(
        name: name, input: payload?["tool_input"] as? [String: Any] ?? [:], cwd: cwd)
      return AgentEvent(
        kind: .toolStart, project: project, sessionID: session, tool: call, source: source)
    case "permission":
      guard let tool = payload?["tool_name"] as? String else { return nil }
      let input = payload?["tool_input"] as? [String: Any] ?? [:]
      let rawInput = try? JSONSerialization.data(withJSONObject: input)
      let suggestions = (payload?["permission_suggestions"] as? [Any]).flatMap {
        try? JSONSerialization.data(withJSONObject: $0)
      }
      let reply = UUID().uuidString
      // `PermissionRequest` couvre aussi `AskUserQuestion` : on montre alors ses questions.
      if tool == "AskUserQuestion" {
        let questions = (input["questions"] as? [[String: Any]] ?? []).compactMap(question)
        if !questions.isEmpty {
          return AgentEvent(
            kind: .needsInput, project: project, sessionID: session, prompt: .questions(questions),
            replyID: reply, toolInput: rawInput, source: source)
        }
      }
      if tool == "ExitPlanMode", let plan = input["plan"] as? String {
        return AgentEvent(
          kind: .needsInput, project: project, sessionID: session,
          prompt: .plan(title: planTitle(plan), body: clip(plan, limit: 900)), replyID: reply,
          toolInput: rawInput, source: source)
      }
      return AgentEvent(
        kind: .needsInput, project: project, sessionID: session,
        prompt: .tool(name: tool, detail: toolDetail(tool, input: input)), replyID: reply,
        toolInput: rawInput, source: source, permissionSuggestions: suggestions)
    case "question":
      let input = payload?["tool_input"] as? [String: Any]
      let questions = (input?["questions"] as? [[String: Any]] ?? []).compactMap(question)
      guard !questions.isEmpty else { return nil }
      // Le hook `PreToolUse` attend la réponse : sans elle, Claude Code n'ouvre pas sa question.
      let rawInput = input.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
      return AgentEvent(
        kind: .needsInput, project: project, sessionID: session, prompt: .questions(questions),
        replyID: UUID().uuidString, toolInput: rawInput, response: .question, source: source)
    case "elicit":
      guard let payload, let questions = elicitationQuestions(payload) else { return nil }
      return AgentEvent(
        kind: .needsInput, project: project, sessionID: session, prompt: .questions(questions),
        replyID: UUID().uuidString, response: .elicitation, source: source)
    case "notify":
      // Une inactivité (`idle_prompt`) est une fin de tour : pastille brève, sans carte.
      let type = payload?["notification_type"] as? String
      let message = (payload?["message"] as? String).map { clip($0) }
      let prompt = type == "idle_prompt" ? nil : message.map(Prompt.message)
      return AgentEvent(
        kind: .needsInput, project: project, sessionID: session, prompt: prompt, source: source)
    default:
      return nil
    }
  }

  private static func question(_ raw: [String: Any]) -> Question? {
    guard let text = raw["question"] as? String else { return nil }
    let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { option -> Option? in
      guard let label = option["label"] as? String else { return nil }
      return Option(label: label, detail: option["description"] as? String ?? "")
    }
    return Question(
      text: clip(text), options: options, multiSelect: raw["multiSelect"] as? Bool ?? false)
  }

  /// Les champs d'un formulaire MCP (`Elicitation`, mode `form`) : un par propriété, dans l'ordre
  /// des clés. `nil` si le formulaire sort de ce que la carte sait montrer (mode URL, plus de
  /// quatre champs, un type inconnu) : Claude Code montre alors sa propre boîte de dialogue.
  static func elicitationQuestions(_ payload: [String: Any]) -> [Question]? {
    guard (payload["mode"] as? String ?? "form") == "form",
      let schema = payload["requested_schema"] as? [String: Any],
      let properties = schema["properties"] as? [String: [String: Any]],
      !properties.isEmpty, properties.count <= 4
    else { return nil }
    let message = clip(payload["message"] as? String ?? "")
    var questions: [Question] = []
    for (index, key) in properties.keys.sorted().enumerated() {
      guard let property = properties[key],
        let type = FieldType(rawValue: property["type"] as? String ?? "")
      else { return nil }
      let title = (property["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
      let text: String
      if properties.count == 1 {
        text = message.isEmpty ? title : message
      } else {
        text = index == 0 && !message.isEmpty ? "\(title) — \(message)" : title
      }
      var options: [Option] = []
      if type == .boolean {
        options = [Option(label: "Yes", detail: ""), Option(label: "No", detail: "")]
      } else if let values = property["enum"] as? [String], (2...4).contains(values.count) {
        options = values.map { Option(label: $0, detail: "") }
      }
      questions.append(
        Question(
          text: clip(text), options: options, multiSelect: false, freeText: options.isEmpty,
          field: key, fieldType: type))
    }
    // Deux champs au même libellé se confondraient dans les réponses.
    guard Set(questions.map(\.text)).count == questions.count else { return nil }
    return questions
  }

  /// La première ligne non vide du plan, sans ses marques de titre Markdown.
  static func planTitle(_ plan: String) -> String {
    let first = plan.split(separator: "\n")
      .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let title = first.map { String($0.drop { $0 == "#" || $0 == " " }) } ?? ""
    return title.isEmpty ? "Plan" : clip(title, limit: 120)
  }

  /// Ce qui identifie l'appel : la commande, le fichier, l'adresse — à défaut, la première valeur texte.
  private static func toolDetail(_ tool: String, input: [String: Any]) -> String {
    for key in ["command", "file_path", "notebook_path", "url", "pattern", "path", "query"] {
      if let value = input[key] as? String, !value.isEmpty { return clip(value) }
    }
    return clip(input.values.compactMap { $0 as? String }.first ?? "")
  }

  private static func clip(_ text: String, limit: Int = 600) -> String {
    text.count > limit ? String(text.prefix(limit)) + "…" : text
  }

  private static func oneLine(_ text: String) -> String {
    text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// `--agent-event=stop|notify|permission|permission-long|question|question-multi|plan|elicit|reply|desktop|clear|work[,projet]`
  /// substitue un événement fixe aux hooks, pour vérifier la notification sans lancer Claude Code.
  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> AgentEvent? {
    guard let argument = arguments.first(where: { $0.hasPrefix("--agent-event=") }) else {
      return nil
    }
    let parts = argument.dropFirst("--agent-event=".count).split(separator: ",", maxSplits: 1)
    guard let kind = parts.first else { return nil }
    let project = parts.dropFirst().first.map(String.init) ?? "whoa-notch"
    switch kind {
    case "stop": return AgentEvent(kind: .finished, project: project)
    case "notify": return AgentEvent(kind: .needsInput, project: project)
    case "clear": return AgentEvent(kind: .clear, project: project)
    case "work":
      let code = """
        import { Item } from './types'

        const TVA = 0.196

        export function total(items: Item[]) {
          const sum = items.reduce((s, i) => s + i.price, 0)
          return sum * (1 + TVA)
        }
        """
      let call = ToolCall(
        name: "Edit", step: .edit, filePath: "src/invoice.ts", snippet: ToolCall.lines(of: code),
        startLine: 10)
      return AgentEvent(kind: .toolStart, project: project, tool: call)
    case "permission", "permission-long", "desktop":
      let detail =
        kind == "permission-long"
        ? "rm -rf node_modules .next dist && npm install --legacy-peer-deps && npm run build -- --profile --verbose"
        : "git push origin main"
      let rule: [[String: Any]] = [
        [
          "type": "addRules", "behavior": "allow", "destination": "localSettings",
          "rules": [["toolName": "Bash", "ruleContent": detail]],
        ]
      ]
      return AgentEvent(
        kind: .needsInput, project: project, prompt: .tool(name: "Bash", detail: detail),
        replyID: "simulated", source: kind == "desktop" ? .claudeDesktop : .claudeCode,
        permissionSuggestions: try? JSONSerialization.data(withJSONObject: rule))
    case "question":
      let options = [
        Option(label: "React", detail: "Component library"),
        Option(label: "Vue", detail: "Progressive framework"),
      ]
      return simulatedQuestions(
        [Question(text: "Which framework should I use?", options: options, multiSelect: false)],
        project: project)
    case "question-multi":
      return simulatedQuestions(
        [
          Question(
            text: "Which checks should run before merge?",
            options: [
              Option(label: "Lint", detail: "ESLint on the changed files"),
              Option(label: "Types", detail: "tsc --noEmit"),
              Option(label: "E2E", detail: "Playwright, about 4 min"),
            ], multiSelect: true),
          Question(
            text: "Where should the report go?",
            options: [Option(label: "Terminal", detail: ""), Option(label: "File", detail: "")],
            multiSelect: false),
        ], project: project)
    case "plan":
      let plan = "## Move login state into a store\n1. Extract the state from LoginForm\n2. Add a store"
      let input = try? JSONSerialization.data(withJSONObject: ["plan": plan])
      return AgentEvent(
        kind: .needsInput, project: project,
        prompt: .plan(title: planTitle(plan), body: plan), replyID: "simulated", toolInput: input)
    case "elicit":
      let payload: [String: Any] = [
        "message": "Create a Jira issue",
        "requested_schema": [
          "type": "object",
          "properties": [
            "project": ["type": "string", "title": "Project key"],
            "priority": ["type": "string", "enum": ["Low", "Medium", "High"]],
            "notify": ["type": "boolean", "title": "Notify the team"],
          ],
        ],
      ]
      guard let questions = elicitationQuestions(payload) else { return nil }
      return AgentEvent(
        kind: .needsInput, project: project, prompt: .questions(questions), replyID: "simulated",
        response: .elicitation)
    case "reply":
      return AgentEvent(
        kind: .finished, project: project, prompt: .reply("I refactored LoginForm and added tests."),
        replyID: "simulated", response: .stopReply)
    default: return nil
    }
  }

  private static func simulatedQuestions(_ questions: [Question], project: String) -> AgentEvent {
    AgentEvent(
      kind: .needsInput, project: project, prompt: .questions(questions), replyID: "simulated",
      toolInput: try? JSONSerialization.data(withJSONObject: ["questions": []]), response: .question)
  }
}
