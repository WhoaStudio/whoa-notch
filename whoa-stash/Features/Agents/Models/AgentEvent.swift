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
            case .finished, .desktopReply, .clear, .toolStart, .turnStart, .sessionEnd: "checkmark.circle.fill"
            case .needsInput: "questionmark.bubble.fill"
            }
        }
    }

    /// Ce que Claude demande : une permission pour un outil, une ou plusieurs questions à choix,
    /// ou le simple texte d'une notification.
    nonisolated enum Prompt: Equatable, Sendable {
        case tool(name: String, detail: String)
        case questions([Question])
        case message(String)
    }

    nonisolated struct Question: Equatable, Sendable {
        var text: String
        var options: [Option]
        var multiSelect: Bool
    }

    nonisolated struct Option: Equatable, Sendable {
        var label: String
        var detail: String
    }

    /// Ce que l'utilisateur répond depuis l'encoche.
    nonisolated enum Decision: Equatable, Sendable {
        case allow
        case deny
        /// Réponses à `AskUserQuestion`, par texte de question.
        case answer([String: String])
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
    /// `tool_input` tel que reçu : une réponse à `AskUserQuestion` le renvoie avec les `answers`.
    var toolInput: Data?
    /// L'appel d'outil d'un événement `toolStart`.
    var tool: ToolCall?

    init(
        kind: Kind, project: String, sessionID: String? = nil, prompt: Prompt? = nil,
        replyID: String? = nil, toolInput: Data? = nil, tool: ToolCall? = nil
    ) {
        self.kind = kind
        self.project = project
        self.sessionID = sessionID
        self.prompt = prompt
        self.replyID = replyID
        self.toolInput = toolInput
        self.tool = tool
    }

    /// La ligne que le script de hook rend à Claude Code pour appliquer la décision, ou `nil` si elle
    /// n'a pas de sens pour cette demande.
    func replyJSON(for decision: Decision) -> String? {
        var body: [String: Any]
        switch decision {
        case .allow:
            body = ["behavior": "allow"]
        case .deny:
            body = ["behavior": "deny", "message": "Denied from the Whoa Stash notch."]
        case .answer(let answers):
            guard
                let toolInput,
                var input = (try? JSONSerialization.jsonObject(with: toolInput)) as? [String: Any]
            else { return nil }
            input["answers"] = answers
            body = ["behavior": "allow", "updatedInput": input]
        }
        let root: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Décode une ligne du script de hook : `{"kind":"stop"|"notify"|"permission"|"question"|"clear","payload":{…entrée du hook…}}`.
    /// Renvoie `nil` pour tout ce qui n'est pas reconnu — un message étranger sur le socket est ignoré.
    static func decode(_ data: Data) -> AgentEvent? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawKind = root["kind"] as? String
        else { return nil }

        let payload = root["payload"] as? [String: Any]
        let cwd = (payload?["cwd"] as? String) ?? ""
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        let project = name.isEmpty || name == "/" ? "Claude Code" : name
        let session = (payload?["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        switch rawKind {
        case "stop":
            return AgentEvent(kind: .finished, project: project, sessionID: session)
        case "clear":
            return AgentEvent(kind: .clear, project: project, sessionID: session)
        case "turn":
            return AgentEvent(kind: .turnStart, project: project, sessionID: session)
        case "end":
            return AgentEvent(kind: .sessionEnd, project: project, sessionID: session)
        case "tool":
            guard let name = payload?["tool_name"] as? String, name != "AskUserQuestion" else { return nil }
            let call = ToolCall(name: name, input: payload?["tool_input"] as? [String: Any] ?? [:], cwd: cwd)
            return AgentEvent(kind: .toolStart, project: project, sessionID: session, tool: call)
        case "permission":
            guard let tool = payload?["tool_name"] as? String else { return nil }
            let input = payload?["tool_input"] as? [String: Any] ?? [:]
            let rawInput = try? JSONSerialization.data(withJSONObject: input)
            let reply = UUID().uuidString
            // `PermissionRequest` couvre aussi `AskUserQuestion` : on montre alors ses questions.
            if tool == "AskUserQuestion" {
                let questions = (input["questions"] as? [[String: Any]] ?? []).compactMap(question)
                if !questions.isEmpty {
                    return AgentEvent(
                        kind: .needsInput, project: project, sessionID: session, prompt: .questions(questions),
                        replyID: reply, toolInput: rawInput)
                }
            }
            return AgentEvent(
                kind: .needsInput, project: project, sessionID: session,
                prompt: .tool(name: tool, detail: toolDetail(tool, input: input)), replyID: reply, toolInput: rawInput)
        case "question":
            let input = payload?["tool_input"] as? [String: Any]
            let questions = (input?["questions"] as? [[String: Any]] ?? []).compactMap(question)
            guard !questions.isEmpty else { return nil }
            return AgentEvent(kind: .needsInput, project: project, sessionID: session, prompt: .questions(questions))
        case "notify":
            // Une inactivité (`idle_prompt`) est une fin de tour : pastille brève, sans carte.
            let type = payload?["notification_type"] as? String
            let message = (payload?["message"] as? String).map { clip($0) }
            let prompt = type == "idle_prompt" ? nil : message.map(Prompt.message)
            return AgentEvent(kind: .needsInput, project: project, sessionID: session, prompt: prompt)
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
        return Question(text: clip(text), options: options, multiSelect: raw["multiSelect"] as? Bool ?? false)
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

    /// `--agent-event=stop|notify|permission|permission-long|question|clear|work[,projet]` substitue un événement fixe aux
    /// hooks, pour vérifier la notification sans lancer Claude Code.
    static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> AgentEvent? {
        guard let argument = arguments.first(where: { $0.hasPrefix("--agent-event=") }) else { return nil }
        let parts = argument.dropFirst("--agent-event=".count).split(separator: ",", maxSplits: 1)
        guard let kind = parts.first else { return nil }
        let project = parts.dropFirst().first.map(String.init) ?? "whoa-stash"
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
                name: "Edit", step: .edit, filePath: "src/invoice.ts", snippet: ToolCall.lines(of: code), startLine: 10)
            return AgentEvent(kind: .toolStart, project: project, tool: call)
        case "permission", "permission-long":
            let detail = kind == "permission"
                ? "git push origin main"
                : "rm -rf node_modules .next dist && npm install --legacy-peer-deps && npm run build -- --profile --verbose"
            return AgentEvent(
                kind: .needsInput, project: project, prompt: .tool(name: "Bash", detail: detail),
                replyID: "simulated")
        case "question":
            let options = [
                Option(label: "React", detail: "Component library"),
                Option(label: "Vue", detail: "Progressive framework"),
            ]
            return AgentEvent(
                kind: .needsInput, project: project,
                prompt: .questions([Question(text: "Which framework should I use?", options: options, multiSelect: false)]))
        default: return nil
        }
    }
}
