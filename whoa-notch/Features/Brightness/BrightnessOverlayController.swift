import AppKit
import Combine

/// Fenêtre flottante (NSPanel) qui héberge le widget de luminosité.
/// Sans titre, transparente, toujours au-dessus, ne prend jamais le focus.
///
/// Apparaît quand le curseur atteint la zone sensible du bord configuré, reste affichée tant que
/// le curseur est au-dessus d'elle (ou que l'utilisateur scrolle), et se referme peu après
/// que le curseur l'a quittée — comme un contrôle qui "suit" l'utilisateur plutôt qu'un
/// widget qui s'impose pendant deux secondes fixes. Chaque aspect visible (position, délai de
/// fermeture, intensité du glow, affichage du pourcentage) suit `Brightness` dans les
/// Préférences en direct.
///
/// Le cadre, lui, ne vient pas des Préférences : c'est celui d'une bande de bord
/// (`PanelGeometry`), partagé avec le panneau latéral pour que les deux se répondent d'un bord
/// à l'autre de l'écran.
///
/// Le widget règle la luminosité de l'écran où il est affiché, pas celle de l'écran
/// principal : c'est lui qui désigne l'écran cible au service de luminosité, puisqu'il est le
/// seul à savoir où il se trouve.
@MainActor
final class BrightnessOverlayController {

  private let panel: NSPanel
  private let containerView: BrightnessView
  private let viewModel: BrightnessViewModel
  private let mouseMonitor = GlobalMouseMonitor()
  private var closeWorkItem: DispatchWorkItem?
  private var settingsCancellable: AnyCancellable?
  private var paletteObserver: NSObjectProtocol?

  /// Taille de la fenêtre : la largeur serre la bande et la bulle du soleil posée à côté
  /// (`PanelGeometry.brightnessPanelWidth`), la hauteur suit `Brightness > Widget size`. La
  /// fenêtre est créée avec cette taille, puis recadrée sur l'écran d'arrivée par
  /// `position(on:)`.
  private var panelSize: NSSize {
    NSSize(width: PanelGeometry.brightnessPanelWidth, height: widgetSize.panelHeight)
  }

  private var closeDelay: TimeInterval
  private var glowIntensity: Double
  private var showPercentage: Bool
  private var widgetPosition: EdgePosition
  private var widgetSize: WidgetSize
  private var isEnabled = false

  /// `storage` n'est lu qu'ici : au-delà de l'init, l'état courant arrive par
  /// `settingsCancellable`, pas par une relecture du stockage.
  init(controller: BrightnessControlling, storage: SettingsStorage = .shared) {
    let brightness = storage.settings.brightness
    closeDelay = brightness.autoHideDelay
    glowIntensity = brightness.glowIntensity
    showPercentage = brightness.showPercentage
    widgetPosition = brightness.widgetPosition
    widgetSize = brightness.widgetSize

    // Le feedback partage le même `storage` que le view model : tout le graphe de l'overlay
    // lit donc une seule et même source de préférences.
    viewModel = BrightnessViewModel(
      controller: controller,
      feedback: SystemOverlayFeedback(storage: storage),
      storage: storage
    )

    panel = NSPanel(
      contentRect: NSRect(
        origin: .zero,
        size: NSSize(
          width: PanelGeometry.brightnessPanelWidth, height: brightness.widgetSize.panelHeight)),
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
    // Sans ça, le panel se cache dès que whoa-notch (app sans fenêtre, menu bar only)
    // n'est plus "active", ce qui arrive en permanence puisqu'elle ne prend jamais le focus.
    panel.hidesOnDeactivate = false

    let initialPalette = OverlayPalette.resolved(for: panel.effectiveAppearance).scalingGlow(
      by: glowIntensity)
    containerView = BrightnessView(
      tickCount: BrightnessViewModel.tickCount, initialPalette: initialPalette)
    containerView.frame = NSRect(origin: .zero, size: panelSize)
    containerView.edge = widgetPosition
    panel.contentView = containerView

    // L'écran cible est résolu à chaque lecture/écriture, donc toujours à jour : inutile
    // de le reposer quand le panel change d'écran.
    controller.targetDisplay = { [weak panel] in NSScreen.hosting(panel)?.displayID }

    containerView.onScroll = { [weak self] delta in self?.handleScroll(delta) }
    containerView.sunButton.onTap = { [weak self] in self?.handleSunTap() }

    mouseMonitor.onMove = { [weak self] location in self?.handlePointerMove(location) }

    settingsCancellable = storage.$settings
      .sink { [weak self] settings in
        self?.apply(brightness: settings.brightness)
      }

    paletteObserver = NotificationCenter.default.addObserver(
      forName: OverlayPalette.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refreshPalette() }
    }
  }

  func activate() {
    containerView.updateBrightness(activeTickCount: viewModel.activeTickCount, animated: false)
  }

