import CoreGraphics
import Foundation
import Testing

@testable import whoa_stash

/// Le relâché du balayage de la grille du mois : la vitesse lue au lâcher et la page où elle
/// mène.
@MainActor @Suite struct MonthGridGestureTests {

  private let width: CGFloat = 196

  @Test("un doigt immobile avant de lâcher rend une vitesse nulle, même après un geste rapide")
  func pauseBeforeReleaseKillsVelocity() {
    let samples: [(time: TimeInterval, offset: CGFloat)] = [(1.00, -10), (1.05, -60), (1.10, -110)]

    #expect(
      MonthGridView.releaseVelocity(samples: samples, at: 1.12) < -900,
      "un lâcher juste après le geste devrait garder sa vitesse")
    #expect(
      MonthGridView.releaseVelocity(samples: samples, at: 1.60) == 0,
      "après une pause d'une demi-seconde, plus rien ne devrait lancer la page")
  }

  @Test("un coup sec court tourne la page, un glisser lent et court la ramène")
  func projectionDecidesThePage() {
    #expect(
      MonthGridView.settlePage(offset: -40, velocity: -1200, width: width) == -1,
      "un coup sec vers la gauche devrait mener au mois suivant")
    #expect(
      MonthGridView.settlePage(offset: -40, velocity: -50, width: width) == 0,
      "un glisser lent et court devrait revenir au mois affiché")
    #expect(
      MonthGridView.settlePage(offset: 120, velocity: 0, width: width) == 1,
      "lâché au-delà de la moitié vers la droite, c'est le mois précédent")
  }

  @Test("un geste ne tourne jamais plus d'une page, si fort soit-il")
  func neverMoreThanOnePage() {
    #expect(MonthGridView.settlePage(offset: -180, velocity: -9000, width: width) == -1)
    #expect(MonthGridView.settlePage(offset: 180, velocity: 9000, width: width) == 1)
  }
}
