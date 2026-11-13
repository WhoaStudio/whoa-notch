import Foundation
import Testing

@testable import whoa_stash

/// Mesures de la section Activity : chaque filtre change les chiffres, et ils se combinent.
@Suite struct ActivityFilterTests {

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(_ day: Int, month: Int = 11) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
  }

  private var now: Date { date(15) }

  private func record(
    _ key: String, day: Int, month: Int = 11, agent: ActivityAgent = .claudeCode,
    model: String = "claude-opus-5-5", project: String = "whoa-stash", input: Int = 1_000,
    output: Int = 500
  ) -> ActivityRecord {
    ActivityRecord(
      key: key, date: date(day, month: month), agent: agent, model: model, project: project,
      tokens: TokenCounts(input: input, output: output))
  }

  private var records: [ActivityRecord] {
    [
      record("a", day: 2),
      record("b", day: 2, model: "claude-sonnet-5-5", project: "claude-kit"),
      record(
        "c", day: 9, agent: .codex, model: "gpt-5-codex", project: "api", input: 4_000,
        output: 1_000),
      record("d", day: 10, month: 10, input: 10_000, output: 0),
    ]
  }

  private func summary(_ filter: ActivityFilter = ActivityFilter()) -> ActivitySummary {
    ActivityAggregator.summarize(records: records, filter: filter, now: now, calendar: calendar)
  }

  @Test func sansFiltreLeMoisEnCoursEstSommeSansLesAutresMois() {
    let result = summary()
    #expect(result.tokens == 1_500 + 1_500 + 5_000)
    #expect(result.activeDays == 2)
    #expect(result.daysInPeriod == 30)
  }

  @Test func leMoisPrecedentChangeLesChiffres() {
    let result = summary(ActivityFilter(monthOffset: 1))
    #expect(result.tokens == 10_000)
    #expect(result.activeDays == 1)
  }

  @Test func chaqueFiltreRestreintLesChiffres() {
    #expect(summary(ActivityFilter(agent: .codex)).tokens == 5_000)
    #expect(summary(ActivityFilter(model: "claude-sonnet-5-5")).tokens == 1_500)
    #expect(summary(ActivityFilter(project: "whoa-stash")).tokens == 1_500)
  }

  @Test func lesFiltresSeCombinent() {
    let both = summary(ActivityFilter(agent: .claudeCode, project: "claude-kit"))
    #expect(both.tokens == 1_500)
    #expect(both.activeDays == 1)

    let none = summary(ActivityFilter(agent: .codex, model: "claude-opus-5-5"))
    #expect(none.tokens == 0)
    #expect(none.activeDays == 0)
  }

  @Test func lesMenusNeProposentQueCeQueLePerimetreContient() {
    let all = ActivityAggregator.options(
      records: records, filter: ActivityFilter(), now: now, calendar: calendar)
    #expect(Set(all.models) == ["claude-opus-5-5", "claude-sonnet-5-5", "gpt-5-codex"])
    #expect(all.models.first == "gpt-5-codex")

    let codex = ActivityAggregator.options(
      records: records, filter: ActivityFilter(agent: .codex), now: now, calendar: calendar)
    #expect(codex.models == ["gpt-5-codex"])
    #expect(codex.projects == ["api"])

    let october = ActivityAggregator.options(
      records: records, filter: ActivityFilter(monthOffset: 1), now: now, calendar: calendar)
    #expect(october.models == ["claude-opus-5-5"])
  }

  @Test func leFormatDesMesures() {
    #expect(ActivityFormatting.tokens(842) == "842")
    #expect(ActivityFormatting.tokens(12_300) == "12.3K")
    #expect(ActivityFormatting.tokens(4_600_000) == "4.6M")
    #expect(ActivityFormatting.tokens(1_000_000_000) == "1B")
    #expect(ActivityFormatting.activeDays(summary()) == "2/30")
  }
}
