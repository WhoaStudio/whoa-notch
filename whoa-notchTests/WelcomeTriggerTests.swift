import Foundation
import Testing

@testable import whoa_notch

/// Décision d'afficher l'écran de bienvenue : une seule fois, sauf si on le force.
@MainActor
struct WelcomeTriggerTests {

  @Test("premier lancement : l'accueil s'affiche")
  func showsOnFirstLaunch() {
    #expect(WelcomeController.shouldShow(hasSeenOnboarding: false, forced: false))
  }

  @Test("accueil déjà vu : il ne se rejoue pas au lancement")
  func skipsOnceSeen() {
    #expect(!WelcomeController.shouldShow(hasSeenOnboarding: true, forced: false))
  }

  @Test("--show-welcome le rejoue même s'il a été vu")
  func forcedReplays() {
    #expect(WelcomeController.shouldShow(hasSeenOnboarding: true, forced: true))
  }
}

/// Rejouer le parcours depuis About : le drapeau est effacé puis reposé, le parcours s'ouvre aussitôt.
@MainActor
struct WelcomeReplayTests {

  private static func makeStorage() -> SettingsStorage {
    let name = "whoa-notch.tests.replay.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return SettingsStorage(defaults: defaults)
  }

  @Test("rejouer efface le drapeau « vu » et ouvre le parcours à la première étape")
  func replayShowsTourFromStart() {
    let storage = Self.makeStorage()
    storage.settings.hasSeenOnboarding = true
    var shown: [OnboardingStep] = []
    let launcher = WelcomeLauncher(storage: storage) { shown.append($0) }

    launcher.replay()

    #expect(shown == [.hello])
    #expect(storage.settings.hasSeenOnboarding)
  }

  @Test("le premier lancement et un second lancement : le parcours ne se rejoue pas seul")
  func launchOnlyOnce() {
    let storage = Self.makeStorage()
    var count = 0
    let launcher = WelcomeLauncher(storage: storage) { _ in count += 1 }

    launcher.launchIfNeeded(forced: false)
    launcher.launchIfNeeded(forced: false)

    #expect(count == 1)
  }

  @Test("on peut rejouer plusieurs fois, et le parcours terminé laisse le drapeau posé")
  func replayRepeatedly() {
    let storage = Self.makeStorage()
    var count = 0
    let launcher = WelcomeLauncher(storage: storage) { _ in count += 1 }

    launcher.launchIfNeeded(forced: false)
    launcher.replay()
    launcher.replay()

    #expect(count == 3)
    #expect(storage.settings.hasSeenOnboarding)
  }
}
