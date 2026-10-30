import Foundation

/// Les demandes d'agent encore sans réponse, une par session. L'encoche montre la plus récente ;
/// elle disparaît dès que la même session signale autre chose (outil exécuté, nouveau prompt, fin).
///
/// Aucun hook ne signale la réponse de l'utilisateur à une demande : c'est le premier événement
/// suivant de la session qui fait foi.
nonisolated struct AgentPromptStore {

    private var pending: [(key: String, event: AgentEvent, date: Date)] = []

    /// La demande à montrer, la plus récente.
    var current: AgentEvent? { pending.last?.event }

    /// Applique un événement. Renvoie `true` si l'ensemble des demandes en attente a changé.
    @discardableResult
    mutating func apply(_ event: AgentEvent, now: Date = Date()) -> Bool {
        let key = event.sessionID ?? ""
        if let prompt = event.prompt {
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
        guard event.kind != .toolStart, event.sessionID != nil || event.kind == .clear, let index = pending.firstIndex(where: { $0.key == key }) else { return false }
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

    /// Retire les demandes plus anciennes que `cutoff` : une session tuée ou plantée ne signale
    /// jamais sa fin, et sa pastille resterait sinon pour toujours.
    @discardableResult
    mutating func expire(before cutoff: Date) -> Bool {
        let count = pending.count
        pending.removeAll { $0.date < cutoff }
        return pending.count != count
    }
}
