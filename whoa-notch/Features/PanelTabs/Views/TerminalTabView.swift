import AppKit
import SwiftTerm

/// L'onglet Terminal : une carte de verre qui accueille la vue de la `TerminalSession`.
///
/// La vue du terminal n'a qu'un parent à la fois ; chaque fenêtre du panneau a son cadre, et
/// c'est celui de la fenêtre qui se déplie qui la reçoit (voir `attach(_:)`).
///
/// Tout le mouvement porte sur la carte et ses boutons, jamais sur le texte : la frappe et le
/// défilement ne passent par aucune animation. Les ressorts viennent de `springAnimate`, qui se
/// coupe seul avec « Réduire les animations ».
final class TerminalTabView: NSView {

  /// Marge entre le bord de la carte et le texte.
  private static let padding: CGFloat = 10

  private weak var terminalView: TerminalSurface?
  private let actions = NSView()
  private let copyButton = NSButton()
  private let clearButton = NSButton()
  private let copiedLabel = NSTextField(labelWithString: "Copied")
  private let latestPill = NSButton()

  private var isHovered = false
  private var isDropTargeted = false
  private var isLatestShown = false
  private var copiedReset: DispatchWorkItem?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    // Concentrique à la silhouette (encoche comme île : même rayon bas) : le rayon du panneau
    // moins la marge qui sépare la carte de son bord.
    layer?.cornerRadius = max(
      10, NotchPanelGeometry.expandedBottomRadius - NotchPanelGeometry.contentInsetBottom)
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.backgroundColor = Self.restingFill
    registerForDraggedTypes([.fileURL])
    setUpOverlays()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private static let restingFill = NSColor.white.withAlphaComponent(0.05).cgColor
  private static let dropFill = NSColor.white.withAlphaComponent(0.12).cgColor

  // MARK: - Mise en place

  private func setUpOverlays() {
    configure(copyButton, symbol: "doc.on.doc", tip: "Copy selection (or all output)", action: #selector(copyOutput))
    configure(clearButton, symbol: "eraser", tip: "Clear screen", action: #selector(clearScreen))

    copiedLabel.font = .systemFont(ofSize: 11, weight: .medium)
    copiedLabel.textColor = .white.withAlphaComponent(0.7)
    copiedLabel.wantsLayer = true
    copiedLabel.layer?.opacity = 0

    actions.wantsLayer = true
    actions.layer?.cornerRadius = 8
    actions.layer?.cornerCurve = .continuous
    actions.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    actions.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
    actions.layer?.borderWidth = 0.5
    actions.layer?.opacity = 0
    actions.isHidden = true
    actions.addSubview(copyButton)
    actions.addSubview(clearButton)

    latestPill.isBordered = false
    latestPill.wantsLayer = true
    latestPill.title = "Latest"
    latestPill.font = .systemFont(ofSize: 11, weight: .semibold)
    latestPill.contentTintColor = .white
    latestPill.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Scroll to latest output")?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
    latestPill.imagePosition = .imageLeading
    latestPill.imageHugsTitle = true
    latestPill.target = self
    latestPill.action = #selector(scrollToLatest)
    latestPill.layer?.cornerRadius = 11
    latestPill.layer?.cornerCurve = .continuous
    latestPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
    latestPill.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    latestPill.layer?.borderWidth = 0.5
    latestPill.layer?.opacity = 0
    latestPill.isHidden = true

    addSubview(copiedLabel)
    addSubview(actions)
    addSubview(latestPill)
  }

  private func configure(_ button: NSButton, symbol: String, tip: String, action: Selector) {
    button.isBordered = false
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    button.contentTintColor = .white.withAlphaComponent(0.7)
    button.toolTip = tip
    button.target = self
    button.action = action
  }

  // MARK: - Session

  /// Prend la vue du terminal et démarre le shell s'il ne tourne pas.
  func attach(_ session: TerminalSession) {
    let view = session.view
    if view.superview !== self {
      view.removeFromSuperview()
      addSubview(view, positioned: .below, relativeTo: copiedLabel)
    }
    terminalView = view
    view.onScrollChanged = { [weak self] position, byUser in
      self?.setLatestShown(byUser && position < 0.999)
    }
    view.applyAccent()
    needsLayout = true
    layoutTerminal()
    session.startIfNeeded()
  }

  /// Donne le clavier à la vue du terminal. Faux si elle n'est pas (encore) dans une fenêtre.
  @discardableResult
  func focusTerminal() -> Bool {
    guard let terminalView, let window = terminalView.window else { return false }
    return window.makeFirstResponder(terminalView)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    layoutTerminal()

    let button: CGFloat = 26
    actions.frame = NSRect(
      x: bounds.maxX - 6 - button * 2, y: bounds.maxY - 6 - button, width: button * 2, height: button)
    copyButton.frame = NSRect(x: 0, y: 0, width: button, height: button)
    clearButton.frame = NSRect(x: button, y: 0, width: button, height: button)

    copiedLabel.sizeToFit()
    copiedLabel.frame.origin = NSPoint(
      x: actions.frame.minX - 8 - copiedLabel.frame.width,
      y: actions.frame.midY - copiedLabel.frame.height / 2)

    let pill = latestPill.fittingSize
    let pillSize = NSSize(width: pill.width + 14, height: 22)
    latestPill.frame = NSRect(
      x: bounds.midX - pillSize.width / 2, y: 10, width: pillSize.width, height: pillSize.height)
  }

  /// Le terminal occupe la carte moins sa marge. Le cadre n'est pas un multiple de la cellule :
  /// la bande restante est transparente (voir `TerminalSurface`), donc elle se fond dans la carte.
  private func layoutTerminal() {
    guard let terminalView, terminalView.superview === self else { return }
    let target = bounds.insetBy(dx: Self.padding, dy: Self.padding)
    if terminalView.frame != target { terminalView.frame = target }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let terminalView, terminalView.hasFocus, terminalView.handleZoomShortcut(event) { return true }
    return super.performKeyEquivalent(with: event)
  }

  // MARK: - Focus et survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  private func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    fade(actions, visible: hovered)
  }

  /// Fondu au ressort ; la vue n'est masquée qu'une fois éteinte, pour ne pas capter les clics.
  private func fade(_ view: NSView, visible: Bool) {
    if visible { view.isHidden = false }
    view.layer?.springAnimate(keyPath: "opacity", to: Float(visible ? 1 : 0)) { [weak view] in
      if !visible, view?.layer?.opacity == 0 { view?.isHidden = true }
    }
  }

  // MARK: - Actions

  @objc private func copyOutput() {
    guard let terminalView else { return }
    // Sans sélection, tout le tampon : la vue ne donne pas le seul écran visible.
    var text = terminalView.getSelection()
    if text == nil {
      terminalView.selectAll()
      text = terminalView.getSelection()
      terminalView.selectNone()
    }
    guard let text, !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    showCopied()
  }

  private func showCopied() {
    copiedReset?.cancel()
    copiedLabel.layer?.springReveal(x: 6, y: 0)
    copiedLabel.layer?.opacity = 1
    let reset = DispatchWorkItem { [weak self] in
      self?.copiedLabel.layer?.springAnimate(keyPath: "opacity", to: Float(0))
    }
    copiedReset = reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: reset)
  }

