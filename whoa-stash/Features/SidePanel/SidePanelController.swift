import AppKit
import Combine

/// Gère, par écran connecté, la bande de bagues du bord droit et la bulle de détail qui s'ouvre
/// à côté d'elles. La bande se révèle quand le curseur entre dans la zone sensible du coin
/// supérieur droit et se masque quand le curseur quitte à la fois cette zone, la bande et la
/// bulle. Reconstruit la liste des fenêtres à chaque changement de configuration d'écrans
/// (branchement, débranchement, résolution, réagencement).
///
/// Les fenêtres ne reçoivent aucun événement de souris (voir `SidePanelWindow`) : c'est ici que
/// la position globale du curseur est confrontée aux cadres, bagues comprises.
@MainActor
final class SidePanelController {

  private let mouseMonitor = GlobalMouseMonitor()
  private let storage: SettingsStorage

  /// Indexés par `CGDirectDisplayID` et non par position dans `NSScreen.screens`, qui change
  /// dès qu'un écran est branché ou débranché.
  private var windows: [CGDirectDisplayID: SidePanelWindow] = [:]
  private var callouts: [CGDirectDisplayID: UsageCalloutWindow] = [:]
  private var activeDisplay: CGDirectDisplayID?

  private var screenObserver: NSObjectProtocol?
  private var paletteObserver: NSObjectProtocol?
  private var pollTimer: Timer?

  private var claudeUsageState: ClaudeUsageState = .loading
  private var copilotUsageState: CopilotUsageState = .loading

  /// Ouverture forcée, hors survol du coin (`--show-usage-panel`) : le curseur est alors
  /// n'importe où, donc le suivi normal refermerait la bande au premier mouvement.
  /// L'épinglage suspend cette logique jusqu'à ce que l'utilisateur soit venu sur la bande
  /// puis en soit ressorti.
  private var isPinned = false
  private var hasVisitedPinnedPanel = false

  /// Bague actuellement survolée dans la bande, et donc visée par la bulle. `nil` quand le
  /// curseur est ailleurs.
  private var hoveredRingIndex: Int?
  private var hoveredProvider: UsageCalloutContentView.Provider = .claude

