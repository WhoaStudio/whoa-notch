import AppKit
import OSLog

/// Menu contextuel partagé par tous les panneaux de l'overlay — la bande du bord droit, celle de
/// la luminosité et le panneau de l'encoche. Une seule définition pour les trois : c'est ce qui
/// garantit qu'un clic droit montre partout les deux mêmes entrées.
///
/// Les actions ne sont pas réimplémentées ici : « Open Settings » appelle le même
/// `SettingsWindowController.shared.show()` que l'engrenage de la capsule de navigation et que l'entrée
/// « Préférences… » de la menu bar, et « Quit Whoa Stash » appelle `NSApp.terminate(_:)`, comme
/// l'entrée homonyme du menu de la menu bar.
///
/// Le menu est posé sur la vue de contenu de chaque panneau (`NSView.menu`) plutôt que présenté
/// à la main : AppKit remonte la chaîne des responders depuis la vue cliquée jusqu'à la première
/// qui en porte un, donc un clic droit sur une bague ou sur un onglet le trouve aussi.
@MainActor
final class OverlayContextMenu: NSObject, NSMenuDelegate {

  static let shared = OverlayContextMenu()

  /// Vrai le temps que le menu soit ouvert. Les contrôleurs de panneaux y suspendent leur suivi
  /// du curseur : le pointeur qui descend dans le menu sort du cadre du panneau, et sans ça
  /// celui-ci se replierait sous le menu encore ouvert.
  private(set) var isPresenting = false

  let menu: NSMenu

  private override init() {
    menu = NSMenu()
    super.init()

    menu.delegate = self

    let settings = NSMenuItem(
      title: "Open Settings", action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit Whoa Stash", action: #selector(quit), keyEquivalent: "")
    quit.target = self
    menu.addItem(quit)
  }

  // MARK: - NSMenuDelegate

  func menuWillOpen(_ menu: NSMenu) {
    isPresenting = true
  }

  func menuDidClose(_ menu: NSMenu) {
    isPresenting = false
  }

  // MARK: - Actions

  @objc private func openSettings() {
    Log.settings.debug(
      "ouverture de la fenêtre de Préférences depuis le menu contextuel d'un panneau")
    SettingsWindowController.shared.show()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
