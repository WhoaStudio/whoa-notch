import Foundation
import Testing

@testable import whoa_stash

/// Découpage d'un mois en cases. Le calcul dépend du premier jour de la semaine chez
/// l'utilisateur — lundi en France, dimanche aux États-Unis —, et c'est précisément ce qu'on ne
/// veut pas vérifier à l'œil sur une capture d'écran.
@MainActor
struct MonthGridLayoutTests {

  /// Calendrier grégorien figé sur un premier jour de semaine et une langue, pour que les tests
  /// ne dépendent pas des réglages de la machine qui les exécute.
  private static func calendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = firstWeekday
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
  }

  @Test(
    "octobre 2026 commence un jeudi : trois cases vides devant lui quand la semaine part du lundi")
  func leadingBlanksFollowMondayFirstWeekday() {
    let calendar = Self.calendar(firstWeekday: 2)
    let layout = MonthGridLayout(
      date: Self.date(2026, 10, 1, in: calendar),
      calendar: calendar,
      today: Self.date(2026, 10, 27, in: calendar)
    )

    #expect(
      layout.days.prefix(3).allSatisfy { $0 == nil },
      "lundi, mardi et mercredi doivent rester vides")
    #expect(layout.days[3] == 1, "le 1er octobre 2026 tombe un jeudi, donc en quatrième colonne")
  }

  @Test("le même mois décalé d'une case quand la semaine part du dimanche")
  func leadingBlanksFollowSundayFirstWeekday() {
    let calendar = Self.calendar(firstWeekday: 1)
    let layout = MonthGridLayout(
      date: Self.date(2026, 10, 1, in: calendar),
      calendar: calendar,
      today: Self.date(2026, 10, 27, in: calendar)
    )

    #expect(
      layout.days.prefix(4).allSatisfy { $0 == nil },
      "de dimanche à mercredi, les cases restent vides")
    #expect(layout.days[4] == 1, "une colonne de plus qu'en semaine commençant le lundi")
  }

  @Test("la pastille tombe sur le jour courant, et nulle part ailleurs")
  func todayIndexPointsAtToday() {
    let calendar = Self.calendar(firstWeekday: 2)
    let today = Self.date(2026, 10, 27, in: calendar)
    let layout = MonthGridLayout(date: today, calendar: calendar, today: today)

    let index = try? #require(layout.todayIndex)
    #expect(layout.days[index ?? 0] == 27, "la case marquée devrait porter le 27")
  }

  @Test("aucune pastille quand la grille montre un autre mois que celui du jour")
  func noTodayIndexForAnotherMonth() {
    let calendar = Self.calendar(firstWeekday: 2)
    let layout = MonthGridLayout(
      date: Self.date(2026, 7, 15, in: calendar),
      calendar: calendar,
      today: Self.date(2026, 10, 27, in: calendar)
    )

    #expect(layout.todayIndex == nil)
  }

  @Test("la grille fait toujours six semaines de sept cases, quel que soit le mois")
  func gridIsAlwaysSixRowsOfSeven() {
    let calendar = Self.calendar(firstWeekday: 2)

    // Février 2027 commence un lundi et tient en quatre lignes ; août 2026 commence un samedi
    // et en demande six. Les deux doivent produire la même grille.
    for (month, day) in [(2, 1), (8, 1), (10, 1)] {
      let layout = MonthGridLayout(
        date: Self.date(2027, month, day, in: calendar),
        calendar: calendar,
        today: Self.date(2026, 10, 27, in: calendar)
      )

      #expect(
        layout.days.count == MonthGridLayout.columnCount * MonthGridLayout.weekRowCount,
        "le mois \(month) ne fait pas 42 cases"
      )
      #expect(layout.weekdayInitials.count == 7, "il manque des initiales au mois \(month)")
    }
  }

  @Test("toutes les journées du mois sont présentes, une seule fois chacune")
  func everyDayOfMonthAppearsExactlyOnce() {
    let calendar = Self.calendar(firstWeekday: 2)
    let layout = MonthGridLayout(
      date: Self.date(2026, 10, 1, in: calendar),
      calendar: calendar,
      today: Self.date(2026, 10, 27, in: calendar)
    )

    #expect(
      layout.days.compactMap(\.self) == Array(1...31),
      "octobre devrait s'étendre du 1 au 31, dans l'ordre")
  }
}
