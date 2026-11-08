import AppKit
import OSLog

/// Gère l'icône dans la menu bar macOS (NSStatusItem) et son menu déroulant.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

  private let statusItem: NSStatusItem

  private var animationTimer: Timer?
  private var openness: CGFloat = 0
  private var startOpenness: CGFloat = 0
  private var targetOpenness: CGFloat = 0
  private var animationStart: TimeInterval = 0
  private let lid = NSImage(named: "MenuBarLid")
  private let body = NSImage(named: "MenuBarBody")

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    super.init()

    if let button = statusItem.button {
      // Glyphe monochrome dédié : l'icône d'application complète devient illisible à 18 pt.
      let icon = NSImage(named: "MenuBarIcon")
      icon?.size = NSSize(width: 18, height: 18)
      icon?.isTemplate = true
      icon?.accessibilityDescription = "Whoa Stash"
      button.image = icon
    }

    updateIcon()
    buildMenu()
  }

  /// Affiche ou masque l'icône de la barre de menus (réglage « Show menu bar icon »).
  func setVisible(_ visible: Bool) {
    statusItem.isVisible = visible
  }

  private func buildMenu() {
    let menu = NSMenu()
    menu.delegate = self

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
        title: "Quit Whoa Stash",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )

    for item in menu.items where item.action == #selector(openPreferences) {
      item.target = self
    }

    statusItem.menu = menu
  }

  func menuWillOpen(_ menu: NSMenu) {
    animateLid(to: 1)
  }

  func menuDidClose(_ menu: NSMenu) {
    animateLid(to: 0)
  }

  /// Le minuteur reste actif pendant le suivi du menu natif.
  private func animateLid(to target: CGFloat) {
    animationTimer?.invalidate()
    animationTimer = nil
    targetOpenness = target
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      openness = target
      updateIcon()
      return
    }
    startOpenness = openness
    animationStart = ProcessInfo.processInfo.systemUptime
    let timer = Timer(
      timeInterval: 1.0 / 60, target: self,
      selector: #selector(advanceAnimation(_:)), userInfo: nil, repeats: true)
    animationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
  }

  @objc private func advanceAnimation(_ timer: Timer) {
    let elapsed = ProcessInfo.processInfo.systemUptime - animationStart
    let progress = min(elapsed / 0.18, 1)
    // Courbe ease-out (0.23, 1, 0.32, 1), inversée sur son axe temporel.
    var lower = 0.0
    var upper = 1.0
    for _ in 0..<12 {
      let t = (lower + upper) / 2
      let x =
        3 * (1 - t) * (1 - t) * t * 0.23
        + 3 * (1 - t) * t * t * 0.32 + t * t * t
      if x < progress { lower = t } else { upper = t }
    }
    let eased = progress >= 1 ? 1 : 1 - pow(1 - (lower + upper) / 2, 3)
    openness = startOpenness + (targetOpenness - startOpenness) * eased
    updateIcon()
    if progress >= 1 {
      timer.invalidate()
      animationTimer = nil
    }
  }

  /// Compose les deux parties vectorielles en une image modèle pour AppKit.
  private func updateIcon() {
    guard let lid, let body else { return }
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    body.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
    let offset = -(1 - openness) * (28 * 0.9 * 18 / 256)
    lid.draw(in: NSRect(x: 0, y: offset, width: 18, height: 18))
    image.unlockFocus()
    image.isTemplate = true
    image.accessibilityDescription = "Whoa Stash"
    statusItem.button?.image = image
  }

  @objc private func openPreferences() {
    Log.settings.debug("ouverture de la fenêtre de Préférences")
    SettingsWindowController.shared.show()
  }
}
