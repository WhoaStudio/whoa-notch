import AppKit

/// Une case de la maquette : une appli (son icône) ou un vrai widget (la même tuile que dans le
/// dock, alimentée par sa source). Elle se laisse saisir pour être déplacée ou sortie du dock.
private final class PreviewTileView: NSView, NSDraggingSource {

  private enum Payload {
    case app(DockPinnedApp)
    case widget(DockWidgetPlacement)
  }

  let entryID: String
  private let payload: Payload
  private let widget: DockWidget?
  private let content: NSView
  private let appIcon: NSImage?
  /// L'icône vient d'être levée : la maquette ferme sa place et suit le curseur avec l'emplacement.
  var onDragBegan: ((String) -> Void)?
  /// La session est finie ; `operation` est vide si la case a été lâchée hors de la maquette.
  var onDragEnded: ((PreviewTileView, NSPoint, NSDragOperation) -> Void)?
  /// La croix du survol a été cliquée.
  var onRemoveRequested: ((PreviewTileView) -> Void)?
  private let closeButton = NSButton()
  private var isDragging = false

  private static let closeSide: CGFloat = 16
  /// Le léger grossissement de l'image portée par le curseur.
  private static let liftScale: CGFloat = 1.12

  /// `nil` pour un type de widget que le registre ne connaît plus.
  init?(entry: DockRowEntry) {
    entryID = entry.id
    let name: String
    switch entry {
    case .app(let item):
      payload = .app(DockPinnedApp(bundleID: item.bundleID, path: item.path))
      widget = nil
      let icon = NSWorkspace.shared.icon(
        forFile: URL(fileURLWithPath: item.path).resolvingSymlinksInPath().path)
      appIcon = icon
      let imageView = NSImageView()
      imageView.image = icon
      imageView.imageScaling = .scaleProportionallyUpOrDown
      content = imageView
      name = item.name
    case .widget(let placement):
      guard let kind = DockWidgetRegistry.kind(for: placement.kind) else { return nil }
      payload = .widget(placement)
      let made = kind.make()
      widget = made
      appIcon = nil
      content = made.view
      name = kind.title
    }
    super.init(frame: .zero)
    wantsLayer = true
    addSubview(content)
    toolTip = name
    setUpCloseButton(name: name)
    widget?.start()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  /// Arrête la source d'un widget qui sort de la maquette.
  func tearDown() {
    widget?.stop()
    removeFromSuperview()
  }

  /// L'image de la case, pour le curseur et pour le « poof ».
  var snapshot: NSImage {
    if let appIcon { return appIcon }
    guard let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds)
    else { return NSImage() }
    content.cacheDisplay(in: content.bounds, to: representation)
    let image = NSImage(size: content.bounds.size)
    image.addRepresentation(representation)
    return image
  }

  // La croix n'apparaît qu'au survol, en haut à gauche, à l'intérieur de la case : un bouton qui
  // déborde ne recevrait pas le clic.
  private func setUpCloseButton(name: String) {
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.image = NSImage(
      systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove \(name)")?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: Self.closeSide, weight: .bold)
          .applying(.init(paletteColors: [.white, NSColor(white: 0.2, alpha: 0.9)])))
    closeButton.target = self
    closeButton.action = #selector(closeTapped)
    closeButton.toolTip = "Remove \(name)"
    closeButton.setAccessibilityLabel("Remove \(name)")
    closeButton.alphaValue = 0
    addSubview(closeButton)
  }

  @objc private func closeTapped() { onRemoveRequested?(self) }

  override func layout() {
    super.layout()
    content.frame = bounds
    let side = min(Self.closeSide, bounds.width / 2)
    closeButton.frame = NSRect(x: 0, y: bounds.height - side, width: side, height: side)
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }

  override func mouseEntered(with event: NSEvent) { setCloseVisible(true) }
  override func mouseExited(with event: NSEvent) { setCloseVisible(false) }

  /// Fondu de la croix ; sans mouvement autorisé, elle paraît et disparaît d'un coup.
  private func setCloseVisible(_ visible: Bool) {
    let alpha: CGFloat = visible && !isDragging ? 1 : 0
    guard closeButton.alphaValue != alpha else { return }
    if OverlayAnimation.allowsMotion {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        closeButton.animator().alphaValue = alpha
      }
    } else {
      closeButton.alphaValue = alpha
    }
  }

  // MARK: - Glisser

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}

  override func mouseDragged(with event: NSEvent) {
    guard !isDragging else { return }
    isDragging = true
    closeButton.alphaValue = 0
    let lifted = bounds.width * Self.liftScale
    let item: NSDraggingItem
    switch payload {
    case .app(let app):
      item = DockAppDrag.item(for: app, image: snapshot, size: lifted)
    case .widget(let placement):
      item = DockWidgetDrag.item(
        for: DockWidgetDragPayload(kind: placement.kind, placementID: placement.id),
        image: snapshot, size: lifted)
    }
    let offset = (lifted - bounds.width) / 2
    item.draggingFrame = NSRect(x: -offset, y: -offset, width: lifted, height: lifted)
    onDragBegan?(entryID)
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
    isDragging = false
    closeButton.alphaValue = 0
    onDragEnded?(self, screenPoint, operation)
  }
}

