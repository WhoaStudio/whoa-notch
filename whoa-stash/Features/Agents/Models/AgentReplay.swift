import Foundation

/// L'historique d'une session tel que la relecture le montre : le journal réduit aux actions, dans
/// l'ordre, chacune avec son état. Rien ici ne touche à l'état des sessions.
nonisolated enum AgentReplay {

  /// Lignes de détail gardées par action (texte ajouté, retiré).
  static let detailLimit = 2

  nonisolated struct Item: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
      /// Un outil de l'agent ; l'étape sert à la couleur, `nil` pour un outil sans étape (MCP…).
      case tool(AgentStep?)
      /// Une demande d'autorisation encore sans réponse.
      case approval
      case allowed
      case denied
      /// Une consigne de l'utilisateur.
      case steer
      case done
      case ended
    }

    nonisolated enum State: Equatable, Sendable {
      case done, active, failed
    }

    var kind: Kind
    /// Le nom court de l'action : « Read », « Edit », « Bash », « Done »…
    var label: String
    /// Fichier concerné, relatif au dossier de la session quand c'est possible.
    var path: String?
    /// Une ligne de détail (commande, texte d'un message) à côté du libellé.
    var summary: String?
    /// Lignes ajoutées ou retirées d'une édition.
    var detail: [CodeLine] = []
    var state: State
  }

  /// Les actions de la session, de la plus ancienne à la plus récente.
  static func items(for session: AgentSession) -> [Item] {
    var items: [Item] = []
    for entry in session.log {
      switch entry.content {
      case .prompt:
        break
      case .tool(let call):
        items.append(item(for: call))
      case .request(let prompt):
        guard case .tool(_, let detail) = prompt else { break }
        items.append(
          Item(kind: .approval, label: "Approval", summary: oneLine(detail), state: .active))
      case .decision(let decision):
        // La demande qui vient de recevoir sa réponse n'est plus en attente.
        if let index = items.lastIndex(where: { $0.kind == .approval }) { items.remove(at: index) }
        switch decision {
        case .deny:
          items.append(Item(kind: .denied, label: "Denied", state: .failed))
        case .allow, .allowAlways:
          items.append(Item(kind: .allowed, label: "Allowed", state: .done))
        case .answer, .plan, .reply, .handBack:
          items.append(Item(kind: .allowed, label: "Answered", state: .done))
        }
      case .steer(let text, let delivered):
        items.append(
          Item(
            kind: .steer, label: "Steer", summary: delivered ? text : text + " (queued)",
            state: delivered ? .done : .active))
      case .reply(let text):
        items.append(Item(kind: .done, label: "Done", summary: oneLine(text), state: .done))
      case .ended:
        items.append(Item(kind: .ended, label: "Ended", state: .done))
      }
    }

    // Une demande qui n'attend plus (session repartie, réponse donnée dans le terminal) ne reste pas
    // affichée en cours.
    if session.status != .blocked {
      items.removeAll { $0.kind == .approval }
    }
    // Fin de tour sans message : l'étape « Done » est tout de même atteinte.
    if session.status == .waiting, items.last?.kind != .done {
      items.append(Item(kind: .done, label: "Done", state: .done))
    }
    // L'outil en cours tourne : son état est « en cours ».
    if session.status == .working, var last = items.last, case .tool = last.kind {
      last.state = .active
      items[items.count - 1] = last
    }
    return items
  }

  /// L'activité d'un agent sans journal : les étapes connues, la courante en cours.
  static func items(for activity: AgentActivity) -> [Item] {
    var items: [Item] = []
    for step in AgentStep.allCases where activity.visited.contains(step) || activity.step == step {
      let isCurrent = activity.step == step && step != .done
      var item = Item(
        kind: step == .done ? .done : .tool(step), label: step.title,
        state: isCurrent ? .active : .done)
      if isCurrent {
        item.path = relative(activity.filePath, to: activity.cwd)
        switch step {
        case .edit: item.detail = activity.snippet.prefix(detailLimit).map { CodeLine(text: $0, kind: .added) }
        case .bash: item.summary = activity.snippet.first
        case .read, .done: break
        }
      }
      items.append(item)
    }
    return items
  }

  private static func item(for call: ToolCall) -> Item {
    var item = Item(kind: .tool(call.step), label: call.name, state: .done)
    switch call.step {
    case .edit:
      item.path = relative(call.filePath, to: call.cwd)
      item.detail =
        call.removed.prefix(detailLimit).map { CodeLine(text: $0, kind: .removed) }
        + call.snippet.prefix(detailLimit).map { CodeLine(text: $0, kind: .added) }
    case .bash:
      item.summary = call.snippet.first.map { oneLine($0) }
    case .read, .done, nil:
      item.path = relative(call.filePath, to: call.cwd)
    }
    return item
  }

  /// Le chemin relatif au dossier de la session ; tel quel s'il est ailleurs.
  static func relative(_ path: String?, to cwd: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    if let cwd, !cwd.isEmpty, path.hasPrefix(cwd + "/") {
      return String(path.dropFirst(cwd.count + 1))
    }
    return path
  }

  private static func oneLine(_ text: String) -> String {
    let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    return line.count > 140 ? String(line.prefix(140)) : line
  }
}
