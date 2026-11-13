import Foundation
import Testing

@testable import whoa_stash

/// Courbe d'usage de la section Activity : les jetons du mois, jour par jour.
@Suite struct ActivityDailyTokensTests {

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  private func record(
    _ key: String, day: Int, month: Int = 11, hour: Int = 12, agent: ActivityAgent = .claudeCode,
    input: Int, output: Int = 0
  ) -> ActivityRecord {
    ActivityRecord(
      key: key, date: date(day, month: month, hour: hour), agent: agent,
      model: agent == .codex ? "gpt-6.1-sol" : "claude-opus-5-5", project: "whoa-stash",
      tokens: TokenCounts(input: input, output: output, cacheRead: 9_999))
  }

  private var records: [ActivityRecord] {
    [
      record("a", day: 2, hour: 8, input: 1_000, output: 500),
      record("b", day: 2, hour: 20, input: 2_000),
      record("c", day: 9, agent: .codex, input: 4_000, output: 1_000),
      record("d", day: 10, month: 10, input: 10_000),
    ]
  }

  private func series(_ filter: ActivityFilter = ActivityFilter()) -> [ActivityDay] {
    ActivityAggregator.dailyTokens(
      records: records, filter: filter, now: date(15), calendar: calendar)
  }

  @Test func `un point par jour du mois, les jours sans activité valent zéro`() {
    let days = series()

    #expect(days.count == 30)
    #expect(days.first?.date == calendar.startOfDay(for: date(1)))
    #expect(days.last?.date == calendar.startOfDay(for: date(30)))
    #expect(days[1].tokens == 3_500)
    #expect(days[8].tokens == 5_000)
    #expect(days.map(\.tokens).reduce(0, +) == 8_500)
  }

  @Test func `la relecture du cache ne compte pas dans la courbe`() {
    // Même mesure que « Tokens » : entrée et sortie seulement.
    #expect(series().map(\.tokens).reduce(0, +) == 3_500 + 5_000)
  }

  @Test func `les filtres de la section s'appliquent à la courbe`() {
    let codex = series(ActivityFilter(agent: .codex))
    #expect(codex.map(\.tokens).reduce(0, +) == 5_000)
    #expect(codex[1].tokens == 0)

    let none = series(ActivityFilter(agent: .codex, model: "claude-opus-5-5"))
    #expect(none.allSatisfy { $0.tokens == 0 })
  }

  @Test func `un autre mois donne sa propre longueur et ses propres jetons`() {
    let october = series(ActivityFilter(monthOffset: 1))

    #expect(october.count == 31)
    #expect(october[9].tokens == 10_000)
    #expect(october.map(\.tokens).reduce(0, +) == 10_000)
  }

  @Test func `le total de la courbe égale les jetons du résumé`() {
    let filter = ActivityFilter(agent: .claudeCode)
    let summary = ActivityAggregator.summarize(
      records: records, filter: filter, now: date(15), calendar: calendar)

    #expect(series(filter).map(\.tokens).reduce(0, +) == summary.tokens)
  }
}
