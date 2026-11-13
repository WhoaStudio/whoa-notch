import Foundation

/// Relie la source d'éveil à l'interface et tient le compte à rebours. Ne tient aucun
/// contrôleur : c'est `AppDelegate` qui branche `onStateChanged`.
@MainActor
final class StayAwakeViewModel {

  var onStateChanged: ((StayAwakeState) -> Void)?
  /// Appelé quand le minuteur arrive à son terme (pas sur un « Turn Off »).
  var onExpired: (() -> Void)?

  /// Bornes du réglage à la main : une minute au moins, douze heures au plus.
  static let minimumRemaining: TimeInterval = 60
  static let maximumRemaining: TimeInterval = 12 * 3600

  private(set) var state = StayAwakeState()

  private let provider: any StayAwakeProviding
  private let now: () -> Date
  private var deadline: Date?
  private var timer: Timer?

  init(provider: any StayAwakeProviding, now: @escaping () -> Date = Date.init) {
    self.provider = provider
    self.now = now
  }

  func activate() {
    onStateChanged?(state)
  }

  func handle(_ action: StayAwakeAction) {
    switch action {
    case .start(let duration): start(duration)
    case .setScope(let scope): setScope(scope)
    case .adjust(let delta): adjust(by: delta)
    case .turnOff: turnOff()
    }
  }

  /// Démarre, ou relance avec une nouvelle durée si c'est déjà actif.
  func start(_ duration: StayAwakeDuration) {
    guard state.isActive || provider.hold(state.scope) else { return }
    state.duration = duration
    deadline = duration.seconds.map { now().addingTimeInterval($0) }
    state.remaining = duration.seconds
    state.total = duration.seconds
    state.isAdjusted = false
    scheduleTimer()
    onStateChanged?(state)
  }

  /// Déplace l'échéance de `delta` secondes, bornée à [1 min, 12 h]. Ne touche pas à la prise.
  func adjust(by delta: TimeInterval) {
    guard let deadline, state.isActive else { return }
    let current = deadline.timeIntervalSince(now())
    let target = min(Self.maximumRemaining, max(Self.minimumRemaining, current + delta))
    guard target != current else { return }
    self.deadline = deadline.addingTimeInterval(target - current)
    state.remaining = target
    state.total = max(state.total ?? target, target)
    state.isAdjusted = true
    onStateChanged?(state)
  }

  /// Change ce qui reste éveillé. Actif, la prise est refaite sur-le-champ ; inactif, le choix
  /// est seulement retenu pour le prochain démarrage.
  func setScope(_ scope: StayAwakeScope) {
    guard scope != state.scope else { return }
    state.scope = scope
    if state.isActive, !provider.hold(scope) {
      turnOff()
      return
    }
    onStateChanged?(state)
  }

  /// Relâche la prise : fin du minuteur, « Turn Off », ou fermeture de l'app.
  func turnOff() {
    timer?.invalidate()
    timer = nil
    deadline = nil
    provider.release()
    guard state.isActive else { return }
    state.duration = nil
    state.remaining = nil
    state.total = nil
    state.isAdjusted = false
    onStateChanged?(state)
  }

  /// Un battement du compte à rebours. Public pour que les tests le jouent sans attendre.
  func tick() {
    guard let deadline else { return }
    let remaining = deadline.timeIntervalSince(now())
    if remaining <= 0 {
      turnOff()
      onExpired?()
    } else {
      state.remaining = remaining
      onStateChanged?(state)
    }
  }

  /// Sans échéance (`forever`), il n'y a rien à compter : pas de minuteur.
  private func scheduleTimer() {
    timer?.invalidate()
    timer = nil
    guard deadline != nil else { return }
    // Mode `.common` : le compte continue de tourner pendant un suivi de souris.
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }
}
