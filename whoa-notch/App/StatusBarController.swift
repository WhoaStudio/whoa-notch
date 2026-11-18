import AppKit
import OSLog

/// Gère l'icône dans la menu bar macOS (NSStatusItem) et son menu déroulant.
@MainActor
final class StatusBarController: NSObject {

  private let statusItem: NSStatusItem
  private var profiles: [DockProfile] = []
  private var activeProfileID: String?
  /// Appelé avec l'identifiant du profil choisi dans le menu.
  var onSelectProfile: ((String) -> Void)?

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    super.init()

    if let button = statusItem.button {
      // Glyphe monochrome tiré du logo (tuile, encoche, yeux, moustache) : l'icône
      // d'application complète devient illisible à 18 pt. En image modèle, AppKit
      // fournit les couleurs des barres claire, sombre et surlignée.
      let icon = NSImage(named: "MenuBarIcon")
      icon?.size = NSSize(width: 18, height: 18)
      icon?.isTemplate = true
      icon?.accessibilityDescription = "Whoa Notch"
      button.image = icon
    }

    buildMenu()
  }

  /// Affiche ou masque l'icône de la barre de menus (réglage « Show menu bar icon »).
  func setVisible(_ visible: Bool) {
    statusItem.isVisible = visible
  }

  /// Met à jour le sous-menu des profils du dock. C'est l'accès au clavier de la pastille, dont la
  /// fenêtre ne prend jamais le focus.
  func apply(profiles newProfiles: [DockProfile], activeID: String?) {
    profiles = newProfiles
    activeProfileID = activeID
    buildMenu()
  }

  private func buildMenu() {
    let menu = NSMenu()

    if !profiles.isEmpty {
      let submenu = NSMenu(title: "Profile")
      for profile in profiles {
        let item = NSMenuItem(
          title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = profile.id
        item.state = profile.id == activeProfileID ? .on : .off
        item.image = NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil)
        submenu.addItem(item)
      }
      let parent = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
      parent.submenu = submenu
      menu.addItem(parent)
      menu.addItem(NSMenuItem.separator())
    }

    menu.addItem(
      NSMenuItem(
        title: "Préférences…",
        action: #selector(openPreferences),
        keyEquivalent: ","
      )
    )
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Whoa Notch",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )

    for item in menu.items where item.action == #selector(openPreferences) {
      item.target = self
    }

    statusItem.menu = menu
  }

  @objc private func selectProfile(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onSelectProfile?(id)
  }

  @objc private func openPreferences() {
    Log.settings.debug("ouverture de la fenêtre de Préférences")
    SettingsWindowController.shared.show()
  }
}
