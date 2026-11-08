import AppKit

/// Fenêtre flottante (NSPanel) qui héberge le cadran de volume. Sans titre, transparente,
/// toujours au-dessus, ne prend jamais le focus — la même fenêtre que le widget de luminosité,
/// posée ailleurs.
///
/// Elle est appelée par le coin supérieur gauche de l'écran : le curseur entre dans le carré
/// sensible, le cadran jaillit depuis le pointeur, la molette règle le volume tant que le
/// curseur est dessus, et le cadran se résorbe peu après qu'il l'a quitté. Chacun des trois
/// coins utiles de l'écran a ainsi le sien — le milieu des flancs aux bandes, le coin
/// supérieur droit au panneau latéral, celui-ci au son.
///
/// Le volume réglé est celui du périphérique de sortie par défaut (`SystemVolumeService`),
/// c'est-à-dire tout ce qui sort des haut-parleurs : le cadran ne connaît aucune application en
/// particulier.
@MainActor
final class VolumeDialController {

  private let panel: NSPanel
  private let dialView: VolumeDialView
  private let viewModel: VolumeDialViewModel
  private let mouseMonitor = GlobalMouseMonitor()
  private var closeWorkItem: DispatchWorkItem?
  private var paletteObserver: NSObjectProtocol?

  /// Cadran ouvert par `--show-volume-dial` plutôt que par le survol : il ne se referme
  /// qu'une fois le curseur venu dessus puis reparti, sinon il disparaîtrait avant même que
  /// le pointeur l'ait atteint. Même comportement que la bande épinglée du panneau latéral.
  private var isPinned = false
  private var hasVisitedPinnedDial = false

  /// Délai avant fermeture une fois le curseur sorti du cadre. Le cadran n'a pas de réglage
  /// dans les Préférences, contrairement à la luminosité : c'est la valeur par défaut de
  /// celle-ci, pour que les deux se referment du même pas.
  private let closeDelay: TimeInterval = 0.45

  init() {
    viewModel = VolumeDialViewModel()

    let side = VolumeDialGeometry.diameter
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: side, height: side),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = true
    // Sans ça, le panel se cache dès que whoa-stash (app sans fenêtre, menu bar only)
    // n'est plus "active", ce qui arrive en permanence puisqu'elle ne prend jamais le focus.
    panel.hidesOnDeactivate = false

    dialView = VolumeDialView(
      initialPalette: VolumeDialView.palette(for: panel.effectiveAppearance)
    )
    dialView.frame = NSRect(x: 0, y: 0, width: side, height: side)
    panel.contentView = dialView

    dialView.onScroll = { [weak self] delta in self?.handleScroll(delta) }
    mouseMonitor.onMove = { [weak self] location in self?.handlePointerMove(location) }

