import Foundation
import Testing

@testable import whoa_stash

/// Le point d'entrée d'utilisation de Claude répond 429 quand on le sollicite trop : l'erreur doit
/// le dire, et le rafraîchissement doit s'arrêter le temps demandé au lieu de marteler.
@MainActor
struct ClaudeUsageRateLimitTests {

  private actor Calls {
    private(set) var count = 0
    func next() -> Int {
      count += 1
      return count
    }
  }

  /// Répond 429 au premier appel, puis un instantané.
  private struct LimitedThenFine: ClaudeUsageProviding {
    let calls: Calls
    let retryAfter: TimeInterval?

    func fetchSnapshot() async throws -> ClaudeUsageSnapshot {
      if await calls.next() == 1 {
        throw ClaudeUsageServiceError.rateLimited(retryAfter: retryAfter)
      }
      let window = ClaudeUsageWindow(utilization: 0.3, resetsAt: Date(timeIntervalSince1970: 1))
      return ClaudeUsageSnapshot(session: window, allModels: window)
    }
  }

  private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<100 {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test func `le statut 429 devient une erreur de limite avec le délai du serveur`() {
    #expect(
      ClaudeUsageServiceError.error(forStatus: 429, retryAfter: "120")
        == .rateLimited(retryAfter: 120))
    #expect(
      ClaudeUsageServiceError.error(forStatus: 429, retryAfter: nil)
        == .rateLimited(retryAfter: nil))
    #expect(ClaudeUsageServiceError.error(forStatus: 500, retryAfter: "120") == .badStatus(500))
  }

  @Test func `Retry-After accepte des secondes ou une date HTTP`() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)  // 2001-09-09 01:46:40 GMT
    #expect(ClaudeUsageServiceError.delay(fromRetryAfter: " 90 ", now: now) == 90)
    #expect(
      ClaudeUsageServiceError.delay(
        fromRetryAfter: "Sun, 09 Sep 2001 01:51:40 GMT", now: now) == 300)
    #expect(ClaudeUsageServiceError.delay(fromRetryAfter: "bientôt", now: now) == nil)
  }

  @Test func `l'attente double sans Retry-After et suit celui du serveur sinon`() {
    let delay = ClaudeUsageViewModel.rateLimitDelay
    #expect(delay(nil, 1) == 300)
    #expect(delay(nil, 2) == 600)
    #expect(delay(nil, 5) == 3600)
    #expect(delay(nil, 9) == 3600)
    #expect(delay(7_200, 1) == 7_200)
    #expect(delay(5, 1) == 60)
  }

  @Test func `la raison affichée dit que Claude limite les requêtes et quand réessayer`() async {
    let model = ClaudeUsageViewModel(
      provider: LimitedThenFine(calls: Calls(), retryAfter: 300),
      now: { Date(timeIntervalSince1970: 1_000) })
    model.refresh()
    await waitUntil { model.state != .loading }
    guard case .unavailable(let reason) = model.state else {
      Issue.record("état attendu : unavailable, reçu \(model.state)")
      return
    }
    let retryTime = Date(timeIntervalSince1970: 1_300).formatted(date: .omitted, time: .shortened)
    #expect(reason.contains("429"))
    #expect(reason.contains("nouvel essai à \(retryTime)"))
  }

  @Test func `après un 429 aucun appel n'est refait avant la fin du délai`() async {
    let calls = Calls()
    var time = Date(timeIntervalSince1970: 1_000)
    let model = ClaudeUsageViewModel(
      provider: LimitedThenFine(calls: calls, retryAfter: 300), now: { time })

    model.refresh()
    await waitUntil { await calls.count == 1 && model.state != .loading }
    guard case .unavailable = model.state else {
      Issue.record("état attendu : unavailable, reçu \(model.state)")
      return
    }

    time = Date(timeIntervalSince1970: 1_000 + 60)
    model.refresh()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await calls.count == 1)

    time = Date(timeIntervalSince1970: 1_000 + 301)
    model.refresh()
    await waitUntil { model.state.snapshot != nil }
    #expect(await calls.count == 2)
    #expect(model.state.snapshot?.session.percentage == 30)
  }

  @Test func `sans délai du serveur l'attente par défaut est de cinq minutes`() async {
    let calls = Calls()
    var time = Date(timeIntervalSince1970: 1_000)
    let model = ClaudeUsageViewModel(
      provider: LimitedThenFine(calls: calls, retryAfter: nil), now: { time })

    model.refresh()
    await waitUntil { await calls.count == 1 && model.state != .loading }

    time = Date(timeIntervalSince1970: 1_000 + 299)
    model.refresh()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await calls.count == 1)
  }
}
