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
  private var pendingClose: Task<Void, Never>?

  /// Délai avant que la sortie ne démarre : voir `hide()`.
  private static let closeGrace: Duration = .milliseconds(90)

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
    let wasOnScreen = panel.isVisible
    contentView.tail = callout.tail

    // Une fermeture encore en attente est annulée : la bulle n'a pas commencé à s'effacer.
    let cancelledClose = pendingClose != nil
    pendingClose?.cancel()
    pendingClose = nil

    // Déjà ouverte : la fenêtre elle-même glisse d'une bague à l'autre, sans se refermer.
    // Le contenu ne bouge pas dans la fenêtre — le décaler la dépasserait et serait rogné.
    guard !isRevealed || cancelledClose else {
      glide(to: callout.frame)
      return
    }
    isRevealed = true

    // Encore à l'écran (fermeture en attente ou en cours) : on repart de l'état affiché au
    // lieu de repartir de zéro, ce qui ferait clignoter la bulle entre deux bagues voisines.
    guard !wasOnScreen else {
      glide(to: callout.frame)
      contentView.animateIn()
      return
    }

    // Entrée : la fenêtre part de quelques points du côté de la pointe et rejoint sa place
    // pendant que le contenu apparaît en fondu.
    setFrame(callout.frame.offsetBy(dx: contentView.entryOffset, dy: 0))
    contentView.prepareForReveal()
    panel.orderFrontRegardless()
    contentView.animateIn()
    glide(to: callout.frame)
  }

  func hide() {
    guard isRevealed else { return }
    isRevealed = false

    // Le départ est différé de `closeGrace` : entre deux bagues voisines le curseur traverse
    // un instant un espace vide, et une sortie lancée tout de suite ferait passer la bulle
    // par un creux de fondu avant que le survol suivant ne la rappelle.
    pendingClose?.cancel()
    pendingClose = Task { [weak self] in
      try? await Task.sleep(for: Self.closeGrace)
      guard let self, !Task.isCancelled else { return }
      self.pendingClose = nil

      self.contentView.animateOut { [weak self] in
        // Un nouveau survol pendant la sortie relance `reveal` : dans ce cas il ne faut
        // surtout pas retirer la fenêtre une fois l'ancienne animation terminée.
        guard let self, !self.isRevealed else { return }
        self.panel.orderOut(nil)
      }
      self.glide(to: self.panel.frame.offsetBy(dx: self.contentView.entryOffset, dy: 0))
    }
  }

  /// Déplace la fenêtre vers `frame` sur une courbe `ease-out`. Un nouvel appel en cours de
  /// route repart de la position affichée, donc deux bagues voisines s'enchaînent sans saut.
  /// Sans mouvement autorisé, la fenêtre est simplement posée.
  private func glide(to frame: NSRect) {
    guard OverlayAnimation.allowsMotion, panel.frame != frame else {
      setFrame(frame)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.28
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
      panel.animator().setFrame(frame, display: true)
    }
  }

  func setFrame(_ frame: NSRect) {
    panel.setFrame(frame, display: true)
    contentView.frame = NSRect(origin: .zero, size: frame.size)
  }

  /// Retrait immédiat, sans animation : l'écran correspondant vient de disparaître.
  func close() {
    isRevealed = false
    pendingClose?.cancel()
    pendingClose = nil
    panel.orderOut(nil)
  }
}
