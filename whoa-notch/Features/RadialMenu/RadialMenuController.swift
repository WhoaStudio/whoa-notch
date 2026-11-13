import AppKit
import os

/// Panneau sans bordure qui peut devenir clé (sans activer l'app) pour recevoir Échap.
private final class RadialPanel: NSPanel {
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Menu radial ouvert sous le curseur par un bouton de souris maintenu.
///
/// Deux gestes : maintenir le bouton, viser, relâcher pour exécuter ; ou un appui bref, qui laisse
/// le menu ouvert pour viser puis cliquer. Dans les deux cas Échap, un clic hors du disque ou un
/// relâché dans la zone morte le ferme sans rien exécuter.
@MainActor
final class RadialMenuController {

  private let service = MouseButtonHoldService()
  private let panel: RadialPanel
  private let view: RadialMenuView
  private var items: [RadialMenuItem] = []
  private var anchor: CGPoint = .zero
  private var pressedAt: Date = .distantPast
  private var highlighted: Int?
  private var isOpen = false
  private var isSticky = false
  private var monitors: [Any] = []
  /// Déclencheur « trois doigts » : le menu s'ouvre sans clic et se ferme quand le curseur sort.
  private var threeFingerMode = false
  private var closesOnExit = false
  /// Faux tant que les doigts n'ont pas été levés après une ouverture ou une fermeture : sans
  /// cela, fermer le menu avec trois doigts toujours posés le rouvrirait aussitôt.
  private var armed = true
  private var fingerWork: DispatchWorkItem?

  /// Au-delà de cette durée ou de cette distance, le relâché exécute au lieu de laisser ouvert.
  private static let tapDuration: TimeInterval = 0.25
  private static let tapDistance: CGFloat = RadialMenuGeometry.deadZone

  init() {
    let size = NSSize(width: RadialMenuGeometry.diameter, height: RadialMenuGeometry.diameter)
    view = RadialMenuView(frame: NSRect(origin: .zero, size: size))
    panel = RadialPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .popUpMenu
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    panel.contentView = view
    panel.onEscape = { [weak self] in self?.close() }
    view.onClick = { [weak self] in self?.commit() }
  }

  func activate() {
    service.onPress = { [weak self] in self?.open() }
    service.onDrag = { [weak self] in self?.updateHighlight() }
    service.onRelease = { [weak self] in self?.released() }
    MultitouchFingerCounter.shared.onChange = { [weak self] count in
      Task { @MainActor in self?.fingersChanged(count) }
    }
  }

  func apply(settings: RadialMenuSettings) {
    items = Array(settings.items.prefix(RadialMenuSettings.maxItems))
    threeFingerMode = settings.enabled && settings.button == .threeFingerClick
    if threeFingerMode { MultitouchFingerCounter.shared.start() }
    // Trois doigts ne passe pas par la souris : pas de tap, donc pas d'Accessibilité requise.
    service.apply(enabled: settings.enabled && !threeFingerMode, button: settings.button)
    // Les changements des Préférences se voient sans relancer, même menu ouvert.
    if isOpen {
      view.apply(items: items, highlighted: highlighted.flatMap { $0 < items.count ? $0 : nil })
    }
  }

  /// `--show-radial-menu` : ouvre le menu sous le curseur, en mode laissé ouvert.
  func openForDevelopment() {
    open()
    enterSticky()
  }

  // MARK: - Trois doigts

  private func fingersChanged(_ count: Int) {
    guard threeFingerMode else { return }
    if count < 3 { armed = true }
    guard count == 3 else {
      fingerWork?.cancel()
      return
    }
    guard armed, !isOpen else { return }
    // Court délai : trois doigts qui se posent passent par 1, 2 puis 3 contacts, et un
    // contact de plus (quatre doigts) ne doit pas ouvrir le menu.
    fingerWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.openFromFingers() }
    }
    fingerWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
  }

  private func openFromFingers() {
    guard threeFingerMode, armed, !isOpen, MultitouchFingerCounter.shared.fingers == 3 else {
      return
    }
    armed = false
    open()
    enterSticky()
    closesOnExit = true
  }

  // MARK: - Ouverture et fermeture

  private func open() {
    if isOpen { close() }
    let cursor = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let center = RadialMenuGeometry.center(forCursor: cursor, in: visible)
    let radius = RadialMenuGeometry.diameter / 2
    panel.setFrame(
      NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
      display: true)
    anchor = cursor
    pressedAt = Date()
    highlighted = nil
    isOpen = true
    isSticky = false
    view.apply(items: items, highlighted: nil)
    panel.orderFrontRegardless()
    Log.radialMenu.info("menu ouvert (\(self.items.count, privacy: .public) éléments)")
  }

  private func close() {
    guard isOpen else { return }
    isOpen = false
    isSticky = false
    closesOnExit = false
    armed = false
    panel.orderOut(nil)
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
  }

  private func released() {
    guard isOpen, !isSticky else { return }
    let quick = Date().timeIntervalSince(pressedAt) < Self.tapDuration
    let still =
      hypot(NSEvent.mouseLocation.x - anchor.x, NSEvent.mouseLocation.y - anchor.y)
      < Self.tapDistance
    if quick && still {
      enterSticky()
    } else {
      commit()
    }
  }

  /// Menu laissé ouvert : le visé suit la souris, un clic exécute, un clic dehors ferme.
  private func enterSticky() {
    isSticky = true
    panel.makeKey()
    monitors.append(
      NSEvent.addGlobalMonitorForEvents(matching: [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
      ]) {
        [weak self] event in
        MainActor.assumeIsolated {
          if event.type == .mouseMoved { self?.updateHighlight() } else { self?.close() }
        }
      } as Any)
    monitors.append(
      NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
        self?.updateHighlight()
        return event
      } as Any)
  }

  // MARK: - Sélection

  private func updateHighlight() {
    guard isOpen else { return }
    let cursor = NSEvent.mouseLocation
    if closesOnExit {
      let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
      if hypot(cursor.x - center.x, cursor.y - center.y) > RadialMenuGeometry.diameter / 2 + 12 {
        close()
        return
      }
    }
    let next = RadialMenuGeometry.index(
      forOffset: CGVector(dx: cursor.x - anchor.x, dy: cursor.y - anchor.y), count: items.count)
    guard next != highlighted else { return }
    highlighted = next
    view.apply(items: items, highlighted: next)
  }

  private func commit() {
    updateHighlight()
    let item = highlighted.map { items[$0] }
    close()
    guard let item else { return }
    RadialMenuActionRunner.run(item)
  }
}
