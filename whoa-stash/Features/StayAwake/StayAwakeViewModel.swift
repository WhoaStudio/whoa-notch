import Foundation

/// Relie la source d'éveil à l'interface et tient le compte à rebours. Ne tient aucun
/// contrôleur : c'est `AppDelegate` qui branche `onStateChanged`.
@MainActor
final class StayAwakeViewModel {

  var onStateChanged: ((StayAwakeState) -> Void)?

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
    case .turnOff: turnOff()
    }
  }

  /// Démarre, ou relance avec une nouvelle durée si c'est déjà actif.
  func start(_ duration: StayAwakeDuration) {
    guard provider.hold(state.scope) else { return }
    state.duration = duration
    deadline = duration.seconds.map { now().addingTimeInterval($0) }
    state.remaining = duration.seconds
    scheduleTimer()
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
    onStateChanged?(state)
  }

  /// Un battement du compte à rebours. Public pour que les tests le jouent sans attendre.
  func tick() {
    guard let deadline else { return }
    let remaining = deadline.timeIntervalSince(now())
    if remaining <= 0 {
      turnOff()
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
