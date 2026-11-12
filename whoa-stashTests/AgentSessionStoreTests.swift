import Foundation
import Testing

@testable import whoa_stash

@Suite struct AgentSessionStoreTests {

  private let start = Date(timeIntervalSince1970: 1_000)

  private func turn(_ session: String, _ prompt: String) -> AgentEvent {
    AgentEvent(kind: .turnStart, project: "app-\(session)", sessionID: session, text: prompt)
  }

  private func tool(_ session: String, _ name: String, file: String) -> AgentEvent {
    AgentEvent(
      kind: .toolStart, project: "app-\(session)", sessionID: session,
      tool: ToolCall(name: name, step: .edit, filePath: file))
  }

  private func permission(_ session: String, command: String, reply: String) -> AgentEvent {
    AgentEvent(
      kind: .needsInput, project: "app-\(session)", sessionID: session,
      prompt: .tool(name: "Bash", detail: command), replyID: reply)
  }

  @Test("deux sessions tournent en même temps, chacune avec sa tâche et son action")
  func twoSessionsRunAtOnce() {
    var store = AgentSessionStore()
    store.apply(turn("A", "fix the checkout"), now: start)
    store.apply(turn("B", "write the docs"), now: start.addingTimeInterval(1))
    store.apply(tool("A", "Edit", file: "/p/checkout.ts"), now: start.addingTimeInterval(2))
    store.apply(tool("B", "Read", file: "/p/README.md"), now: start.addingTimeInterval(3))

    #expect(store.sessions.map(\.id) == ["A", "B"])
    #expect(store.session("A")?.task == "fix the checkout")
    #expect(store.session("A")?.action == "Edit checkout.ts")
    #expect(store.session("B")?.action == "Read README.md")
    #expect(store.workingCount == 2)
  }

  @Test("chaque session garde son propre journal")
  func eachSessionKeepsItsOwnLog() {
    var store = AgentSessionStore()
    store.apply(turn("A", "fix the checkout"), now: start)
    store.apply(turn("B", "write the docs"), now: start)
    store.apply(tool("A", "Edit", file: "/p/checkout.ts"), now: start)
    store.apply(
      AgentEvent(kind: .finished, project: "app-B", sessionID: "B", text: "Docs done"), now: start)

    let a = store.session("A")?.log.map(\.content)
    let b = store.session("B")?.log.map(\.content)
    #expect(a?.count == 2)
    #expect(a?.first == .prompt("fix the checkout"))
    #expect(b == [.prompt("write the docs"), .reply("Docs done")])
    // Le fil de discussion n'a que les messages, la relecture a aussi les outils.
    #expect(store.session("A")?.thread.count == 1)
  }

  @Test("les statuts suivent working, blocked, working, waiting, done")
  func statusesFollowTheSession() {
    var store = AgentSessionStore()
    store.apply(turn("A", "task"), now: start)
    #expect(store.session("A")?.status == .working)

    store.apply(permission("A", command: "git push", reply: "r1"), now: start)
    #expect(store.session("A")?.status == .blocked)
    #expect(store.session("A")?.action == "Allow Bash? git push")
    #expect(store.blockedCount == 1)

    store.remove(replyID: "r1")
    #expect(store.session("A")?.status == .working)
    #expect(store.session("A")?.pending == nil)

    store.apply(AgentEvent(kind: .finished, project: "app-A", sessionID: "A"), now: start)
    #expect(store.session("A")?.status == .waiting)

    store.apply(AgentEvent(kind: .sessionEnd, project: "app-A", sessionID: "A"), now: start)
    #expect(store.session("A")?.status == .done)
  }

  @Test("la durée s'arrête à la fin du tour et repart au prompt suivant")
  func elapsedTime() {
    var store = AgentSessionStore()
    store.apply(turn("A", "task"), now: start)
    #expect(store.session("A")?.elapsed(now: start.addingTimeInterval(42)) == 42)

    store.apply(
      AgentEvent(kind: .finished, project: "app-A", sessionID: "A"),
      now: start.addingTimeInterval(60))
    #expect(store.session("A")?.elapsed(now: start.addingTimeInterval(500)) == 60)

    store.apply(turn("A", "again"), now: start.addingTimeInterval(500))
    #expect(store.session("A")?.elapsed(now: start.addingTimeInterval(510)) == 10)
  }

