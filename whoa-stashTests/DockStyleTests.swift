import Foundation
import Testing

@testable import whoa_stash

/// Réglages « Appearance » et « Screens » du dock : calcul d'ajustement et décodage tolérant.
@MainActor
@Suite("Réglages d'apparence du dock")
struct DockStyleTests {

  @Test("Une rangée qui tient garde la taille de base")
  func fitKeepsBaseWhenItFits() {
    let size = DockStyle.fittedIconSize(base: 48, count: 3, spacing: 8, available: 2000)
    #expect(size == 48)
  }

  @Test("Une rangée trop large réduit l'icône pour tenir dans la largeur disponible")
  func fitShrinksWhenTooWide() {
    let available: CGFloat = 800
    let size = DockStyle.fittedIconSize(base: 96, count: 20, spacing: 8, available: available)
    #expect(size < 96)
    #expect(size * DockStyle.widthFactor(count: 20, spacing: 8) <= available + 0.001)
  }

  @Test("Sans icône ou sans place, la taille de base est rendue telle quelle")
  func fitIgnoresEmptyInputs() {
    #expect(DockStyle.fittedIconSize(base: 48, count: 0, spacing: 8, available: 100) == 48)
    #expect(DockStyle.fittedIconSize(base: 48, count: 5, spacing: 8, available: 0) == 48)
  }

  @Test("Le filtre d'écrans « one » ne garde que le premier écran permis")
  func policyOneKeepsFirst() {
    #expect(DockScreenPolicy.allowed([], mode: .one, detached: []).isEmpty)
  }

  @Test("Les nouveaux réglages se décodent avec leurs valeurs par défaut")
  func decodesDefaultsWhenMissing() throws {
    let decoded = try JSONDecoder().decode(DockSettings.self, from: Data("{}".utf8))
    #expect(decoded.screenMode == .attached)
    #expect(decoded.adaptsToFit)
    #expect(!decoded.monochromeWidgets)
    #expect(!decoded.reduceTransparency)
  }

  @Test("Le mode « All Displays » est reconnu au décodage")
  func decodesAllDisplays() throws {
    let decoded = try JSONDecoder().decode(
      DockSettings.self, from: Data(#"{"screenMode":"all"}"#.utf8))
    #expect(decoded.screenMode == .all)
  }
}