  /// Les moniteurs d'événements ne se déclenchent qu'au mouvement : si le curseur est téléporté,
  /// ou qu'il quitte la zone pendant un changement de Space, plus aucun événement n'arrive et
  /// les fenêtres resteraient ouvertes. Ce rafraîchissement ne tourne que pendant qu'une
  /// fenêtre est visible.
  private let pollInterval: TimeInterval = 0.25

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
  }

  func activate() {
    rebuildWindows()

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.rebuildWindows() }
    }

    // Aucune permission d'accessibilité requise : seuls les événements clavier et synthétiques
    // en demandent, pas le suivi des déplacements de souris.
    mouseMonitor.onMove = { [weak self] location in
      self?.handleCursor(at: location)
    }
    mouseMonitor.start()

    paletteObserver = NotificationCenter.default.addObserver(
      forName: OverlayPalette.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.applyPaletteChange() }
    }
  }

  /// Coupe ou rétablit le panneau : désactivé, plus aucun suivi du curseur et la bande se replie.
  func setEnabled(_ enabled: Bool) {
    if enabled {
      mouseMonitor.start()
    } else {
      mouseMonitor.stop()
      hideActive()
    }
  }

  /// Accent et translucidité ne passent pas par `NSAppearance` : la palette les porte, et
  /// c'est à nous de demander la repeinte.
  private func applyPaletteChange() {
    windows.values.forEach { $0.refreshPalette() }
    callouts.values.forEach { $0.refreshPalette() }
  }

  /// Diffuse le dernier instantané à toutes les fenêtres, y compris celles qui ne sont pas
  /// visibles : elles doivent être déjà à jour au moment où elles glissent à l'écran, pas se
  /// remplir après coup.
  func apply(usageState newState: ClaudeUsageState) {
    claudeUsageState = newState
    applyCurrentUsageStates(animated: true)
  }

  func apply(copilotUsageState newState: CopilotUsageState) {
    copilotUsageState = newState
    applyCurrentUsageStates(animated: true)
  }

  private func applyCurrentUsageStates(animated: Bool) {
    windows.values.forEach {
      $0.apply(claudeState: claudeUsageState, copilotState: copilotUsageState, animated: animated)
    }
    callouts.values.forEach {
      $0.apply(
        claudeState: claudeUsageState,
        copilotState: copilotUsageState,
        provider: hoveredProvider,
        animated: animated
      )
    }
  }

  /// Ouvre (ou referme) la bande de l'écran qui contient le curseur — appelé par
  /// `--show-usage-panel`.
  func togglePinnedReveal() {
    guard !isPinned else {
      isPinned = false
      hideActive()
      return
    }

    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        ?? NSScreen.main,
      let displayID = screen.displayID,
      let window = windows[displayID]
    else { return }

    if activeDisplay != displayID {
      hideActive()
      activeDisplay = displayID
    }

    isPinned = true
    hasVisitedPinnedPanel = false
    window.apply(
      claudeState: claudeUsageState,
      copilotState: copilotUsageState,
      animated: false
    )
    window.reveal(in: SidePanelGeometry.panelFrame(on: screen))
    startPolling()
  }

  private func isCursorOverCallout(at location: NSPoint) -> Bool {
    guard let activeDisplay, let callout = callouts[activeDisplay], callout.isVisible else {
      return false
    }
    return callout.frame.contains(location)
  }

  // MARK: - Suivi du curseur

  private func handleCursor(at location: NSPoint) {
    // Menu contextuel ouvert : le suivi est gelé. Le pointeur descend dans le menu, hors du
    // cadre du panneau, et celui-ci se replierait sous un menu encore ouvert.
    guard !OverlayContextMenu.shared.isPresenting else { return }

    // Un seul écran est testé, celui qui contient le curseur : avec des écrans accolés, le bord
    // droit de l'un recouvre le bord gauche du suivant, et tester toutes les zones ferait
    // apparaître la bande du mauvais écran.
    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
      let displayID = screen.displayID,
      let window = windows[displayID]
    else {
      hideActive()
      return
    }

    let inHotZone = SidePanelGeometry.hotZone(on: screen).contains(location)
    // La bande reste ouverte tant que le curseur est dessus — ou sur la bulle qu'elle a
    // ouverte, qu'il faut pouvoir atteindre sans que tout se referme en chemin.
    let overPanel = activeDisplay == displayID && window.frame.contains(location)
    let overCallout = activeDisplay == displayID && isCursorOverCallout(at: location)

    if isPinned {
      // La bande épinglée ne se referme qu'une fois le curseur venu dessus puis reparti —
      // sinon elle disparaîtrait avant même que le pointeur l'ait atteinte.
      if overPanel || overCallout {
        hasVisitedPinnedPanel = true
        updateRingHover(at: location, on: screen, displayID: displayID)
      } else if hasVisitedPinnedPanel {
        isPinned = false
        hideActive()
      }
      return
    }

    guard inHotZone || overPanel || overCallout else {
      hideActive()
      return
    }

    if activeDisplay != displayID {
      hideActive()
      activeDisplay = displayID
    }
    window.apply(
      claudeState: claudeUsageState,
      copilotState: copilotUsageState,
      animated: false
    )
    window.reveal(in: SidePanelGeometry.panelFrame(on: screen))
    startPolling()

    updateRingHover(at: location, on: screen, displayID: displayID)
  }

  /// Confronte le curseur aux bagues de la bande : celle qu'il survole est mise en avant et
  /// reçoit la bulle. Quand il n'en survole aucune, la bulle ne se referme que s'il n'est pas
  /// passé dessus — c'est ce qui permet d'aller la lire.
  private func updateRingHover(
    at location: NSPoint, on screen: NSScreen, displayID: CGDirectDisplayID
  ) {
    guard let window = windows[displayID], let callout = callouts[displayID] else { return }

    // Seules les bagues branchées ouvrent la bulle : les autres n'ont rien à montrer.
    let hovered = (0..<window.ringCount).first { index in
      SidePanelGeometry.ringSlots[index].isConnected
        && window.ringScreenRect(at: index)?.contains(location) ?? false
    }

    guard let hovered else {
      // Le curseur a quitté la bague : la bulle reste tant qu'il est dessus.
      if !callout.frame.contains(location) || !callout.isVisible {
        hoveredRingIndex = nil
        window.setHighlightedRing(nil)
        callout.hide()
      }
      return
    }

    window.setHighlightedRing(hovered)

    guard hovered != hoveredRingIndex || !callout.isVisible else { return }
    hoveredRingIndex = hovered
    hoveredProvider = SidePanelGeometry.ringSlots[hovered].mark == .copilot ? .copilot : .claude

    guard let ringRect = window.ringScreenRect(at: hovered) else { return }
    callout.apply(
      claudeState: claudeUsageState,
      copilotState: copilotUsageState,
      provider: hoveredProvider,
      animated: false
    )
    callout.reveal(SidePanelGeometry.callout(anchoredTo: ringRect, on: screen))
  }

  private func hideActive() {
    isPinned = false
    hoveredRingIndex = nil
    hoveredProvider = .claude
    guard let activeDisplay else { return }
    windows[activeDisplay]?.setHighlightedRing(nil)
    windows[activeDisplay]?.hide()
    callouts[activeDisplay]?.hide()
    self.activeDisplay = nil
    stopPolling()
  }

  // MARK: - Écrans

  private func rebuildWindows() {
    var connected: Set<CGDirectDisplayID> = []

    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }
      connected.insert(displayID)

      let window: SidePanelWindow
      if let existing = windows[displayID] {
        window = existing
      } else {
        window = SidePanelWindow()
        windows[displayID] = window
      }

      if callouts[displayID] == nil {
        callouts[displayID] = UsageCalloutWindow()
      }

      // Un écran déjà connu a pu changer de taille ou de position ; seule la bande visible
      // a besoin d'être recadrée tout de suite, les autres le seront à leur prochain survol.
      if activeDisplay == displayID {
        window.setFrame(SidePanelGeometry.panelFrame(on: screen))
      }
    }

    for (displayID, window) in windows where !connected.contains(displayID) {
      window.close()
      windows.removeValue(forKey: displayID)
      callouts.removeValue(forKey: displayID)?.close()
      if activeDisplay == displayID {
        activeDisplay = nil
        stopPolling()
      }
    }
  }

  // MARK: - Rafraîchissement pendant l'affichage

  private func startPolling() {
    guard pollTimer == nil else { return }
    let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.handleCursor(at: NSEvent.mouseLocation) }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
  }

  private func stopPolling() {
    pollTimer?.invalidate()
    pollTimer = nil
  }
}
