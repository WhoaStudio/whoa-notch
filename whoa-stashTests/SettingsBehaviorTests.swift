import AppKit
import Foundation
import Testing

@testable import whoa_stash

/// Les réglages qui pilotent une vraie transformation : chacun est vérifié sur l'objet qu'il
/// est censé changer, et non sur la valeur qu'on vient d'écrire. C'est ce qui distingue un
/// réglage réel d'un interrupteur décoratif.
@MainActor
struct SettingsBehaviorTests {

  /// L'app n'a qu'une apparence, mais les couleurs dynamiques (`AccentColor.system`) ne se
  /// résolvent que dans une apparence de dessin posée explicitement : d'où cette constante.
  private static let dark = NSAppearance(named: .darkAqua)!

  // MARK: - Couleur d'accent

  @Test("l'accent remplace la teinte des graduations actives")
  func accentReplacesActiveTick() {
    let base = OverlayPalette.base
    let accented = base.accented(with: .purple, in: Self.dark)

    #expect(accented.activeTickColor != base.activeTickColor)
    #expect(accented.activeTickColor == AccentColor.purple.cgColor(for: Self.dark))
    // Le reste de la palette ne bouge pas : l'accent ne touche que la teinte « active ».
    #expect(accented.panelBackground == base.panelBackground)
    #expect(accented.strokeColor == base.strokeColor)
  }

  @Test("l'accent par défaut est le vert historique de l'app")
  func defaultAccentIsTheSignatureGreen() {
    #expect(GeneralSettings().accentColor == .green)
    #expect(AccentColor.green.cgColor(for: Self.dark) == OverlayPalette.activeGreen)
    // Donc la palette par défaut rend exactement ce qu'elle rendait avant le réglage.
    let accented = OverlayPalette.base.accented(with: .green, in: Self.dark)
    #expect(accented.activeTickColor == OverlayPalette.activeGreen)
  }

  @Test("chaque accent donne une couleur")
  func everyAccentResolves() {
    for accent in AccentColor.allCases {
      let resolved = accent.cgColor(for: Self.dark)
      #expect(resolved.alpha > 0, "\(accent.displayName) n'a rien rendu")
    }
  }

  // MARK: - Translucidité

  @Test("la translucidité n'abaisse que l'alpha du fond des panneaux")
  func opacityFadesOnlyThePanelBackground() throws {
    let base = OverlayPalette.base
    let faded = base.fadingPanel(to: 0.5)

    #expect(faded.panelBackground.alpha == 0.5)
    #expect(base.panelBackground.alpha == 1)
    // Le filet garde le sien : sans lui la silhouette se dissoudrait.
    #expect(faded.strokeColor.alpha == base.strokeColor.alpha)
  }

  @Test("à 100 % la palette est inchangée, et l'alpha ne descend jamais sous le plancher")
  func opacityIsClamped() {
    let base = OverlayPalette.base

    #expect(base.fadingPanel(to: 1).panelBackground == base.panelBackground)
    #expect(base.fadingPanel(to: 0).panelBackground.alpha == 0.2)
    #expect(base.fadingPanel(to: -5).panelBackground.alpha == 0.2)
  }

  // MARK: - Taille du widget

  @Test("chaque taille de widget donne une hauteur distincte et croissante")
  func widgetSizesAreDistinctAndOrdered() {
    let heights = WidgetSize.allCases.map(\.panelHeight)
    #expect(heights == heights.sorted())
    #expect(Set(heights).count == WidgetSize.allCases.count)
    // `.medium` est la hauteur d'avant le réglage : la valeur par défaut ne déplace rien.
    #expect(WidgetSize.medium.panelHeight == PanelGeometry.minimumPanelHeight)
    #expect(BrightnessSettings().widgetSize == .medium)
  }

  @Test("la hauteur choisie arrive dans le cadre de la bande")
  func widgetHeightReachesThePanelFrame() throws {
    let screen = try #require(NSScreen.main)
    let small = PanelGeometry.panelFrame(
      on: screen, anchoredTo: .left, height: WidgetSize.small.panelHeight)
    let large = PanelGeometry.panelFrame(
      on: screen, anchoredTo: .left, height: WidgetSize.large.panelHeight)

    #expect(small.height == WidgetSize.small.panelHeight)
    #expect(large.height == WidgetSize.large.panelHeight)
    // Les deux restent centrées sur le même milieu de bord : seule la hauteur change.
    #expect(small.midY == large.midY)
    // Et c'est bien là que la zone sensible va les chercher.
    #expect(PanelGeometry.hotZone(on: screen, anchoredTo: .left).midY == small.midY)
  }

  // MARK: - Raccourci global

  @Test("seul le raccourci désactivé n'a rien à enregistrer")
  func onlyDisabledHasNoKeyCode() {
    #expect(GlobalShortcut.disabled.keyCode == nil)
    #expect(GlobalShortcut.disabled.carbonModifiers == 0)

    for shortcut in GlobalShortcut.allCases where shortcut != .disabled {
      #expect(shortcut.keyCode != nil, "\(shortcut.rawValue) n'a pas de touche")
      #expect(shortcut.carbonModifiers != 0, "\(shortcut.rawValue) n'a pas de modificateur")
    }
  }

  @Test("aucune combinaison n'est proposée deux fois")
  func shortcutsAreUnique() {
    let combos = GlobalShortcut.allCases
      .compactMap { shortcut in shortcut.keyCode.map { ($0, shortcut.carbonModifiers) } }
    #expect(Set(combos.map { "\($0.0)-\($0.1)" }).count == combos.count)
  }

  // MARK: - Remise à zéro

  @Test("la remise à zéro ramène chaque réglage à sa valeur d'origine, et la persiste")
  func resetRestoresAndPersistsDefaults() {
    let suite = "whoa-stash.tests.reset"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let storage = SettingsStorage(defaults: defaults)
    storage.settings.general.accentColor = .pink
    storage.settings.general.panelOpacity = 0.5
    storage.settings.general.togglePanelShortcut = .optionCommandN
    storage.settings.brightness.widgetSize = .large
    #expect(storage.settings != .default)

    storage.resetToDefaults()
    #expect(storage.settings == .default)

    // Et le retour aux valeurs d'origine survit lui aussi au relancement.
    #expect(SettingsStorage(defaults: defaults).settings == .default)
  }
}