  private func apply(brightness: BrightnessSettings) {
    closeDelay = brightness.autoHideDelay
    showPercentage = brightness.showPercentage

    if widgetPosition != brightness.widgetPosition {
      widgetPosition = brightness.widgetPosition
      containerView.edge = widgetPosition
      if viewModel.isVisible, let screen = NSScreen.underCursor {
        position(on: screen)
      }
    }

    if widgetSize != brightness.widgetSize {
      widgetSize = brightness.widgetSize
      if let screen = NSScreen.hosting(panel) ?? NSScreen.underCursor {
        position(on: screen)
      }
    }

    if glowIntensity != brightness.glowIntensity {
      glowIntensity = brightness.glowIntensity
      refreshPalette()
    }

    setEnabled(brightness.enableOverlay)
  }

  /// Seule voie de repeinte du widget : le glow des Préférences s'applique par-dessus la
  /// palette résolue, qui porte déjà l'accent et la translucidité choisis.
  private func refreshPalette() {
    containerView.applyPalette(
      OverlayPalette.resolved(for: panel.effectiveAppearance).scalingGlow(by: glowIntensity)
    )
  }

  private func setEnabled(_ enabled: Bool) {
    guard isEnabled != enabled else { return }
    isEnabled = enabled

    if enabled {
      mouseMonitor.start()
    } else {
      mouseMonitor.stop()
      dismiss()
    }
  }

  private func handlePointerMove(_ location: NSPoint) {
    // Menu contextuel ouvert : le suivi est gelé. Le pointeur descend dans le menu, hors du
    // cadre du panneau, et celui-ci se replierait sous un menu encore ouvert.
    guard !OverlayContextMenu.shared.isPresenting else { return }

    if viewModel.isVisible {
      if panel.frame.contains(location) {
        cancelClose()
      } else {
        scheduleClose()
      }
    } else if isInHotZone(location) {
      reveal()
    }
  }

  /// La zone sensible est celle du panneau latéral, prise sur le bord configuré : son milieu,
  /// pas tout le bord. La bande est centrée sur ce bord — appelée depuis un coin de l'écran,
  /// elle s'ouvrirait loin du curseur.
  private func isInHotZone(_ location: NSPoint) -> Bool {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
      return false
    }
    return PanelGeometry.hotZone(on: screen, anchoredTo: widgetPosition).contains(location)
  }

  private func reveal() {
    guard let screen = NSScreen.underCursor else { return }
    position(on: screen)

    // La luminosité a pu changer pendant que le widget était fermé (touches clavier,
    // Réglages Système...) : on se resynchronise avant d'afficher, sans jouer de son/tick.
    // Après `position(on:)` et jamais avant : c'est la luminosité de l'écran d'arrivée
    // qu'il faut lire, et l'écran cible se déduit de la position du panel.
    viewModel.syncWithSystem()
    containerView.updateBrightness(activeTickCount: viewModel.activeTickCount, animated: false)

    if !panel.isVisible {
      panel.alphaValue = 1
      // La silhouette repliée est posée avant que la fenêtre ne passe devant : la première
      // image montrée doit être le début du dépliage, et non la bande en place.
      containerView.prepareForReveal()
      panel.orderFrontRegardless()
    }
    panel.ignoresMouseEvents = false
    viewModel.setVisible(true)
    containerView.setVisible(true)
    cancelClose()
  }

  private func position(on screen: NSScreen) {
    // Le panel démarre pile au bord de l'écran : le curseur qui déclenche l'apparition
    // se trouve donc déjà "au-dessus" du widget, pas d'à-coup au premier survol. Le cadre
    // vient de la géométrie commune — centré sur le milieu du bord, comme le panneau
    // latéral, pour que les deux bandes soient à la même place sur leur bord.
    let frame = PanelGeometry.panelFrame(
      on: screen,
      anchoredTo: widgetPosition,
      height: widgetSize.panelHeight,
      width: PanelGeometry.brightnessPanelWidth
    )
    panel.setFrame(frame, display: true)
    containerView.frame = NSRect(origin: .zero, size: frame.size)
  }

  private func handleScroll(_ deltaY: CGFloat) {
    guard viewModel.isVisible else { return }
    viewModel.adjust(byScrollDelta: deltaY)
    containerView.updateBrightness(activeTickCount: viewModel.activeTickCount, animated: true)
    if showPercentage {
      containerView.showPercent(viewModel.percent)
    }
    cancelClose()
  }

  private func handleSunTap() {
    viewModel.setBrightness(1.0)
    containerView.updateBrightness(activeTickCount: viewModel.activeTickCount, animated: true)
    cancelClose()
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

  private func dismiss() {
    cancelClose()
    guard viewModel.isVisible else { return }
    viewModel.setVisible(false)
    panel.ignoresMouseEvents = true

    containerView.setVisible(false) { [weak self] in
      // Un nouveau survol pendant le repli relance `reveal` : dans ce cas il ne faut
      // surtout pas retirer la fenêtre une fois l'ancien dépliage terminé.
      guard let self, !self.viewModel.isVisible else { return }
      self.panel.orderOut(nil)
    }
  }
}
