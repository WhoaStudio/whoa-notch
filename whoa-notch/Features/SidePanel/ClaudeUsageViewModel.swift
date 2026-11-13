import AppKit
import OSLog

/// Expose l'état d'utilisation Claude aux vues AppKit avec un simple callback — pas de Combine
/// côté vue.
///
/// Une seule instance alimente la bande latérale et la bulle de détail : c'est ce qui garantit
/// qu'elles montrent le même instantané, et qu'un seul appel réseau les sert toutes les deux.
@MainActor
final class ClaudeUsageViewModel {

  private(set) var state: ClaudeUsageState = .loading {
    didSet {
      guard state != oldValue else { return }
      onStateChanged?()
    }
  }

  var onStateChanged: (() -> Void)?

  private let provider: ClaudeUsageProviding

  /// Le quota ne bouge qu'au rythme des requêtes faites dans Claude Code : cinq minutes
  /// suffisent, et le jeton OAuth est partagé avec Claude Code — un sondage plus serré
  /// déclenche des 429 sur un point d'entrée non documenté.
  private let refreshInterval: TimeInterval = 300
  /// Le texte « Resets in 51 min » est recalculé localement à partir de `resetsAt`, sans
  /// réseau — le compte à rebours reste juste entre deux rafraîchissements.
  private let countdownInterval: TimeInterval = 30

  private var refreshTimer: Timer?
  private var countdownTimer: Timer?
  private var wakeObserver: NSObjectProtocol?
  private var inFlight: Task<Void, Never>?

  /// Après un 429, aucun appel avant cette date : le point d'entrée n'est pas sollicité tant que
  /// le serveur demande d'attendre.
  private var retryNotBefore: Date?
  /// Nombre de 429 de suite, pour allonger l'attente quand le serveur ne dit pas combien.
  private var consecutiveRateLimits = 0
  private let now: @MainActor () -> Date

  init(provider: ClaudeUsageProviding, now: @escaping @MainActor () -> Date = { Date() }) {
    self.provider = provider
    self.now = now
  }

  func activate() {
    refresh()

    // Timers construits sur place plutôt que via un helper prenant une closure : le même
    // motif que `SidePanelController`, et le seul qui traverse proprement la frontière
    // d'isolation (le bloc d'un `Timer` est `@Sendable`, le modèle de vue est `@MainActor`).
    refreshTimer = schedule(interval: refreshInterval) { [weak self] in
      self?.refresh()
    }
    countdownTimer = schedule(interval: countdownInterval) { [weak self] in
      // Rien à recharger : seul le texte dérivé de `resetsAt` vieillit.
      self?.onStateChanged?()
    }

    // Au réveil, les timers ont sauté toute la durée du sommeil et `resetsAt` est
    // probablement dépassé : on repart d'un instantané frais plutôt que d'attendre la
    // prochaine minute.
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  /// Rafraîchissement — appelé à l'activation, par le timer, au réveil et par le bouton
  /// d'actualisation de l'onglet Analytics. Tous passent par ici : pendant une attente imposée
  /// par un 429, aucun ne touche au réseau.
  func refresh() {
    guard inFlight == nil else { return }
    if let retryNotBefore, now() < retryNotBefore { return }

    inFlight = Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await provider.fetchSnapshot()
        self.retryNotBefore = nil
        self.consecutiveRateLimits = 0
        self.state = .loaded(snapshot)
      } catch {
        var reason = error.localizedDescription
        if case ClaudeUsageServiceError.rateLimited(let retryAfter) = error {
          self.consecutiveRateLimits += 1
          let retryAt = self.now().addingTimeInterval(
            Self.rateLimitDelay(retryAfter: retryAfter, attempt: self.consecutiveRateLimits))
          self.retryNotBefore = retryAt
          reason += " — nouvel essai à \(retryAt.formatted(date: .omitted, time: .shortened))"
        }
        if case ClaudeUsageCredentialError.expired = error {
          // Un jeton périmé ne se réparera pas tout seul : on le dit, même par-dessus un
          // instantané devenu trop vieux pour être fiable.
          self.state = .expired(reason: error.localizedDescription)
        } else if self.state.snapshot == nil {
          // Un échec ponctuel ne doit pas effacer un instantané déjà affiché : la bague
          // garde sa dernière valeur connue et ne clignote pas à chaque coupure réseau.
          self.state = .unavailable(reason: reason)
        }
        Log.sidePanel.error(
          "rafraîchissement de l'utilisation Claude échoué — \(reason, privacy: .public)"
        )
      }
      self.inFlight = nil
    }
  }

  /// Un `Retry-After` du serveur est respecté tel quel (au moins une minute). Sans lui, l'attente
  /// double à chaque 429 de suite : 5, 10, 20, 40 puis 60 min au plus.
  nonisolated static func rateLimitDelay(retryAfter: TimeInterval?, attempt: Int) -> TimeInterval {
    if let retryAfter { return max(60, retryAfter) }
    return min(3600, 300 * pow(2, Double(max(0, attempt - 1))))
  }

  private func schedule(interval: TimeInterval, tick: @escaping @Sendable @MainActor () -> Void)
    -> Timer
  {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in
      Task { @MainActor in tick() }
    }
    // `.common` : sans ça, les timers gèlent pendant qu'un menu ou un suivi de souris tourne.
    RunLoop.main.add(timer, forMode: .common)
    return timer
  }
}