/// Maquette du dock d'un profil, posée sur le fond d'écran : les applis et les vrais widgets dans
/// leur ordre, sur une pastille de verre. Une case saisie quitte la rangée (les voisines se
/// referment) et l'emplacement suit le curseur ; on la dépose pour la ranger. On y dépose aussi
/// une appli du sélecteur ou du Finder, ou un widget de la galerie, pour l'ajouter, et on sort une
/// case de la maquette (ou on clique sa croix) pour la retirer.
final class DockPreviewView: NSView {

  /// Une case de la maquette (appli ou widget) est rangée à `index`, compté sans elle.
  var onMove: ((String, Int) -> Void)?
  /// Une appli absente est déposée à `index` de la rangée.
  var onInsertApp: ((DockPinnedApp, Int) -> Void)?
  /// Un widget de ce type est déposé à `index` de la rangée.
  var onInsertWidget: ((String, Int) -> Void)?
  /// Une case, appli (son bundle) ou widget (son placement), sort du dock.
  var onRemove: ((String) -> Void)?

  private static let maxIconSize: CGFloat = 44
  private static let minIconSize: CGFloat = 22
  private static let gap: CGFloat = 8
  private static let padding: CGFloat = 14
  /// La pastille de verre posée sur le fond d'écran, comme un vrai dock : sa hauteur ne change pas,
  /// sa largeur épouse la rangée.
  private static let pillHeight: CGFloat = maxIconSize + 16
  private static let pillBottom: CGFloat = 14
  private static let pillInset: CGFloat = 10

  /// Ce qu'un glisser apporte : une appli (du sélecteur, de la maquette ou du Finder) ou un widget.
  private enum Dropped {
    case app(DockPinnedApp)
    case widget(DockWidgetDragPayload)
  }

  private var apps: [DockPinnedApp] = []
  private var widgets: [DockWidgetPlacement] = []
  private var entries: [DockRowEntry] = []
  private var tiles: [String: PreviewTileView] = [:]
  /// Les cases arrivées depuis la dernière disposition : elles apparaissent en fondu, sur place.
  private var freshIDs: Set<String> = []
  private var gapIndex: Int?
  /// La case de la maquette que le curseur porte (glissée d'ici), ou celle qu'un glisser venu
  /// d'ailleurs survole alors qu'elle y est déjà. Sa place est fermée dans la rangée.
  private var internalDragID: String?
  private var externalLiftID: String?
  private let hint = NSTextField(
    labelWithString: "Drag apps and widgets here to build this profile's dock")
  private let wallpaper = DesktopWallpaperView()
  private let pill = NSVisualEffectView()

  private var liftedID: String? { internalDragID ?? externalLiftID }
  /// La rangée sans la case levée : c'est dans cette liste que l'indice d'insertion est compté.
  private var remaining: [DockRowEntry] { entries.filter { $0.id != liftedID } }

