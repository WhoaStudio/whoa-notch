import Testing

@testable import whoa_stash

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