  /// Ctrl-L : c'est le shell qui efface, comme au clavier.
  @objc private func clearScreen() {
    terminalView?.send(txt: "\u{0C}")
    focusTerminal()
  }

  @objc private func scrollToLatest() {
    terminalView?.scrollToBottom()
    setLatestShown(false)
    focusTerminal()
  }

  private func setLatestShown(_ shown: Bool) {
    guard shown != isLatestShown else { return }
    isLatestShown = shown
    if shown { latestPill.layer?.springReveal(x: 0, y: -6) }
    fade(latestPill, visible: shown)
  }

  // MARK: - Déposer un fichier

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard !fileURLs(from: sender).isEmpty else { return [] }
    setDropTargeted(true)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    isDropTargeted ? .copy : []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { setDropTargeted(false) }
  override func draggingEnded(_ sender: NSDraggingInfo) { setDropTargeted(false) }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    setDropTargeted(false)
    let paths = fileURLs(from: sender).map { Self.shellQuoted($0.path) }
    guard let terminalView, !paths.isEmpty else { return false }
    // Comme Terminal.app : le chemin est tapé, jamais exécuté (pas de retour chariot).
    terminalView.send(txt: paths.joined(separator: " ") + " ")
    focusTerminal()
    return true
  }

  private func fileURLs(from info: NSDraggingInfo) -> [URL] {
    let objects = info.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    return (objects as? [URL]) ?? []
  }

  private func setDropTargeted(_ targeted: Bool) {
    guard targeted != isDropTargeted else { return }
    isDropTargeted = targeted
    layer?.springAnimate(keyPath: "backgroundColor", to: targeted ? Self.dropFill : Self.restingFill)
  }

  /// Échappe un chemin pour le shell : tel quel s'il est sûr, sinon entre apostrophes.
  static func shellQuoted(_ path: String) -> String {
    let safe = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:@%,~")
    if path.unicodeScalars.allSatisfy(safe.contains) { return path }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
