import Foundation

/// Décide quand le parcours d'accueil s'affiche et tient le drapeau `hasSeenOnboarding` : au
/// premier lancement, ou à la demande depuis About (`replay`). Le drapeau est posé dès que le
/// parcours s'affiche, pas à sa fin, pour qu'un relancement en cours de route ne le rejoue pas.
@MainActor
final class WelcomeLauncher {

  private let storage: SettingsStorage
  private let present: (OnboardingStep) -> Void

  init(storage: SettingsStorage = .shared, present: @escaping (OnboardingStep) -> Void) {
    self.storage = storage
    self.present = present
  }

  /// Lancement de l'app : affiche le parcours s'il n'a pas été vu, ou si on le force.
  func launchIfNeeded(forced: Bool, start: OnboardingStep = .hello) {
    guard
      WelcomeController.shouldShow(
        hasSeenOnboarding: storage.settings.hasSeenOnboarding, forced: forced)
    else { return }
    show(at: start)
  }

  /// Rejoue le parcours : efface le drapeau, puis le déroule comme au premier lancement.
  func replay() {
    storage.settings.hasSeenOnboarding = false
    launchIfNeeded(forced: false)
  }

  private func show(at step: OnboardingStep) {
    storage.settings.hasSeenOnboarding = true
    present(step)
  }
}