  init(size: NSSize) {
    super.init(frame: NSRect(origin: .zero, size: size))
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: size.width),
      heightAnchor.constraint(equalToConstant: size.height),
    ])
    wantsLayer = true
    // Le fond d'écran courant, pour qu'on voie tout de suite que c'est un dock posé dessus.
    layer?.cornerRadius = 18
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    wallpaper.frame = bounds
    wallpaper.autoresizingMask = [.width, .height]
    addSubview(wallpaper)
    pill.material = .hudWindow
    pill.blendingMode = .withinWindow
    pill.state = .active
    pill.wantsLayer = true
    pill.layer?.cornerRadius = 20
    pill.layer?.cornerCurve = .continuous
    pill.layer?.masksToBounds = true
    pill.layer?.borderWidth = 1
    pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    addSubview(pill)
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = NSColor.white.withAlphaComponent(0.65)
    addSubview(hint)
    registerForDraggedTypes([.dockApp, .dockWidget, .fileURL])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    tiles.values.forEach { $0.tearDown() }
  }

  func setEnabled(_ enabled: Bool) { alphaValue = enabled ? 1 : 0.4 }

  /// Pose le contenu du profil : ses applis et ses widgets (un type inconnu est ignoré, comme
  /// dans le dock).
  func setContent(apps newApps: [DockPinnedApp], widgets newWidgets: [DockWidgetPlacement]) {
    let known = newWidgets.filter { DockWidgetRegistry.kind(for: $0.kind) != nil }
    guard newApps != apps || known != widgets else { return }
    let newEntries = DockRow.entries(items: newApps.map(\.dockItem), widgets: known)
    let ids = Set(newEntries.map(\.id))
    for (id, tile) in tiles where !ids.contains(id) {
      tile.tearDown()
      tiles[id] = nil
    }
    for entry in newEntries where tiles[entry.id] == nil {
      guard let tile = makeTile(for: entry) else { continue }
      addSubview(tile)
      tiles[entry.id] = tile
      if window != nil { freshIDs.insert(entry.id) }
    }
    apps = newApps
    widgets = known
    entries = newEntries
    layoutIcons(animated: window != nil)
  }

  private func makeTile(for entry: DockRowEntry) -> PreviewTileView? {
    guard let tile = PreviewTileView(entry: entry) else { return nil }
    tile.onRemoveRequested = { [weak self] tile in self?.remove(tile) }
    tile.onDragBegan = { [weak self] id in self?.beginLift(of: id) }
    tile.onDragEnded = { [weak self] tile, point, operation in
      self?.endDrag(of: tile, at: point, operation: operation)
    }
    return tile
  }

  /// La croix d'une case : elle sort du dock, avec le même « poof » qu'en la glissant dehors.
  private func remove(_ tile: PreviewTileView) {
    if let window {
      let center = NSPoint(x: tile.bounds.midX, y: tile.bounds.midY)
      let screenPoint = window.convertPoint(toScreen: tile.convert(center, to: nil))
      DockPoofEffect.show(image: tile.snapshot, size: tile.bounds.width, at: screenPoint)
    }
    onRemove?(tile.entryID)
  }

  // MARK: - Levée et fin du glisser

  /// La case quitte la rangée : son emplacement reste ouvert là où elle était, puis suit le curseur.
  private func beginLift(of id: String) {
    internalDragID = id
    gapIndex = entries.firstIndex { $0.id == id }
    layoutIcons(animated: false)
  }

  private func endDrag(of tile: PreviewTileView, at screenPoint: NSPoint, operation: NSDragOperation)
  {
    internalDragID = nil
    gapIndex = nil
    // Lâchée ailleurs que sur la maquette : la case sort du dock, dans un « poof ».
    guard operation.isEmpty else {
      layoutIcons(animated: true)
      return
    }
    DockPoofEffect.show(image: tile.snapshot, size: tile.bounds.width, at: screenPoint)
    onRemove?(tile.entryID)
    layoutIcons(animated: true)
  }

  // MARK: - Disposition

  override func layout() {
    super.layout()
    layoutIcons(animated: false)
  }

  /// Cadres des emplacements de la rangée sans la case levée ; `gap` laisse un emplacement vide à
  /// cet indice, là où le dépôt va tomber. `span` couvre toute la rangée, emplacement vide compris.
  private func frames(gap: Int?) -> (frames: [CGRect], gapFrame: CGRect?, span: CGRect?) {
    let slots = remaining.count + (gap == nil ? 0 : 1)
    guard slots > 0 else { return ([], nil, nil) }
    let available = bounds.width - Self.padding * 2
    let size = max(
      Self.minIconSize,
      min(Self.maxIconSize, (available - CGFloat(slots - 1) * Self.gap) / CGFloat(slots)))
    let total = CGFloat(slots) * size + CGFloat(slots - 1) * Self.gap
    var x = max(Self.padding, (bounds.width - total) / 2)
    let span = CGRect(x: x, y: Self.pillBottom, width: total, height: Self.pillHeight)
    var result: [CGRect] = []
    var gapFrame: CGRect?
    for index in 0..<slots {
      let centerY = Self.pillBottom + Self.pillHeight / 2
      let frame = CGRect(x: x, y: centerY - size / 2, width: size, height: size)
      if index == gap { gapFrame = frame } else { result.append(frame) }
      x += size + Self.gap
    }
    return (result, gapFrame, span)
  }

  /// La pastille autour de la rangée (emplacement vide compris) ; sans case, autour de l'invite.
  private func pillFrame(span: CGRect?) -> CGRect {
    if let span {
      return span.insetBy(dx: -Self.pillInset, dy: 0)
    }
    let width = min(bounds.width - 2 * Self.padding, hint.frame.width + 2 * Self.padding)
    return CGRect(
      x: (bounds.width - width) / 2, y: Self.pillBottom, width: width, height: Self.pillHeight)
  }

  private func layoutIcons(animated: Bool) {
    hint.isHidden = !entries.isEmpty || gapIndex != nil
    hint.sizeToFit()
    let placement = frames(gap: gapIndex)
    let layout = placement.frames
    let pillTarget = pillFrame(span: placement.span)
    hint.frame.origin = NSPoint(
      x: pillTarget.midX - hint.frame.width / 2, y: pillTarget.midY - hint.frame.height / 2)
    let row = remaining
    let lifted = liftedID
    let fresh = freshIDs
    freshIDs = []
    // Une case levée n'est plus dans la rangée : le curseur la porte, sa place est fermée.
    if let lifted { tiles[lifted]?.alphaValue = 0 }
    for (index, entry) in row.enumerated() where index < layout.count {
      guard let tile = tiles[entry.id], fresh.contains(entry.id) else { continue }
      tile.frame = layout[index]
      tile.alphaValue = 0
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated && OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
      if animated { pill.animator().frame = pillTarget } else { pill.frame = pillTarget }
      for (index, entry) in row.enumerated() where index < layout.count {
        guard let tile = tiles[entry.id] else { continue }
        if animated { tile.animator().frame = layout[index] } else { tile.frame = layout[index] }
        if animated { tile.animator().alphaValue = 1 } else { tile.alphaValue = 1 }
      }
    }
  }

  // MARK: - Dépôt

  private func dropped(from pasteboard: NSPasteboard) -> Dropped? {
    if let widget = DockWidgetDrag.payload(from: pasteboard),
      DockWidgetRegistry.kind(for: widget.kind) != nil
    {
      return .widget(widget)
    }
    return DockAppDrag.app(fromAny: pasteboard).map(Dropped.app)
  }

  /// L'identifiant de la case de la maquette que ce glisser représente, s'il en est une.
  private func presentID(of dropped: Dropped) -> String? {
    switch dropped {
    case .app(let app):
      return apps.contains { $0.bundleID == app.bundleID } ? app.bundleID : nil
    case .widget(let payload):
      guard let id = payload.placementID, widgets.contains(where: { $0.id == id }) else {
        return nil
      }
      return id
    }
  }

  /// L'indice d'insertion : le nombre de cases de la rangée (sans la case levée) dont le centre
  /// est à gauche du curseur.
  private func insertionIndex(for sender: NSDraggingInfo) -> Int {
    let x = convert(sender.draggingLocation, from: nil).x
    return frames(gap: nil).frames.filter { $0.midX < x }.count
  }

  private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    // Ni une appli ni un widget connu : rien à déposer ici.
    guard let dropped = dropped(from: sender.draggingPasteboard) else {
      clearGap()
      return []
    }
    // Une case déjà présente qui nous est amenée d'ailleurs se range comme une icône levée.
    if internalDragID == nil, externalLiftID == nil, let id = presentID(of: dropped) {
      externalLiftID = id
      gapIndex = nil
    }
    let index = insertionIndex(for: sender)
    if index != gapIndex {
      gapIndex = index
      layoutIcons(animated: true)
    }
    return operation(for: sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { clearGap() }
  override func draggingEnded(_ sender: NSDraggingInfo) { clearGap() }

  /// Le curseur a quitté la maquette : l'emplacement se referme. Une case glissée d'ici reste
  /// levée (sa place reste fermée) jusqu'à la fin du glisser.
  private func clearGap() {
    guard gapIndex != nil || externalLiftID != nil else { return }
    gapIndex = nil
    externalLiftID = nil
    layoutIcons(animated: true)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let dropped = dropped(from: sender.draggingPasteboard) else { return false }
    let index = insertionIndex(for: sender)
    let lifted = presentID(of: dropped)
    // La case se pose d'abord dans son emplacement : le nouvel ordre ne la fait pas bouger.
    if let lifted, let tile = tiles[lifted], let slot = frames(gap: index).gapFrame {
      tile.frame = slot
      tile.alphaValue = 1
    }
    gapIndex = nil
    internalDragID = nil
    externalLiftID = nil
    switch dropped {
    case .app(let app):
      if let lifted { onMove?(lifted, index) } else { onInsertApp?(app, index) }
    case .widget(let payload):
      if let lifted { onMove?(lifted, index) } else { onInsertWidget?(payload.kind, index) }
    }
    layoutIcons(animated: true)
    return true
  }
}
