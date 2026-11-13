import Foundation
import Testing

@testable import whoa_notch

/// Session Claude Code expirée : l'état doit le dire et proposer la reconnexion, au lieu de
/// retomber sur un « indisponible » muet.
@MainActor
struct ClaudeUsageExpiredTests {

  private struct ThrowingProvider: ClaudeUsageProviding {
    let error: Error
    func fetchSnapshot() async throws -> ClaudeUsageSnapshot { throw error }
  }

  private func settled(_ model: ClaudeUsageViewModel) async {
    for _ in 0..<100 {
      if model.state != .loading { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test func unJetonExpireDonneLEtatExpire() async {
    let model = ClaudeUsageViewModel(
      provider: ThrowingProvider(error: ClaudeUsageCredentialError.expired))
    model.refresh()
    await settled(model)
    guard case .expired = model.state else {
      Issue.record("état attendu : expired, reçu \(model.state)")
      return
    }
  }

  @Test func uneErreurReseauResteIndisponibleSansReconnexion() async {
    let model = ClaudeUsageViewModel(
      provider: ThrowingProvider(error: ClaudeUsageServiceError.badStatus(500)))
    model.refresh()
    await settled(model)
    guard case .unavailable = model.state else {
      Issue.record("état attendu : unavailable, reçu \(model.state)")
      return
    }
    #expect(!NotchUsageReading.claude(model.state).needsReauth)
  }

  @Test func laLectureExpireeProposeLaReconnexion() {
    let reading = NotchUsageReading.claude(.expired(reason: "périmé"))
    #expect(reading.needsReauth)
    #expect(reading.status == .unavailable(reason: "périmé"))
    #expect(reading.windowLabel == "5H")
  }
}
