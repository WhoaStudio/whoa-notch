import AppKit

/// Une icône de la maquette : elle se laisse saisir pour être déplacée ou sortie du dock.
private final class PreviewIconView: NSView, NSDraggingSource {

  let app: DockPinnedApp
  var onDragOut: ((DockPinnedApp) -> Void)?
  private let imageView = NSImageView()
  private let image: NSImage

  init(app: DockPinnedApp) {
    self.app = app
    image = NSWorkspace.shared.icon(
      forFile: URL(fileURLWithPath: app.path).resolvingSymlinksInPath().path)
    super.init(frame: .zero)
    wantsLayer = true
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(imageView)
    toolTip = DockModel.displayName(path: app.path)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  override func layout() {
    super.layout()
    imageView.frame = bounds
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}

  override func mouseDragged(with event: NSEvent) {
    let item = DockAppDrag.item(for: app, image: image, size: bounds.width)
    item.draggingFrame = NSRect(origin: .zero, size: bounds.size)
    alphaValue = 0.3
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    alphaValue = 1
    // Lâchée ailleurs que sur la maquette : l'appli sort du dock.
    guard operation.isEmpty else { return }
    NSAnimationEffect.disappearingItemDefault.show(centeredAt: screenPoint, size: .zero)
    onDragOut?(app)
  }
}

/// Maquette du dock d'un profil : les applis dans leur ordre, qu'on réorganise en les
/// glissant. On y dépose une appli du sélecteur pour l'ajouter, et on en sort une icône pour la retirer.
final class DockPreviewView: NSView {

  var onPlace: ((DockPinnedApp, Int) -> Void)?
  var onRemove: ((DockPinnedApp) -> Void)?

  private static let maxIconSize: CGFloat = 44
  private static let minIconSize: CGFloat = 22
  private static let gap: CGFloat = 8
  private static let padding: CGFloat = 14

  private var apps: [DockPinnedApp] = []
  private var iconViews: [String: PreviewIconView] = [:]
  private var gapIndex: Int?
  private let hint = NSTextField(labelWithString: "Drag apps here to build this profile's dock")

  init(size: NSSize) {
    super.init(frame: NSRect(origin: .zero, size: size))
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: size.width),
      heightAnchor.constraint(equalToConstant: size.height),
    ])
    wantsLayer = true
    // Même fond que le dock lui-même (celui de l'encoche).
    layer?.backgroundColor = OverlayPalette.base.panelBackground
    layer?.cornerRadius = 18
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .tertiaryLabelColor
    addSubview(hint)
    registerForDraggedTypes([.dockApp])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func setEnabled(_ enabled: Bool) { alphaValue = enabled ? 1 : 0.4 }

  func setApps(_ newApps: [DockPinnedApp]) {
    guard newApps != apps else { return }
    let ids = Set(newApps.map(\.bundleID))
    for (id, view) in iconViews where !ids.contains(id) {
      view.removeFromSuperview()
      iconViews[id] = nil
    }
    for app in newApps where iconViews[app.bundleID] == nil {
      let view = PreviewIconView(app: app)
      view.onDragOut = { [weak self] in self?.onRemove?($0) }
      addSubview(view)
      iconViews[app.bundleID] = view
    }
    apps = newApps
    layoutIcons(animated: window != nil)
  }

  // MARK: - Disposition

  override func layout() {
    super.layout()
    layoutIcons(animated: false)
  }

  /// Cadres des icônes ; `gap` laisse un emplacement vide à cet indice, là où le dépôt va tomber.
  private func frames(gap: Int?) -> (frames: [CGRect], size: CGFloat) {
    let slots = apps.count + (gap == nil ? 0 : 1)
    guard slots > 0 else { return ([], Self.maxIconSize) }
    let available = bounds.width - Self.padding * 2
    let size = max(
      Self.minIconSize,
      min(Self.maxIconSize, (available - CGFloat(slots - 1) * Self.gap) / CGFloat(slots)))
    let total = CGFloat(slots) * size + CGFloat(slots - 1) * Self.gap
    var x = max(Self.padding, (bounds.width - total) / 2)
    var result: [CGRect] = []
    for index in 0..<slots {
      let frame = CGRect(x: x, y: (bounds.height - size) / 2, width: size, height: size)
      if index != gap { result.append(frame) }
      x += size + Self.gap
    }
    return (result, size)
  }

  private func layoutIcons(animated: Bool) {
    hint.isHidden = !apps.isEmpty || gapIndex != nil
    hint.sizeToFit()
    hint.frame.origin = NSPoint(
      x: (bounds.width - hint.frame.width) / 2, y: (bounds.height - hint.frame.height) / 2)
    let layout = frames(gap: gapIndex).frames
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated && OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
      for (index, app) in apps.enumerated() where index < layout.count {
        guard let view = iconViews[app.bundleID] else { continue }
        if animated { view.animator().frame = layout[index] } else { view.frame = layout[index] }
      }
    }
  }

  // MARK: - Dépôt

  /// L'indice d'insertion : le nombre d'icônes (au repos) dont le centre est à gauche du curseur.
  private func insertionIndex(for sender: NSDraggingInfo) -> Int {
    let x = convert(sender.draggingLocation, from: nil).x
    return frames(gap: nil).frames.prefix(apps.count).filter { $0.midX < x }.count
  }

  private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let index = insertionIndex(for: sender)
    if index != gapIndex {
      gapIndex = index
      layoutIcons(animated: true)
    }
    return operation(for: sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { clearGap() }
  override func draggingEnded(_ sender: NSDraggingInfo) { clearGap() }

  private func clearGap() {
    guard gapIndex != nil else { return }
    gapIndex = nil
    layoutIcons(animated: true)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let app = DockAppDrag.app(from: sender.draggingPasteboard) else { return false }
    let index = insertionIndex(for: sender)
    gapIndex = nil
    onPlace?(app, index)
    return true
  }
}
