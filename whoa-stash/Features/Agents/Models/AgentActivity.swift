import Foundation

/// Les quatre étapes que l'onglet AI montre pendant qu'un agent travaille.
nonisolated enum AgentStep: Int, CaseIterable, Sendable {
    case read, edit, bash, done

    var title: String {
        switch self {
        case .read: "Read"
        case .edit: "Edit"
        case .bash: "Bash"
        case .done: "Done"
        }
    }

    var symbolName: String {
        switch self {
        case .read: "doc.text"
        case .edit: "pencil"
        case .bash: "terminal"
        case .done: "checkmark.circle.fill"
        }
    }
}

/// Un appel d'outil vu par le hook `PreToolUse`, réduit à ce que la carte d'activité affiche.
nonisolated struct ToolCall: Equatable, Sendable {
    /// Lignes montrées au plus.
    static let previewLines = 8

    var name: String
    /// `nil` : l'outil n'avance pas la liste (sous-agent, outil MCP…).
    var step: AgentStep?
    var filePath: String?
    /// Texte écrit (édition) ou commande ; vide pour une lecture, dont l'aperçu vient du disque.
    var snippet: [String] = []
    var startLine: Int = 1
    var cwd: String?

    init(
        name: String, step: AgentStep?, filePath: String? = nil, snippet: [String] = [], startLine: Int = 1,
        cwd: String? = nil
    ) {
        self.name = name
        self.step = step
        self.filePath = filePath
        self.snippet = snippet
        self.startLine = startLine
        self.cwd = cwd
    }

    init(name: String, input: [String: Any], cwd: String?) {
        self.name = name
        self.cwd = cwd
        switch name {
        case "Read", "NotebookRead":
            step = .read
            filePath = (input["file_path"] as? String) ?? (input["notebook_path"] as? String)
            startLine = max(1, (input["offset"] as? Int) ?? 1)
        case "Grep", "Glob", "LS", "WebFetch", "WebSearch":
            step = .read
            filePath = ["path", "url", "pattern", "query"].lazy.compactMap { input[$0] as? String }.first
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            step = .edit
            filePath = (input["file_path"] as? String) ?? (input["notebook_path"] as? String)
            let firstEdit = (input["edits"] as? [[String: Any]])?.first
            let text =
                (input["new_string"] as? String) ?? (input["content"] as? String)
                ?? (input["new_source"] as? String) ?? (firstEdit?["new_string"] as? String)
            snippet = Self.lines(of: text ?? "")
        case "Bash":
            step = .bash
            snippet = Self.lines(of: (input["command"] as? String) ?? "")
        default:
            step = nil
        }
    }

    static func lines(of text: String, limit: Int = previewLines) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).prefix(limit).map {
            let line = String($0)
            return line.count > 120 ? String(line.prefix(120)) : line
        }
    }

    /// Quelques lignes du fichier lu, tirées du disque — seulement un fichier du dossier de la
    /// session, de taille raisonnable : ce que l'agent lit ailleurs ne s'affiche pas sur l'écran.
    static func filePreview(_ call: ToolCall) -> [String]? {
        guard
            call.step == .read, let path = call.filePath, let cwd = call.cwd, !cwd.isEmpty,
            path.hasPrefix("/")
        else { return nil }
        let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let root = URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath()
        guard
            file.path.hasPrefix(root.path + "/"),
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
            size < 512_000,
            let data = try? Data(contentsOf: file),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        let start = min(max(call.startLine - 1, 0), max(all.count - 1, 0))
        return all[start...].prefix(previewLines).map {
            let line = String($0)
            return line.count > 120 ? String(line.prefix(120)) : line
        }
    }
}

/// Ce qu'une session fait en ce moment : l'étape courante, celles déjà passées et le fichier travaillé.
nonisolated struct AgentActivity: Equatable, Sendable {
    var project: String
    var step: AgentStep?
    var visited: Set<AgentStep> = []
    var toolName: String?
    var filePath: String?
    var snippet: [String] = []
    var startLine: Int = 1
    var updatedAt: Date
}

/// L'activité des sessions Claude Code, une par session ; la plus récente est montrée.
nonisolated struct AgentActivityStore {

    /// Un tour en cours sans nouvelle depuis ce délai est oublié (session plantée).
    static let workingLifetime: TimeInterval = 900
    /// Un tour terminé reste lisible ce temps.
    static let finishedLifetime: TimeInterval = 120

    private var sessions: [(key: String, activity: AgentActivity)] = []

    var current: AgentActivity? { sessions.last?.activity }

    /// Applique un événement. Renvoie `true` si ce que montre la carte a changé.
    @discardableResult
    mutating func apply(
        _ event: AgentEvent, now: Date = Date(), preview: (ToolCall) -> [String]? = ToolCall.filePreview
    ) -> Bool {
        let key = event.sessionID ?? ""
        let before = current
        let index = sessions.firstIndex { $0.key == key }
        var activity = index.map { sessions[$0].activity } ?? AgentActivity(project: event.project, updatedAt: now)

        switch event.kind {
        case .toolStart:
            guard let call = event.tool else { return false }
            if let step = call.step {
                activity.step = step
                activity.visited.insert(step)
                activity.filePath = call.filePath
                activity.snippet = call.snippet.isEmpty ? (preview(call) ?? []) : call.snippet
                activity.startLine = call.startLine
            }
            activity.toolName = call.name
        case .turnStart:
            activity = AgentActivity(project: event.project, updatedAt: now)
        case .finished:
            guard index != nil else { return false }
            activity.step = .done
            activity.visited = Set(AgentStep.allCases)
            activity.toolName = nil
        case .sessionEnd:
            if let index { sessions.remove(at: index) }
            return before != current
        default:
            return false
        }

        activity.project = event.project
        activity.updatedAt = now
        if let index { sessions.remove(at: index) }
        sessions.append((key, activity))
        return before != current
    }

    /// Retire les sessions sans nouvelle depuis trop longtemps.
    @discardableResult
    mutating func expire(now: Date = Date()) -> Bool {
        let count = sessions.count
        sessions.removeAll {
            let lifetime = $0.activity.step == .done ? Self.finishedLifetime : Self.workingLifetime
            return now.timeIntervalSince($0.activity.updatedAt) > lifetime
        }
        return sessions.count != count
    }
}
