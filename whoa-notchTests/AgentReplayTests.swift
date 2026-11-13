import AppKit
import Foundation
import Testing

@testable import whoa_notch

@Suite struct AgentReplayTests {

  private let start = Date(timeIntervalSince1970: 1_000)

  private func session(_ events: [AgentEvent]) -> AgentSession {
    var store = AgentSessionStore()
    for event in events { store.apply(event, now: start) }
    return store.session("s")!
  }

  private func event(_ kind: AgentEvent.Kind, tool: ToolCall? = nil, text: String? = nil) -> AgentEvent {
    AgentEvent(kind: kind, project: "korus", sessionID: "s", tool: tool, text: text)
  }

  private func tool(_ name: String, _ step: AgentStep?, file: String? = nil) -> AgentEvent {
    event(.toolStart, tool: ToolCall(name: name, step: step, filePath: file, cwd: "/p"))
  }

  @Test("la frise suit l'ordre chronologique des actions, sur plus de dix étapes")
  func chronologicalOrder() {
    var events = [event(.turnStart, text: "task")]
    let names = ["Read", "Grep", "Read", "Edit", "Bash", "Read", "Edit", "Edit", "Bash", "Read", "Write", "Bash"]
    for (index, name) in names.enumerated() {
      let step: AgentStep = name == "Bash" ? .bash : (name == "Edit" || name == "Write" ? .edit : .read)
      events.append(tool(name, step, file: "/p/src/f\(index).ts"))
    }
    events.append(event(.finished))
    let items = AgentReplay.items(for: session(events))
    #expect(items.count == 13)
    #expect(items.dropLast().map(\.label) == names)
    #expect(items.last?.kind == .done)
    // Chaque action garde son rang : les chemins sont relatifs au dossier de la session.
    #expect(items[0].path == "src/f0.ts")
    #expect(items[11].path == nil)
  }

  @Test("seul l'outil en cours tourne, les autres sont faits")
  func activeState() {
    let items = AgentReplay.items(
      for: session([
        event(.turnStart, text: "task"), tool("Read", .read, file: "/p/a.ts"),
        tool("Edit", .edit, file: "/p/a.ts"),
      ]))
    #expect(items.map(\.state) == [.done, .active])
  }

  @Test("une fois le tour fini, plus rien ne tourne et Done termine la frise")
  func finishedIsDone() {
    let items = AgentReplay.items(
      for: session([
        event(.turnStart, text: "task"), tool("Read", .read, file: "/p/a.ts"), event(.finished),
      ]))
    #expect(items.map(\.state) == [.done, .done])
    #expect(items.last?.label == "Done")
  }

  @Test("un refus est une erreur, une autorisation est faite")
  func decisions() {
    var store = AgentSessionStore()
    let ask = AgentEvent(
      kind: .needsInput, project: "korus", sessionID: "s",
      prompt: .tool(name: "Bash", detail: "rm -rf build"), replyID: "r")
    store.apply(event(.turnStart, text: "task"), now: start)
    store.apply(ask, now: start)
    #expect(AgentReplay.items(for: store.session("s")!).last?.kind == .approval)

    store.record(.deny, for: ask, now: start)
    store.remove(replyID: "r")
    let items = AgentReplay.items(for: store.session("s")!)
    #expect(items.last?.kind == .denied)
    #expect(items.last?.state == .failed)
    #expect(items.contains { $0.kind == .approval } == false)
  }

  @Test("une édition garde ses lignes retirées puis ajoutées")
  func editDetail() {
    let call = ToolCall(
      name: "Edit", step: .edit, filePath: "/p/invoice.ts", snippet: ["const TVA = 0.196"], cwd: "/p",
      removed: ["const TVA = 0.2"])
    let items = AgentReplay.items(
      for: session([event(.turnStart, text: "task"), event(.toolStart, tool: call)]))
    #expect(items.last?.path == "invoice.ts")
    #expect(
      items.last?.detail == [
        CodeLine(text: "const TVA = 0.2", kind: .removed),
        CodeLine(text: "const TVA = 0.196", kind: .added),
      ])
  }

  @Test("une commande Bash montre sa première ligne")
  func bashSummary() {
    let call = ToolCall(name: "Bash", step: .bash, snippet: ["git push origin main", "echo ok"])
    let items = AgentReplay.items(
      for: session([event(.turnStart, text: "task"), event(.toolStart, tool: call)]))
    #expect(items.last?.summary == "git push origin main")
  }

  @Test("une consigne envoyée figure dans la frise, en attente tant qu'elle n'est pas remise")
  func steerItem() {
    var store = AgentSessionStore()
    store.apply(event(.turnStart, text: "task"), now: start)
    _ = store.steer("use yarn", to: "s", now: start)
    #expect(AgentReplay.items(for: store.session("s")!).last?.state == .active)
    store.markSteerDelivered("use yarn", for: "s")
    #expect(AgentReplay.items(for: store.session("s")!).last?.state == .done)
  }

  @Test("old_string d'une édition est lu comme lignes retirées")
  func toolCallParsesRemovedText() {
    let call = ToolCall(
      name: "Edit", input: ["file_path": "/p/a.ts", "old_string": "a\nb", "new_string": "c"],
      cwd: "/p")
    #expect(call.removed == ["a", "b"])
    #expect(call.snippet == ["c"])
  }

  @Test("le texte de l'historique n'a aucune image maison, que des symboles SF")
  @MainActor func historyTextUsesSymbolsOnly() {
    let items = [
      AgentReplay.Item(kind: .tool(.read), label: "Read", path: "a.ts", state: .done),
      AgentReplay.Item(kind: .denied, label: "Denied", state: .failed),
      AgentReplay.Item(kind: .tool(.bash), label: "Bash", summary: "ls", state: .active),
    ]
    let text = AgentActivityCardView.historyText(items)
    var attachments = 0
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
      if value is NSTextAttachment { attachments += 1 }
    }
    #expect(attachments == 3)
    #expect(text.string.contains("Denied"))
  }
}
