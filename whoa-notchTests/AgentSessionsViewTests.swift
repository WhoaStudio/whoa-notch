import AppKit
import Foundation
import Testing

@testable import whoa_notch

@Suite struct AgentSessionsViewTests {

  /// Une session bloquée sur une permission, dans une vue assez grande pour tout ranger.
  @MainActor private func blockedView() -> AgentSessionsView {
    var store = AgentSessionStore()
    store.apply(AgentEvent(kind: .turnStart, project: "app", sessionID: "A", text: "task"))
    store.apply(
      AgentEvent(
        kind: .needsInput, project: "app", sessionID: "A",
        prompt: .tool(name: "Bash", detail: "git push"), replyID: "r1"))
    let view = AgentSessionsView(frame: NSRect(x: 0, y: 0, width: 740, height: 240))
    view.apply(sessions: store.sessions, selectedID: "A")
    view.layoutSubtreeIfNeeded()
    return view
  }

  @Test("le clic sur Allow atteint le bouton, pas la relecture posée par-dessus")
  @MainActor func allowButtonReceivesClicks() throws {
    let view = blockedView()
    let allow = try #require(
      view.subviews.compactMap { $0 as? PromptButton }.first { $0.isPrimary && !$0.isHidden })
    let center = NSPoint(x: allow.frame.midX, y: allow.frame.midY)
    let hit = try #require(view.hitTest(center))
    #expect(hit === allow || hit.isDescendant(of: allow))
  }
}
