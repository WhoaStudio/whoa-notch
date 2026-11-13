import Foundation

/// Une fenêtre de quota Claude : la fraction déjà consommée et l'instant où elle se réinitialise.
struct ClaudeUsageWindow: Equatable, Sendable {

  /// Fraction consommée, toujours bornée à `0…1` — l'API peut renvoyer un léger dépassement
  /// quand la dernière requête a mordu sur la limite, et le ruban de la bague ne doit pas
  /// repartir pour un second tour.
  let utilization: Double
  let resetsAt: Date

  init(utilization: Double, resetsAt: Date) {
    self.utilization = min(1, max(0, utilization))
    self.resetsAt = resetsAt
  }

  /// Entier affiché à côté de la bague et dans le panneau — arrondi une seule fois, ici, pour
  /// que les deux surfaces ne puissent pas afficher 72 % et 73 % du même instantané.
  var percentage: Int { Int((utilization * 100).rounded()) }
}

/// Les deux fenêtres montrées par le widget : la session glissante de 5 h, et le quota
/// hebdomadaire tous modèles confondus.
struct ClaudeUsageSnapshot: Equatable, Sendable {
  let session: ClaudeUsageWindow
  let allModels: ClaudeUsageWindow
}

/// État complet de la vue, `snapshot` inclus : la bague et le panneau doivent savoir distinguer
/// « pas encore chargé » de « 0 % », et afficher un état neutre plutôt qu'une bague vide quand
/// Claude Code n'est pas connecté sur cette machine.
enum ClaudeUsageState: Equatable {
  case loading
  case loaded(ClaudeUsageSnapshot)
  case unavailable(reason: String)
  /// Le jeton du trousseau est périmé : seule une reconnexion dans Claude Code y remédie.
  case expired(reason: String)

  var snapshot: ClaudeUsageSnapshot? {
    if case .loaded(let snapshot) = self { return snapshot }
    return nil
  }
}
