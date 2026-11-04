import Foundation

/// Calcule les mesures de la section Activity à partir des requêtes lues. Pur : le calendrier et
/// l'horloge sont des paramètres, pour que les tests fixent le jour.
nonisolated enum ActivityAggregator {

    /// Le mois civil `offset` mois avant celui de `now`.
    static func month(offset: Int, now: Date, calendar: Calendar) -> DateInterval {
        let current = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        guard offset != 0,
              let shifted = calendar.date(byAdding: .month, value: -offset, to: current.start),
              let interval = calendar.dateInterval(of: .month, for: shifted)
        else { return current }
        return interval
    }

    /// Les requêtes du mois choisi, avant les filtres d'agent, de modèle et de projet.
    private static func inMonth(_ records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar) -> [ActivityRecord] {
        let interval = month(offset: filter.monthOffset, now: now, calendar: calendar)
        return records.filter { interval.contains($0.date) }
    }

    /// Menus de filtre : modèles et projets du mois, les plus utilisés d'abord.
    static func options(records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar) -> ActivityOptions {
        let scoped = inMonth(records, filter: filter, now: now, calendar: calendar)
            .filter { filter.agent == nil || $0.agent == filter.agent }

        func ranked(_ keyPath: KeyPath<ActivityRecord, String>) -> [String] {
            var weight: [String: Int] = [:]
            for record in scoped { weight[record[keyPath: keyPath], default: 0] += record.tokens.work }
            return weight.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        }
        return ActivityOptions(models: ranked(\.model), projects: Array(ranked(\.project).prefix(20)))
    }

    static func summarize(records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar) -> ActivitySummary {
        let interval = month(offset: filter.monthOffset, now: now, calendar: calendar)
        let daysInPeriod = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0

        let scoped = inMonth(records, filter: filter, now: now, calendar: calendar).filter {
            (filter.agent == nil || $0.agent == filter.agent)
                && (filter.model == nil || $0.model == filter.model)
                && (filter.project == nil || $0.project == filter.project)
        }

        var tokens = 0
        var cost = 0.0
        var hasPricedRecord = false
        var days: Set<Date> = []
        for record in scoped {
            tokens += record.tokens.work
            days.insert(calendar.startOfDay(for: record.date))
            if let pricing = ModelPricing.pricing(for: record.model) {
                cost += pricing.cost(of: record.tokens)
                hasPricedRecord = true
            }
        }

        let total: Double? = hasPricedRecord ? cost : (scoped.isEmpty ? 0 : nil)
        return ActivitySummary(
            tokens: tokens,
            cost: total,
            forecast: total.map { forecast(of: $0, interval: interval, now: now) },
            activeDays: days.count,
            daysInPeriod: daysInPeriod
        )
    }

    /// Les `limit` modèles les plus utilisés du mois choisi, par jetons décroissants (le nom
    /// départage les égalités).
    static func breakdown(
        records: [ActivityRecord], filter: ActivityFilter, now: Date, calendar: Calendar, limit: Int
    ) -> [ActivityBreakdownRow] {
        var tokens: [String: Int] = [:]
        var cost: [String: Double] = [:]
        for record in inMonth(records, filter: filter, now: now, calendar: calendar)
        where filter.agent == nil || record.agent == filter.agent {
            tokens[record.model, default: 0] += record.tokens.work
            if let pricing = ModelPricing.pricing(for: record.model) {
                cost[record.model, default: 0] += pricing.cost(of: record.tokens)
            }
        }
        return tokens
            .map { ActivityBreakdownRow(model: $0.key, tokens: $0.value, cost: cost[$0.key]) }
            .sorted { ($0.tokens, $1.model) > ($1.tokens, $0.model) }
            .prefix(limit)
            .map { $0 }
    }

    /// Coût du mois projeté au rythme observé. Un mois fini vaut son coût ; la première journée
    /// compte pour un jour entier, sans quoi quelques heures d'activité s'extrapoleraient à
    /// l'infini.
    private static func forecast(of cost: Double, interval: DateInterval, now: Date) -> Double {
        guard interval.contains(now) else { return cost }
        let elapsedDays = max(1, now.timeIntervalSince(interval.start) / 86_400)
        return cost / elapsedDays * (interval.duration / 86_400)
    }
}
