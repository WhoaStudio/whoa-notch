import AppKit
import OSLog
import SwiftUI

/// Fenêtre de bienvenue du premier lancement. Sa fermeture pose `hasSeenOnboarding`, ce qui
/// l'empêche de revenir. Comme les Préférences, elle réclame l'icône du Dock tant qu'elle est ouverte.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

  static let shared = OnboardingWindowController()

  private convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 810),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.center()

    self.init(window: window)
    window.contentView = NSHostingView(
      rootView: OnboardingView(onStart: { [weak self] in self?.close() }))
    window.delegate = self
  }

  func show() {
    DockPresence.showIcon()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    SettingsStorage.shared.settings.hasSeenOnboarding = true
    Log.onboarding.debug("fenêtre de bienvenue fermée")
    DockPresence.hideIcon()
  }
}
