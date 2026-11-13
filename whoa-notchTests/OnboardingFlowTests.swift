import CoreGraphics
import Testing

@testable import whoa_notch

@MainActor
@Suite("Parcours d'accueil")
struct OnboardingFlowTests {

  @Test("les étapes ne bouclent pas aux bords")
  func bords() {
    #expect(OnboardingStep.hello.moved(by: -1) == nil)
    #expect(OnboardingStep.done.moved(by: 1) == nil)
    #expect(OnboardingStep.hello.moved(by: 1) == .notch)
    #expect(OnboardingStep.done.moved(by: -1) == .permissions)
  }

  @Test("le nom de lancement retrouve l'étape")
  func nomDeLancement() {
    for step in OnboardingStep.allCases {
      #expect(OnboardingStep(launchName: step.launchName) == step)
    }
    #expect(OnboardingStep(launchName: "inconnue") == nil)
  }

  @Test("la fenêtre est au moins aussi haute que chaque étape")
  func hauteurMaximale() {
    let inset: CGFloat = 44
    let maximum = OnboardingFlow.maxPanelHeight(topInset: inset)
    for step in OnboardingStep.allCases {
      #expect(OnboardingFlow.panelHeight(for: step, topInset: inset) <= maximum)
    }
  }

  @Test("le balayage résiste au bord et suit le doigt ailleurs")
  func resistance() {
    #expect(OnboardingFlow.trackedOffset(40, at: .hello) == 10)
    #expect(OnboardingFlow.trackedOffset(-40, at: .done) == -10)
    #expect(OnboardingFlow.trackedOffset(-40, at: .hello) == -40)
    #expect(OnboardingFlow.trackedOffset(40, at: .tabs) == 40)
  }
}
