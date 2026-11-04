import Foundation

/// Les agents dont l'activité est lue dans les journaux locaux.
nonisolated enum ActivityAgent: String, CaseIterable, Sendable {
    case claudeCode
    case codex

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// Jetons d'une requête, ventilés comme le facturent les API : l'écriture en cache coûte plus
/// cher que l'entrée, et plus encore avec la durée de vie d'une heure.
nonisolated struct TokenCounts: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0

    /// Ce que montre la mesure « Tokens » : le travail réellement fourni — entrée et sortie. Les
    /// relectures du cache se comptent par centaines de millions et noieraient le chiffre ; elles
    /// restent comptées dans le coût.
    var work: Int { input + output }
}

/// Une requête d'un agent, réduite à ce que les mesures et les filtres utilisent.
nonisolated struct ActivityRecord: Equatable, Sendable {
    /// Identifie la requête d'un journal à l'autre : une session reprise recopie son historique.
    let key: String
    let date: Date
    let agent: ActivityAgent
    let model: String
    let project: String
    let tokens: TokenCounts
}

/// Les filtres de la section Activity. Aucun n'est mémorisé d'un lancement à l'autre.
nonisolated struct ActivityFilter: Equatable, Sendable {
    /// 0 : le mois en cours ; 1 : le précédent…
    var monthOffset = 0
    var agent: ActivityAgent?
    var model: String?
    var project: String?
}

nonisolated struct ActivitySummary: Equatable, Sendable {
    let tokens: Int
    /// `nil` quand aucun modèle de la période n'a de tarif connu.
    let cost: Double?
    /// Coût projeté à la fin du mois ; un mois passé vaut son coût final.
    let forecast: Double?
    let activeDays: Int
    let daysInPeriod: Int

    static let empty = ActivitySummary(tokens: 0, cost: nil, forecast: nil, activeDays: 0, daysInPeriod: 0)
}

/// Une ligne de l'onglet Analytics : ce qu'un modèle a consommé sur la période.
nonisolated struct ActivityBreakdownRow: Equatable, Sendable {
    let model: String
    let tokens: Int
    /// `nil` quand le modèle n'a pas de tarif connu.
    let cost: Double?
}

/// Les valeurs proposées par les menus de filtre, tirées de la période affichée.
nonisolated struct ActivityOptions: Equatable, Sendable {
    let models: [String]
    let projects: [String]
}
