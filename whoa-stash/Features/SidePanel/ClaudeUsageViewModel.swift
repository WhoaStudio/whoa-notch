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

  /// Le quota ne bouge qu'au rythme des requêtes faites dans Claude Code : une minute suffit
  /// largement, et évite de marteler un point d'entrée non documenté.
  private let refreshInterval: TimeInterval = 60
  /// Le texte « Resets in 51 min » est recalculé localement à partir de `resetsAt`, sans
  /// réseau — le compte à rebours reste juste entre deux rafraîchissements.
  private let countdownInterval: TimeInterval = 30

  private var refreshTimer: Timer?
  private var countdownTimer: Timer?
  private var wakeObserver: NSObjectProtocol?
  private var inFlight: Task<Void, Never>?

  init(provider: ClaudeUsageProviding) {
    self.provider = provider
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

  /// Rafraîchissement immédiat — appelé à l'activation, par les timers, et à chaque ouverture
  /// du panneau latéral pour que la première image montrée soit à jour.
  func refresh() {
    guard inFlight == nil else { return }

    inFlight = Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await provider.fetchSnapshot()
        self.state = .loaded(snapshot)
      } catch {
        if case ClaudeUsageCredentialError.expired = error {
          // Un jeton périmé ne se réparera pas tout seul : on le dit, même par-dessus un
          // instantané devenu trop vieux pour être fiable.
          self.state = .expired(reason: error.localizedDescription)
        } else if self.state.snapshot == nil {
          // Un échec ponctuel ne doit pas effacer un instantané déjà affiché : la bague
          // garde sa dernière valeur connue et ne clignote pas à chaque coupure réseau.
          self.state = .unavailable(reason: error.localizedDescription)
        }
        Log.sidePanel.error(
          "rafraîchissement de l'utilisation Claude échoué — \(error.localizedDescription, privacy: .public)"
        )
      }
      self.inFlight = nil
    }
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
