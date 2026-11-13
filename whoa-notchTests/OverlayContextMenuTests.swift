import AppKit
import Testing

@testable import whoa_notch

/// Le menu contextuel des panneaux de l'overlay. Rien ici ne vérifie une valeur qu'on vient
/// d'écrire : ce sont les trois choses qui le feraient taire sans que la compilation bronche —
/// une action qui ne mène plus à personne, un menu qui n'est plus posé sur un panneau, et le
/// drapeau dont les contrôleurs se servent pour ne pas se replier sous un menu ouvert.
@MainActor
struct OverlayContextMenuTests {

  private static var menu: NSMenu { OverlayContextMenu.shared.menu }

  // MARK: - Contenu

  @Test("le menu porte exactement les deux entrées, séparateur au milieu")
  func menuHoldsExactlyTheTwoItems() {
    let items = Self.menu.items

    #expect(items.count == 3)
    #expect(items.first?.title == "Open Settings")
    #expect(items.last?.title == "Quit Whoa Notch")
    #expect(items[1].isSeparatorItem)
    // Les deux seules entrées cliquables : rien ne s'est ajouté en route.
    #expect(items.filter { !$0.isSeparatorItem }.count == 2)
  }

  // MARK: - Actions

  /// Une entrée dont la cible ne répond plus à l'action reste affichée, mais grisée et muette :
  /// c'est la panne qu'aucun compilateur ne signale, puisqu'un `Selector` n'est qu'un nom.
  @Test("chaque entrée mène à une action que sa cible implémente vraiment")
  func everyActionIsImplementedOnItsTarget() throws {
    for item in Self.menu.items where !item.isSeparatorItem {
      let target = try #require(item.target as? OverlayContextMenu)
      let action = try #require(item.action)

      #expect(target === OverlayContextMenu.shared)
      #expect(target.responds(to: action), "\(item.title) ne mène à personne")
    }
  }

  @Test("les deux entrées ne mènent pas à la même action")
  func theTwoItemsDoNotShareOneAction() {
    let actions = Self.menu.items.compactMap(\.action)
    #expect(actions.count == 2)
    #expect(actions[0] != actions[1])
  }

  /// `SettingsWindowController.rerouteSettingsMenuItem()` parcourt le menu de l'app et
  /// rebranche sur lui tout ce qui porte ⌘,. Il ne touche pas à ce menu-ci, qui n'est pas dans
  /// `NSApp.mainMenu` — mais une entrée à qui on donnerait ⌘, le deviendrait au premier
  /// déplacement, et « Quit Whoa Notch » prendrait le chemin des Préférences.
  @Test("aucune entrée ne porte de raccourci que le menu de l'app irait rebrancher")
  func noItemCarriesAKeyEquivalent() {
    for item in Self.menu.items where !item.isSeparatorItem {
      #expect(item.keyEquivalent.isEmpty, "\(item.title) porte un raccourci")
    }
  }

  // MARK: - Gel du suivi du curseur

  /// Les trois contrôleurs de panneaux lisent ce drapeau pour suspendre leur suivi : s'il ne
  /// se levait plus, le panneau se replierait sous le menu encore ouvert.
  @Test("le drapeau suit l'ouverture et la fermeture du menu")
  func presentingFlagFollowsTheMenu() {
    let overlay = OverlayContextMenu.shared
    #expect(overlay.isPresenting == false)

    overlay.menuWillOpen(overlay.menu)
    #expect(overlay.isPresenting)

    overlay.menuDidClose(overlay.menu)
    #expect(overlay.isPresenting == false)
  }

  // MARK: - Pose sur les panneaux

  /// La vraie dépendance du clic droit : AppKit ne remonte la chaîne des responders que
  /// jusqu'à une vue qui porte un menu. Une vue de contenu qui cesserait de le poser ne
  /// montrerait plus rien, sans que rien d'autre ne change.
  @Test("les trois panneaux de l'overlay portent le même menu")
  func everyPanelCarriesTheSharedMenu() {
    let palette = OverlayPalette.base

    let views: [(String, NSView)] = [
      ("bande de flanc", SidePanelContentView()),
      ("panneau de l'encoche", NotchPanelContentView()),
      (
        "widget de luminosité",
        BrightnessView(tickCount: BrightnessViewModel.tickCount, initialPalette: palette)
      ),
    ]

    for (name, view) in views {
      #expect(view.menu === OverlayContextMenu.shared.menu, "\(name) ne porte pas le menu partagé")
    }
  }
}
