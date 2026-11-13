import Foundation

/// Où en est une session d'agent.
nonisolated enum AgentSessionStatus: Equatable, Sendable {
  /// Un outil tourne ou un tour est en cours.
  case working
  /// Une demande (permission, plan, question, formulaire) attend l'utilisateur.
  case blocked
  /// Le tour est fini : la session attend un nouveau prompt.
  case waiting
  /// La session est close.
  case done

  var title: String {
    switch self {
    case .working: "Working"
    case .blocked: "Blocked"
    case .waiting: "Waiting"
    case .done: "Done"
    }
  }
}

nonisolated enum AgentSender: Equatable, Sendable {
  case user
  case agent
}

/// Une ligne du journal d'une session. Le même journal sert de fil de discussion (prompts, consignes,
/// réponses) et de relecture (lectures, éditions, commandes, interventions).
nonisolated struct AgentSessionEntry: Equatable, Sendable, Identifiable {
  nonisolated enum Content: Equatable, Sendable {
    /// Le prompt qui a lancé le tour.
    case prompt(String)
    case tool(ToolCall)
    /// Une demande posée à l'utilisateur.
    case request(AgentEvent.Prompt)
    /// Ce que l'utilisateur a répondu à une demande.
    case decision(AgentEvent.Decision)
    /// Une consigne envoyée en cours de route ; `delivered` : l'agent l'a reçue.
    case steer(String, delivered: Bool)
    /// Le dernier message de l'agent à la fin d'un tour.
    case reply(String)
    case ended
  }

  var id: Int
  var date: Date
  var sender: AgentSender
  var content: Content

  /// Appartient au fil de discussion (le reste n'est que de la relecture).
  var isMessage: Bool {
    switch content {
    case .prompt, .steer, .reply: true
    case .tool, .request, .decision, .ended: false
    }
  }
}

nonisolated struct AgentSession: Equatable, Sendable, Identifiable {
  /// Entrées gardées au plus par session.
  static let logLimit = 200

  var id: String
  var project: String
  var source: AgentEvent.Source
  /// Le prompt du tour en cours ; le nom du projet tant qu'on ne le connaît pas.
  var task: String
  /// Début du tour en cours.
  var startedAt: Date
  /// Fin du tour (réponse rendue ou session close) ; `nil` tant qu'il tourne.
  var endedAt: Date?
  var updatedAt: Date
  var status: AgentSessionStatus = .working
  /// La demande à laquelle on peut répondre, si elle attend.
  var pending: AgentEvent?
  var lastTool: ToolCall?
  var log: [AgentSessionEntry] = []
  fileprivate var nextEntryID = 0

  /// Ce que fait la session, par exemple « Edit checkout.ts ».
  var action: String {
    switch status {
    case .blocked: return pendingSummary
    case .waiting: return "Waiting for you"
    case .done: return "Finished"
    case .working:
      guard let tool = lastTool else { return "Thinking" }
      let file = tool.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
      return [tool.name, file ?? tool.snippet.first].compactMap { $0 }.joined(separator: " ")
    }
  }

  private var pendingSummary: String {
    switch pending?.prompt {
    case .tool(let name, let detail): "Allow \(name)? \(detail)"
    case .plan(let title, _): "Plan: \(title)"
    case .questions(let questions): questions.first?.text ?? "Question"
    case .reply, .message, .none: "Needs input"
    }
  }

  /// Le fil de discussion : le journal sans les étapes d'outil.
  var thread: [AgentSessionEntry] { log.filter(\.isMessage) }

  func elapsed(now: Date) -> TimeInterval {
    max(0, (endedAt ?? now).timeIntervalSince(startedAt))
  }

  fileprivate mutating func append(
    _ content: AgentSessionEntry.Content, from sender: AgentSender, at date: Date
  ) {
    log.append(AgentSessionEntry(id: nextEntryID, date: date, sender: sender, content: content))
    nextEntryID += 1
    if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
  }
}

/// Où part une consigne.
nonisolated enum AgentSteerRoute: Equatable, Sendable {
  /// La session attend une réponse libre : elle part par cette demande.
  case reply(AgentEvent)
  /// Elle est gardée pour le prochain `PostToolUse` de cette session.
  case queue(sessionID: String)
  /// Session inconnue ou close.
  case rejected
}

