import Foundation

/// Les demandes d'agent encore sans réponse, une par session. L'encoche montre la plus récente ;
/// elle disparaît dès que la même session signale autre chose (outil exécuté, nouveau prompt, fin).
///
/// Aucun hook ne signale la réponse de l'utilisateur à une demande : c'est le premier événement
/// suivant de la session qui fait foi.
nonisolated struct AgentPromptStore {

  private var pending: [(key: String, event: AgentEvent, date: Date)] = []
  /// Sessions dont une question a été rendue au terminal : sa boîte de dialogue s'ouvre alors, et
  /// la même question ne doit pas revenir sur la carte avant que la session passe à autre chose.
  private var handedBack: Set<String> = []

  /// La demande à montrer, la plus récente.
  var current: AgentEvent? { pending.last?.event }

  /// Combien de demandes attendent, la courante comprise.
  var count: Int { pending.count }

  /// Quand cette demande a été reçue.
  func receivedDate(of event: AgentEvent) -> Date? {
    pending.last { $0.event == event }?.date
  }

  /// Quand la demande sera rendue à l'agent (`{}`) faute de réponse, `nil` si elle attend sans limite
  /// (une permission) ou n'attend pas de réponse.
  func handBackDeadline(of event: AgentEvent) -> Date? {
    guard event.replyID != nil, let received = receivedDate(of: event) else { return nil }
    switch event.response {
    case .permission: return nil
    case .question, .elicitation:
      return received.addingTimeInterval(AgentHookServer.defaultQuestionWait)
    case .stopReply:
      return received.addingTimeInterval(AgentHookServer.defaultStopReplyWait)
    }
  }

  /// Applique un événement. Renvoie `true` si l'ensemble des demandes en attente a changé.
  @discardableResult
  mutating func apply(_ event: AgentEvent, now: Date = Date()) -> Bool {
    let key = event.sessionID ?? ""
    if event.kind.resolvesPrompt { handedBack.remove(key) }
    if let prompt = event.prompt {
      if case .questions = prompt, event.replyID != nil, handedBack.contains(key) { return false }
      // La notification de permission suit de peu la demande détaillée de la même session :
      // elle ne doit pas l'écraser.
      // Même chose pour la version d'affichage seul d'une demande à laquelle on peut répondre.
      let answerable = pending.first { $0.key == key }?.event.replyID != nil
      if case .message = prompt, pending.contains(where: { $0.key == key }) { return false }
      if event.replyID == nil, answerable { return false }
      pending.removeAll { $0.key == key }
      pending.append((key, event, now))
      return true
    }
    guard event.kind != .toolStart, event.sessionID != nil || event.kind == .clear,
      let index = pending.firstIndex(where: { $0.key == key })
    else { return false }
    pending.remove(at: index)
    return true
  }

  /// Retire la demande qui attendait cette réponse : elle a reçu sa réponse, ou son hook a été
  /// annulé (réponse donnée dans le terminal, session tuée).
  @discardableResult
  mutating func remove(replyID: String) -> Bool {
    let count = pending.count
    pending.removeAll { $0.event.replyID == replyID }
    return pending.count != count
  }

  /// Fait de cette demande la courante, pour que la carte l'affiche (choisie depuis la liste des sessions).
  @discardableResult
  mutating func bringToFront(replyID: String) -> Bool {
    guard let index = pending.firstIndex(where: { $0.event.replyID == replyID }),
      index != pending.count - 1
    else { return false }
    pending.append(pending.remove(at: index))
    return true
  }

  /// La question de cette session est rendue au terminal (« Reply in terminal »).
  mutating func noteHandedBack(_ event: AgentEvent) {
    guard case .questions = event.prompt, let session = event.sessionID else { return }
    handedBack.insert(session)
  }

  /// Retire les demandes plus anciennes que `cutoff` : une session tuée ou plantée ne signale
  /// jamais sa fin, et sa pastille resterait sinon pour toujours.
  @discardableResult
  mutating func expire(before cutoff: Date) -> Bool {
    let count = pending.count
    pending.removeAll { $0.date < cutoff }
    return pending.count != count
  }
}
