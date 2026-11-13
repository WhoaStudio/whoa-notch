import Foundation
import Testing

@testable import whoa_notch

/// Les trois fournisseurs de l'onglet AI passent par la même interface : une lecture réelle, ou un
/// état d'erreur propre à l'agent avec la raison.
@MainActor
struct UsageProvidingTests {

  private struct Failing: UsageProviding {
    let provider: NotchUsageProvider
    let error: Error
    func fetchReading() async throws -> NotchUsageReading { throw error }
  }

  private func codexPayload(primarySeconds: Int, secondarySeconds: Int) -> Data {
    Data(
      """
      {"rate_limit":{
        "primary_window":{"used_percent":25,"limit_window_seconds":\(primarySeconds),"reset_after_seconds":7200},
        "secondary_window":{"used_percent":40,"limit_window_seconds":\(secondarySeconds),"reset_after_seconds":300000}}}
      """.utf8)
  }

  @Test func codexAffichePremierLHebdomadaireEtLaSessionDessous() throws {
    let snapshot = try CodexUsageService.parse(
      codexPayload(primarySeconds: 18_000, secondarySeconds: 604_800))
    let reading = NotchUsageReading.codex(.loaded(snapshot))
    #expect(reading.windowLabel == "7D")
    #expect(reading.remainingPercentage == 60)
    #expect(reading.secondaryLine == "5H 75% remaining")
    #expect(!reading.needsReauth)
  }

  @Test func codexSansHebdomadaireMontreLaSession() throws {
    let data = Data(
      #"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000,"reset_after_seconds":60}}}"#
        .utf8)
    let reading = NotchUsageReading.codex(.loaded(try CodexUsageService.parse(data)))
    #expect(reading.windowLabel == "5H")
    #expect(reading.remainingPercentage == 90)
  }

  @Test func codexIllisibleRemonteLesClesRecues() {
    #expect(throws: CodexUsageServiceError.self) {
      try CodexUsageService.parse(Data(#"{"autre":1}"#.utf8))
    }
  }

  @Test func claudeEtCopilotDonnentUneLectureChargee() throws {
    let claude = try ClaudeUsageService.parse(
      Data(
        """
        {"five_hour":{"utilization":30,"resets_at":"2026-11-01T18:00:00Z"},
         "seven_day":{"utilization":10,"resets_at":"2026-11-05T18:00:00Z"}}
        """.utf8))
    #expect(NotchUsageReading.claude(.loaded(claude)).remainingPercentage == 70)

    let copilot = try CopilotUsageService.parse(
      Data(
        """
        {"quota_snapshots":{"premium_interactions":{"percent_remaining":80}},"quota_reset_date_utc":"2026-12-01T00:00:00Z"}
        """.utf8))
    #expect(NotchUsageReading.copilot(.loaded(copilot)).remainingPercentage == 80)
  }

  @Test func uneErreurDonneUnEtatPropreALAgentAvecSaRaison() async {
    for provider in NotchUsageProvider.allCases {
      let reading = await Failing(provider: provider, error: ClaudeUsageServiceError.badStatus(500))
        .currentReading()
      #expect(reading.windowLabel == provider.windowLabel)
      guard case .unavailable(let reason) = reading.status else {
        Issue.record("\(provider.name) : état d'erreur attendu")
        continue
      }
      #expect(!reason.isEmpty)
      #expect(!reading.needsReauth)
    }
  }

  @Test func laReconnexionEstProposeSeulementQuandElleRepare() async {
    let claude = await Failing(provider: .claude, error: ClaudeUsageCredentialError.expired)
      .currentReading()
    #expect(claude.needsReauth)

    let codexRefuse = await Failing(provider: .codex, error: CodexUsageServiceError.badStatus(401))
      .currentReading()
    #expect(codexRefuse.needsReauth)
    let codexAbsent = await Failing(provider: .codex, error: CodexUsageCredentialError.notSignedIn)
      .currentReading()
    #expect(codexAbsent.needsReauth)
    let codexPanne = await Failing(provider: .codex, error: CodexUsageServiceError.badStatus(503))
      .currentReading()
    #expect(!codexPanne.needsReauth)

    let copilot = await Failing(provider: .copilot, error: CopilotUsageServiceError.badStatus(401))
      .currentReading()
    #expect(!copilot.needsReauth)
  }
}