/// Les sessions d'agent en cours, en parallèle, chacune avec son journal. L'ordre est celui de leur
/// première apparition, pour que la liste ne saute pas.
nonisolated struct AgentSessionStore {

  static let workingLifetime: TimeInterval = 900
  static let blockedLifetime: TimeInterval = 600
  static let waitingLifetime: TimeInterval = 1800
  static let doneLifetime: TimeInterval = 600

  private(set) var sessions: [AgentSession] = []
  /// La session ouverte dans la liste ; `nil` : la première qui attend, sinon la dernière active.
  var selectedID: String?

  var selected: AgentSession? {
    if let selectedID, let session = session(selectedID) { return session }
    return sessions.first { $0.status == .blocked }
      ?? sessions.max { $0.updatedAt < $1.updatedAt }
  }

  var blockedCount: Int { sessions.filter { $0.status == .blocked }.count }
  var workingCount: Int { sessions.filter { $0.status == .working }.count }

  func session(_ id: String) -> AgentSession? { sessions.first { $0.id == id } }

  private func index(of id: String) -> Int? { sessions.firstIndex { $0.id == id } }

  /// Applique un événement. Renvoie `true` si une session a changé.
  @discardableResult
  mutating func apply(_ event: AgentEvent, now: Date = Date()) -> Bool {
    let id = event.sessionID ?? ""
    let before = sessions
    var position = index(of: id)

    // Une fin de session ou un « clear » ne crée pas de session.
    if position == nil {
      guard event.kind != .clear, event.kind != .sessionEnd else { return false }
      sessions.append(
        AgentSession(
          id: id, project: event.project, source: event.source, task: event.project,
          startedAt: now, updatedAt: now))
      position = sessions.count - 1
    }
    guard let position else { return false }
    var session = sessions[position]
    session.updatedAt = now

    switch event.kind {
    case .turnStart:
      session.startedAt = now
      session.endedAt = nil
      session.status = .working
      session.pending = nil
      session.lastTool = nil
      if let text = event.text, !text.isEmpty {
        session.task = text
        session.append(.prompt(text), from: .user, at: now)
      }
    case .toolStart:
      guard let call = event.tool else { return false }
      session.endedAt = nil
      session.lastTool = call
      if session.status != .blocked { session.status = .working }
      session.append(.tool(call), from: .agent, at: now)
    case .clear:
      session.pending = nil
      session.endedAt = nil
      session.status = .working
    case .finished:
      session.endedAt = now
      session.status = .waiting
      session.lastTool = nil
      session.pending = event.replyID != nil ? event : nil
      if let text = event.text, !text.isEmpty { session.append(.reply(text), from: .agent, at: now) }
    case .sessionEnd:
      session.endedAt = now
      session.status = .done
      session.pending = nil
      session.append(.ended, from: .agent, at: now)
    case .needsInput, .desktopReply:
      guard let prompt = event.prompt else { break }
      // Une notification qui double la demande détaillée ne l'écrase pas.
      if event.replyID == nil, session.pending?.replyID != nil { return false }
      session.pending = event.replyID != nil ? event : nil
      session.status = .blocked
      session.endedAt = nil
      session.append(.request(prompt), from: .agent, at: now)
    }

    sessions[position] = session
    return sessions != before
  }

  /// La demande avec cet identifiant a trouvé sa réponse, ou son hook a été annulé.
  @discardableResult
  mutating func remove(replyID: String) -> Bool {
    guard let position = sessions.firstIndex(where: { $0.pending?.replyID == replyID }) else {
      return false
    }
    let wasReply = sessions[position].pending?.response == .stopReply
    sessions[position].pending = nil
    sessions[position].status = wasReply ? .waiting : .working
    return true
  }

  /// L'utilisateur a répondu à la demande de cette session.
  mutating func record(
    _ decision: AgentEvent.Decision, for event: AgentEvent, now: Date = Date()
  ) {
    guard let position = index(of: event.sessionID ?? "") else { return }
    sessions[position].append(.decision(decision), from: .user, at: now)
  }

  /// Envoie une consigne à une seule session : elle est notée dans son journal et rien d'autre ne
  /// la reçoit. Renvoie la voie à suivre pour la livrer.
  mutating func steer(_ text: String, to id: String, now: Date = Date()) -> AgentSteerRoute {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !id.isEmpty, let position = index(of: id), sessions[position].status != .done else {
      return .rejected
    }
    if let pending = sessions[position].pending, pending.response == .stopReply {
      sessions[position].append(.steer(text, delivered: true), from: .user, at: now)
      return .reply(pending)
    }
    sessions[position].append(.steer(text, delivered: false), from: .user, at: now)
    return .queue(sessionID: id)
  }

  /// Le hook de cette session a rendu la consigne à l'agent.
  mutating func markSteerDelivered(_ text: String, for id: String) {
    guard let position = index(of: id),
      let entry = sessions[position].log.lastIndex(where: {
        $0.content == .steer(text, delivered: false)
      })
    else { return }
    sessions[position].log[entry].content = .steer(text, delivered: true)
  }

  /// Retire les sessions sans nouvelle depuis trop longtemps (processus tué : aucun `SessionEnd`).
  @discardableResult
  mutating func expire(now: Date = Date()) -> Bool {
    let count = sessions.count
    sessions.removeAll {
      let lifetime: TimeInterval
      switch $0.status {
      case .working: lifetime = Self.workingLifetime
      case .blocked: lifetime = Self.blockedLifetime
      case .waiting: lifetime = Self.waitingLifetime
      case .done: lifetime = Self.doneLifetime
      }
      return now.timeIntervalSince($0.updatedAt) > lifetime
    }
    return sessions.count != count
  }
}
