import Foundation

/// Calcule les mesures de la section Activity à partir des requêtes lues. Pur : le calendrier et
/// l'horloge sont des paramètres, pour que les tests fixent le jour.
nonisolated enum ActivityAggregator {

  /// Le mois civil `offset` mois avant celui de `now`.
  static func month(offset: Int, now: Date, calendar: Calendar) -> DateInterval {
    let current =
      calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
    guard offset != 0,
      let shifted = calendar.date(byAdding: .month, value: -offset, to: current.start),
      let interval = calendar.dateInterval(of: .month, for: shifted)
    else { return current }
    return interval
  }

  /// Les requêtes du mois choisi, avant les filtres d'agent, de modèle et de projet.
  private static func inMonth(
    _ records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar
  ) -> [ActivityRecord] {
    let interval = month(offset: filter.monthOffset, now: now, calendar: calendar)
    return records.filter { interval.contains($0.date) }
  }

  /// Menus de filtre : modèles et projets du mois, les plus utilisés d'abord.
  static func options(
    records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar
  ) -> ActivityOptions {
    let scoped = inMonth(records, filter: filter, now: now, calendar: calendar)
      .filter { filter.agent == nil || $0.agent == filter.agent }

    func ranked(_ keyPath: KeyPath<ActivityRecord, String>) -> [String] {
      var weight: [String: Int] = [:]
      for record in scoped { weight[record[keyPath: keyPath], default: 0] += record.tokens.work }
      return weight.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
    return ActivityOptions(models: ranked(\.model), projects: Array(ranked(\.project).prefix(20)))
  }

  static func summarize(
    records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar
  ) -> ActivitySummary {
    let interval = month(offset: filter.monthOffset, now: now, calendar: calendar)
    let daysInPeriod = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0

    let scoped = inMonth(records, filter: filter, now: now, calendar: calendar).filter {
      (filter.agent == nil || $0.agent == filter.agent)
        && (filter.model == nil || $0.model == filter.model)
        && (filter.project == nil || $0.project == filter.project)
    }

    var tokens = 0
    var days: Set<Date> = []
    for record in scoped {
      tokens += record.tokens.work
      days.insert(calendar.startOfDay(for: record.date))
    }
    return ActivitySummary(tokens: tokens, activeDays: days.count, daysInPeriod: daysInPeriod)
  }

  /// Les jetons du mois choisi, un point par jour calendaire (zéro les jours sans activité),
  /// avec les mêmes filtres que `summarize` : la somme de la courbe vaut `summary.tokens`.
  static func dailyTokens(
    records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar
  ) -> [ActivityDay] {
    let interval = month(offset: filter.monthOffset, now: now, calendar: calendar)
    let daysInPeriod = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0

    var perDay: [Date: Int] = [:]
    for record in inMonth(records, filter: filter, now: now, calendar: calendar)
    where (filter.agent == nil || record.agent == filter.agent)
      && (filter.model == nil || record.model == filter.model)
      && (filter.project == nil || record.project == filter.project)
    {
      perDay[calendar.startOfDay(for: record.date), default: 0] += record.tokens.work
    }
    return (0..<daysInPeriod).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: interval.start).map {
        ActivityDay(date: $0, tokens: perDay[$0] ?? 0)
      }
    }
  }

  /// Les `limit` modèles les plus utilisés du mois choisi, par jetons décroissants (le nom
  /// départage les égalités).
  static func breakdown(
    records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar, limit: Int
  ) -> [ActivityBreakdownRow] {
    var tokens: [String: Int] = [:]
    for record in inMonth(records, filter: filter, now: now, calendar: calendar)
    where filter.agent == nil || record.agent == filter.agent {
      tokens[record.model, default: 0] += record.tokens.work
    }
    return
      tokens
      .map { ActivityBreakdownRow(model: $0.key, tokens: $0.value) }
      .sorted { ($0.tokens, $1.model) > ($1.tokens, $0.model) }
      .prefix(limit)
      .map { $0 }
  }
}
