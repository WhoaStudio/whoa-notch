import AppKit

/// Fenêtre flottante de la bulle d'utilisation, une par écran. Jumelle de `SidePanelWindow` :
/// elle ne prend jamais le focus et laisse passer tous les clics — le survol est déduit de la
/// position globale du curseur par `SidePanelController`.
///
/// C'est une fenêtre à part et non une seconde silhouette du panneau : la bande de bagues reste
/// visible pendant que la bulle est ouverte, donc les deux doivent pouvoir être à l'écran en
/// même temps.
@MainActor
final class UsageCalloutWindow {

  private let panel: NSPanel
  private let contentView = UsageCalloutContentView()
  private var isRevealed = false

  init() {
    panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // Voir `UsageCalloutContentView` : l'ombre est portée par le calque du contenu.
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    panel.contentView = contentView
  }

  var frame: NSRect { panel.frame }
  var isVisible: Bool { isRevealed }

  func apply(
    claudeState: ClaudeUsageState, copilotState: CopilotUsageState,
    provider: UsageCalloutContentView.Provider, animated: Bool
  ) {
    contentView.apply(
      claudeState: claudeState, copilotState: copilotState, provider: provider, animated: animated)
  }

  /// Repeint depuis la palette courante — appelé quand l'accent ou la translucidité change
  /// dans les Préférences, et non quand l'apparence système bascule (AppKit s'en charge).
  func refreshPalette() {
    contentView.refreshOverlayPalette()
  }

  func reveal(_ callout: SidePanelGeometry.Callout) {
    // La pointe d'abord : elle décide du sens du glissement et de la mise en page du
    // contenu, que `setFrame` va justement appliquer.
    contentView.tail = callout.tail
    setFrame(callout.frame)
    guard !isRevealed else { return }
    isRevealed = true

    contentView.prepareForReveal()
    panel.orderFrontRegardless()
    contentView.animateIn()
  }

  func hide() {
    guard isRevealed else { return }
    isRevealed = false

    contentView.animateOut { [weak self] in
      // Un nouveau survol pendant la sortie relance `reveal` : dans ce cas il ne faut
      // surtout pas retirer la fenêtre une fois l'ancienne animation terminée.
      guard let self, !self.isRevealed else { return }
      self.panel.orderOut(nil)
    }
  }

  func setFrame(_ frame: NSRect) {
    panel.setFrame(frame, display: true)
    contentView.frame = NSRect(origin: .zero, size: frame.size)
  }

  /// Retrait immédiat, sans animation : l'écran correspondant vient de disparaître.
  func close() {
    isRevealed = false
    panel.orderOut(nil)
  }
}