  @Test("une permission de A ne bloque pas B")
  func blockedSessionDoesNotAffectTheOther() {
    var store = AgentSessionStore()
    store.apply(turn("A", "a"), now: start)
    store.apply(turn("B", "b"), now: start)
    store.apply(permission("A", command: "rm -rf build", reply: "ra"), now: start)

    #expect(store.session("A")?.status == .blocked)
    #expect(store.session("B")?.status == .working)
    #expect(store.session("B")?.pending == nil)
    #expect(store.selected?.id == "A")

    // L'approbation de A n'ajoute rien au journal de B.
    store.record(.allow, for: permission("A", command: "rm -rf build", reply: "ra"), now: start)
    #expect(store.session("A")?.log.last?.content == .decision(.allow))
    #expect(store.session("B")?.log.contains { $0.content == .decision(.allow) } == false)
  }

  @Test("une consigne va à la session visée seulement, notée dans son journal")
  func steerIsRoutedToOneSession() {
    var store = AgentSessionStore()
    store.apply(turn("A", "a"), now: start)
    store.apply(turn("B", "b"), now: start)

    let route = store.steer("  use yarn  ", to: "A", now: start)
    #expect(route == .queue(sessionID: "A"))
    #expect(store.session("A")?.log.last?.content == .steer("use yarn", delivered: false))
    #expect(store.session("A")?.log.last?.sender == .user)
    #expect(store.session("B")?.log.contains { if case .steer = $0.content { true } else { false } } == false)

    store.markSteerDelivered("use yarn", for: "B")
    #expect(store.session("A")?.log.last?.content == .steer("use yarn", delivered: false))
    store.markSteerDelivered("use yarn", for: "A")
    #expect(store.session("A")?.log.last?.content == .steer("use yarn", delivered: true))
  }

  @Test("une consigne à une session qui attend une suite part par sa réponse libre")
  func steerToWaitingSessionUsesTheReply() {
    var store = AgentSessionStore()
    store.apply(turn("A", "a"), now: start)
    let stop = AgentEvent(
      kind: .finished, project: "app-A", sessionID: "A", prompt: .reply("done"), replyID: "r9",
      response: .stopReply, text: "done")
    store.apply(stop, now: start)

    let route = store.steer("also add tests", to: "A", now: start)
    #expect(route == .reply(stop))
  }

  @Test("une consigne vide, inconnue ou pour une session close est refusée")
  func steerIsRejected() {
    var store = AgentSessionStore()
    store.apply(turn("A", "a"), now: start)
    let empty = store.steer("  ", to: "A")
    #expect(empty == .rejected)
    let unknown = store.steer("hello", to: "missing")
    #expect(unknown == .rejected)
    store.apply(AgentEvent(kind: .sessionEnd, project: "app-A", sessionID: "A"), now: start)
    let closed = store.steer("hello", to: "A")
    #expect(closed == .rejected)
  }

  @Test("une session inactive expire, une session récente reste")
  func expiry() {
    var store = AgentSessionStore()
    store.apply(turn("A", "a"), now: start)
    store.apply(turn("B", "b"), now: start.addingTimeInterval(800))

    let late = start.addingTimeInterval(AgentSessionStore.workingLifetime + 1)
    let expired = store.expire(now: late)
    #expect(expired)
    #expect(store.sessions.map(\.id) == ["B"])
  }

  @Test("un clear ou une fin pour une session inconnue ne crée rien")
  func unknownSessionIsIgnored() {
    var store = AgentSessionStore()
    let cleared = store.apply(AgentEvent(kind: .clear, project: "x", sessionID: "Z"), now: start)
    let ended = store.apply(AgentEvent(kind: .sessionEnd, project: "x", sessionID: "Z"), now: start)
    #expect(!cleared && !ended)
    #expect(store.sessions.isEmpty)
  }
}
