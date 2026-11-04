import Foundation
import Testing

@testable import whoa_stash

/// Texte de la pastille d'usage posée dans l'en-tête du panneau de l'encoche.
@Suite struct ActivityFormattingTests {

    @Test("la pastille montre les jetons et le coût du mois sur une ligne")
    func chipShowsTokensAndCost() {
        let summary = ActivitySummary(
            tokens: 1_800_000, cost: 49.13, forecast: 851.75, activeDays: 2, daysInPeriod: 30)
        #expect(ActivityFormatting.chip(summary) == "1.8M · $49.13")
    }

    @Test("l'onglet Analytics classe les modèles du mois par jetons décroissants")
    func breakdownRanksModelsByTokens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!

        func record(_ key: String, _ model: String, input: Int, date: Date) -> ActivityRecord {
            ActivityRecord(
                key: key, date: date, agent: .claudeCode, model: model, project: "whoa-stash",
                tokens: TokenCounts(input: input, output: 0))
        }
        let records = [
            record("a", "claude-opus-5-5", input: 1_000, date: now),
            record("b", "claude-sonnet-5-5", input: 5_000, date: now),
            record("c", "claude-opus-5-5", input: 2_000, date: now),
            record("d", "claude-haiku-5-5", input: 9_000, date: lastMonth),
        ]

        let rows = ActivityAggregator.breakdown(
            records: records, filter: ActivityFilter(), now: now, calendar: calendar, limit: 1)
        #expect(rows.map(\.model) == ["claude-sonnet-5-5"])

        let all = ActivityAggregator.breakdown(
            records: records, filter: ActivityFilter(), now: now, calendar: calendar, limit: 5)
        #expect(all.map(\.model) == ["claude-sonnet-5-5", "claude-opus-5-5"])
        #expect(all[1].tokens == 3_000)
    }

    @Test("la pastille affiche n/a quand aucun tarif n'est connu")
    func chipWithoutKnownPrice() {
        let summary = ActivitySummary(tokens: 842, cost: nil, forecast: nil, activeDays: 1, daysInPeriod: 30)
        #expect(ActivityFormatting.chip(summary) == "842 · n/a")
    }
}