    paletteObserver = NotificationCenter.default.addObserver(
      forName: OverlayPalette.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshPalette() }
    }
  }

  func activate() {
    viewModel.syncWithSystem()
    pushVolumeToView(animated: false)
    mouseMonitor.start()
  }

  /// Coupe ou rétablit le cadran : désactivé, plus aucun suivi du curseur et la fenêtre se ferme.
  func setEnabled(_ enabled: Bool) {
    if enabled {
      mouseMonitor.start()
    } else {
      mouseMonitor.stop()
      isPinned = false
      dismiss()
    }
  }

  /// Ouvre (ou referme) le cadran sur l'écran qui contient le curseur — appelé par
  /// `--show-volume-dial`, qui est ce qui le rend vérifiable sur capture d'écran.
  func togglePinnedReveal() {
    guard !isPinned else {
      isPinned = false
      dismiss()
      return
    }

    isPinned = true
    hasVisitedPinnedDial = false
    reveal(growingFrom: nil)
  }

  // MARK: - Suivi du curseur

  private func handlePointerMove(_ location: NSPoint) {
    // Menu contextuel ouvert : le suivi est gelé. Le pointeur descend dans le menu, hors du
    // cadre du cadran, qui se résorberait sous un menu encore ouvert.
    guard !OverlayContextMenu.shared.isPresenting else { return }

    if isPinned {
      if panel.frame.contains(location) {
        hasVisitedPinnedDial = true
        cancelClose()
      } else if hasVisitedPinnedDial {
        isPinned = false
        dismiss()
      }
      return
    }

    if viewModel.isVisible {
      // Le cadre est carré et le cadran rond : les quatre coins retiennent donc le cadran
      // ouvert un peu au-delà du disque. C'est voulu — le carré sensible du coin d'écran
      // est l'un d'eux, et c'est par lui que le curseur arrive.
      if panel.frame.contains(location) {
        cancelClose()
      } else {
        scheduleClose()
      }
    } else if isInHotZone(location) {
      reveal(growingFrom: location)
    }
  }

  private func isInHotZone(_ location: NSPoint) -> Bool {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
      return false
    }
    return VolumeDialGeometry.hotZone(on: screen).contains(location)
  }

  // MARK: - Apparition

  /// `growingFrom` est le point d'où le cadran jaillit, en coordonnées d'écran ; `nil` le fait
  /// grandir depuis son centre, pour une ouverture qui ne vient pas du curseur.
  private func reveal(growingFrom location: NSPoint?) {
    guard let screen = NSScreen.underCursor ?? NSScreen.main else { return }
    position(on: screen)

    // Le volume a pu changer pendant que le cadran était fermé (touches du clavier, Réglages
    // Système…) : on se resynchronise avant d'afficher. Après `position(on:)`, pour que la
    // première image soit déjà la bonne.
    viewModel.syncWithSystem()
    pushVolumeToView(animated: false)

    if !panel.isVisible {
      panel.alphaValue = 1
      // Le cadran replié est posé, point de croissance compris, avant que la fenêtre ne
      // passe devant : la première image montrée doit être le début du jaillissement.
      let origin =
        location.map { panel.convertPoint(fromScreen: $0) }
        ?? NSPoint(x: dialView.bounds.midX, y: dialView.bounds.midY)
      dialView.prepareForReveal(growingFrom: origin)
      panel.orderFrontRegardless()
    }

    panel.ignoresMouseEvents = false
    viewModel.setVisible(true)
    dialView.setVisible(true)
    cancelClose()
  }

  private func position(on screen: NSScreen) {
    let frame = VolumeDialGeometry.panelFrame(on: screen)
    panel.setFrame(frame, display: true)
    dialView.frame = NSRect(origin: .zero, size: frame.size)
  }

  private func dismiss() {
    cancelClose()
    guard viewModel.isVisible else { return }
    viewModel.setVisible(false)
    panel.ignoresMouseEvents = true

    dialView.setVisible(false) { [weak self] in
      // Un nouveau survol pendant la résorption relance `reveal` : dans ce cas il ne faut
      // surtout pas retirer la fenêtre une fois l'ancien geste terminé.
      guard let self, !self.viewModel.isVisible else { return }
      self.panel.orderOut(nil)
    }
  }

  private func scheduleClose() {
    guard closeWorkItem == nil else { return }
    let item = DispatchWorkItem { [weak self] in self?.dismiss() }
    closeWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: item)
  }

  private func cancelClose() {
    closeWorkItem?.cancel()
    closeWorkItem = nil
  }

  // MARK: - Réglage

  private func handleScroll(_ deltaY: CGFloat) {
    guard viewModel.isVisible else { return }
    viewModel.adjust(byScrollDelta: deltaY)
    pushVolumeToView(animated: true)
    cancelClose()
  }

  private func pushVolumeToView(animated: Bool) {
    dialView.updateVolume(
      fraction: viewModel.fraction,
      activeTickCount: viewModel.activeTickCount,
      percent: viewModel.percent,
      animated: animated
    )
  }

  private func refreshPalette() {
    dialView.applyPalette(VolumeDialView.palette(for: panel.effectiveAppearance))
  }
}
