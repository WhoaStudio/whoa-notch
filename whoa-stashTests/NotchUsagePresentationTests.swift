import Foundation
import Testing

@testable import whoa_stash

@Suite("Présentation de l'onglet Usage")
struct NotchUsagePresentationTests {

  @Test("la teinte vire à l'ambre sous 30 % et au rouge sous 10 %")
  func teinteSelonLeReste() {
    #expect(NotchUsageTone(remaining: nil) == .plenty)
    #expect(NotchUsageTone(remaining: 1) == .plenty)
    #expect(NotchUsageTone(remaining: 0.30) == .plenty)
    #expect(NotchUsageTone(remaining: 0.29) == .low)
    #expect(NotchUsageTone(remaining: 0.10) == .low)
    #expect(NotchUsageTone(remaining: 0.09) == .critical)
    #expect(NotchUsageTone(remaining: 0) == .critical)
  }

  @Test("le rythme compare le reste à une consommation régulière")
  func rythme() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    // Fenêtre de 5 h, 2 h 30 restantes : une consommation régulière laisserait 50 %.
    let resets = now.addingTimeInterval(2.5 * 3600)
    let expected = NotchUsagePace.expectedRemaining(resetsAt: resets, windowLength: 5 * 3600, now: now)
    #expect(expected == 0.5)
    #expect(NotchUsagePace.evaluate(remaining: 0.3, expected: 0.5) == .over)
    #expect(NotchUsagePace.evaluate(remaining: 0.52, expected: 0.5) == .on)
    #expect(NotchUsagePace.evaluate(remaining: 0.8, expected: 0.5) == .under)
  }

  @Test("pas de rythme quand la réinitialisation est passée ou hors fenêtre")
  func rythmeSansReference() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(
      NotchUsagePace.expectedRemaining(
        resetsAt: now.addingTimeInterval(-10), windowLength: 3600, now: now) == nil)
    #expect(
      NotchUsagePace.expectedRemaining(
        resetsAt: now.addingTimeInterval(2 * 3600), windowLength: 3600, now: now) == nil)
    #expect(NotchUsagePace.windowLength(forLabel: "??") == nil)
    #expect(NotchUsagePace.windowLength(forLabel: "7D") == TimeInterval(7 * 24 * 3600))
  }

  @Test("la réinitialisation se lit en durée relative")
  func reinitialisationRelative() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func text(_ seconds: TimeInterval) -> String {
      NotchUsageFormatting.resetsIn(now.addingTimeInterval(seconds), now: now)
    }
    #expect(text(-5) == "Resetting…")
    #expect(text(30) == "Resets in 1 min")
    #expect(text(12 * 60) == "Resets in 12 min")
    #expect(text(2 * 3600 + 14 * 60) == "Resets in 2 h 14 min")
    #expect(text(3 * 3600) == "Resets in 3 h")
    #expect(text(3 * 86400 + 4 * 3600) == "Resets in 3 d 4 h")
  }

  @Test("l'ancienneté d'une lecture")
  func anciennete() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func text(_ seconds: TimeInterval) -> String {
      NotchUsageFormatting.updatedAgo(now.addingTimeInterval(-seconds), now: now)
    }
    #expect(text(10) == "Updated just now")
    #expect(text(3 * 60) == "Updated 3 min ago")
    #expect(text(2 * 3600) == "Updated 2 h ago")
  }

  @Test("consommé et restant font toujours 100")
  func complement() {
    for remaining in 0...100 {
      #expect(remaining + NotchUsageFormatting.usedPercentage(remainingPercentage: remaining) == 100)
    }
    #expect(NotchUsageFormatting.exactText(remaining: 0.473) == "47.3% remaining · 52.7% used")
    #expect(NotchUsageFormatting.exactText(remaining: 1) == "100.0% remaining · 0.0% used")
    // Hors bornes : ramené à 0…100 %.
    #expect(NotchUsageFormatting.exactText(remaining: 1.4) == "100.0% remaining · 0.0% used")
    #expect(NotchUsageFormatting.exactText(remaining: -0.2) == "0.0% remaining · 100.0% used")
  }

  @Test("les pannes simulées visent le bon fournisseur")
  func pannesSimulees() {
    func outcome(_ provider: String, _ flag: String) -> MockUsageBehavior.Outcome {
      MockUsageBehavior.failure(for: provider, arguments: ["--usage-fail=\(flag)"])
    }
    #expect(MockUsageBehavior.failure(for: "claude", arguments: []) == .none)
    #expect(outcome("claude", "all") == .failure)
    #expect(outcome("codex", "claude") == .none)
    #expect(outcome("claude", "claude:expired") == .expired)
    #expect(outcome("copilot", "claude:expired,copilot") == .failure)
    #expect(outcome("claude", "claude:expired,copilot") == .expired)
  }

  @Test("le délai simulé ignore les valeurs mal formées")
  func delaiSimule() {
    #expect(MockUsageBehavior.delay(["--usage-delay=2.5"]) == 2.5)
    #expect(MockUsageBehavior.delay(["--usage-delay=vite"]) == nil)
    #expect(MockUsageBehavior.delay([]) == nil)
  }
}
