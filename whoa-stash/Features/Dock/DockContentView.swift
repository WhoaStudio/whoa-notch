import AppKit

/// Une icône du dock : l'icône de l'appli, un point dessous si elle tourne, un globe si c'est
/// une web app. Le clic est traité au relâchement, dans la vue.
final class DockIconView: NSView, NSDraggingSource {

  /// Espace entre le bas de la vue (le point) et le bas de l'icône.
  static let dotGap: CGFloat = 8
  private static let dotSize: CGFloat = 4

  var onClick: (() -> Void)?
  var onContextMenu: ((NSEvent) -> Void)?
  /// Appelé quand l'icône est lâchée hors du dock : l'appli doit en sortir.
  var onDragOut: ((NSPoint) -> Void)?
  private(set) var dragApp: DockPinnedApp?
  private var didDrag = false
  private let imageView = NSImageView()
  private let dot = NSView()
  private let badge = NSView()
  private let globe = NSImageView()
  /// Fond discret derrière l'icône (« Tile backgrounds & borders »), caché par défaut.
  private let tile = CALayer()
  private var tileCornerRatio: CGFloat = 0.22

  /// « Tile backgrounds & borders » et « App Icon Style » : fond derrière l'icône, icône en niveaux de gris.
  func setStyle(tiles: Bool, grayscale: Bool, cornerRatio: CGFloat) {
    tile.isHidden = !tiles
    tile.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    tile.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    tile.borderWidth = 1
    tileCornerRatio = cornerRatio
    imageView.contentFilters = grayscale ? [Self.grayscaleFilter()] : []
    needsLayout = true
  }

  private static func grayscaleFilter() -> CIFilter {
    let filter = CIFilter(name: "CIColorControls") ?? CIFilter()
    filter.setValue(0, forKey: kCIInputSaturationKey)
    return filter
  }

  /// Teinte du point « en cours » : celle du thème du dock.
  func setInk(_ ink: NSColor) {
    dot.layer?.backgroundColor = ink.withAlphaComponent(0.65).cgColor
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    tile.isHidden = true
    layer?.addSublayer(tile)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(imageView)

    dot.wantsLayer = true
    dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
    dot.layer?.cornerRadius = Self.dotSize / 2
    addSubview(dot)

    badge.wantsLayer = true
    badge.layer?.backgroundColor = NSColor.white.cgColor
    badge.layer?.borderWidth = 1.5
    badge.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
    addSubview(badge)
    globe.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web app")
    globe.contentTintColor = .black
    badge.addSubview(globe)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func apply(_ item: DockItem) {
    // Les chemins du système (Safari…) passent par des liens : l'icône d'un lien porte la flèche d'alias.
    imageView.image = NSWorkspace.shared.icon(
      forFile: URL(fileURLWithPath: item.path).resolvingSymlinksInPath().path)
    toolTip = item.name
    dragApp = DockPinnedApp(bundleID: item.bundleID, path: item.path)
    dot.isHidden = !item.isRunning
    badge.isHidden = !item.isWebApp
    needsLayout = true
  }

  /// Rebondit tant que l'appli se lance.
  func setBouncing(_ bouncing: Bool) {
    guard let layer else { return }
    if !bouncing || !OverlayAnimation.allowsMotion {
      layer.removeAnimation(forKey: "bounce")
    } else if layer.animation(forKey: "bounce") == nil {
      let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
      animation.values = [0, bounds.width * 0.45, 0, bounds.width * 0.22, 0, 0]
      animation.keyTimes = [0, 0.25, 0.5, 0.7, 0.85, 1]
      animation.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
        CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
        CAMediaTimingFunction(name: .linear),
      ]
      animation.duration = 1.1
      animation.repeatCount = .infinity
      layer.add(animation, forKey: "bounce")
    }
  }

  override func layout() {
    super.layout()
    let size = bounds.width
    imageView.frame = NSRect(x: 0, y: Self.dotGap, width: size, height: size)
    tile.frame = imageView.frame
    tile.cornerRadius = size * tileCornerRatio
    dot.frame = NSRect(
      x: (size - Self.dotSize) / 2, y: 0, width: Self.dotSize, height: Self.dotSize)
    let badgeSize = max(14, size * 0.38)
    badge.frame = NSRect(
      x: size - badgeSize + 4, y: Self.dotGap - 4, width: badgeSize, height: badgeSize)
    badge.layer?.cornerRadius = badgeSize / 2
    globe.frame = badge.bounds.insetBy(dx: badgeSize * 0.15, dy: badgeSize * 0.15)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { didDrag = false }

  /// Saisie de l'icône : réorganiser le dock, ou la sortir pour l'y retirer.
  override func mouseDragged(with event: NSEvent) {
    guard !didDrag, let app = dragApp, let image = imageView.image else { return }
    didDrag = true
    layer?.removeAnimation(forKey: "bounce")
    let item = DockAppDrag.item(for: app, image: image, size: imageView.frame.width)
    item.draggingFrame = imageView.frame
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
    if operation.isEmpty { onDragOut?(screenPoint) }
  }

  override func mouseUp(with event: NSEvent) {
    if !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) {
      ButtonSound.shared.playClick()
      onClick?()
    }
  }

  override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }
}

extension NSColor {
  /// `#RRGGBB` → couleur sRGB ; gris moyen si le texte est illisible.
  convenience init(hex: String) {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
      self.init(white: 0.4, alpha: 1)
      return
    }
    self.init(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  var hexString: String {
    guard let rgb = usingColorSpace(.sRGB) else { return "#5A5A60" }
    return String(
      format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
      Int((rgb.greenComponent * 255).rounded()),
      Int((rgb.blueComponent * 255).rounded()))
  }
}

/// Une zone cliquable du dock : le clic est traité au relâchement.
class DockButtonView: NSView {
  var onClick: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) {
      ButtonSound.shared.playClick()
      onClick?()
    }
  }
}

/// Le dossier des applis ouvertes qui ne sont pas dans le profil actif : leurs icônes en miniature,
/// en grille de deux comme un dossier d'iPhone, posées sur sa propre capsule noire.
final class DockFolderView: NSView {

  private var thumbnails: [NSImageView] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func apply(items: [DockItem]) {
    let shown = Array(items.prefix(4))
    while thumbnails.count < shown.count {
      let view = NSImageView()
      view.imageScaling = .scaleProportionallyUpOrDown
      addSubview(view)
      thumbnails.append(view)
    }
    for (index, view) in thumbnails.enumerated() {
      view.isHidden = index >= shown.count
      if index < shown.count {
        view.image = NSWorkspace.shared.icon(
          forFile: URL(fileURLWithPath: shown[index].path).resolvingSymlinksInPath().path)
      }
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    // Quatre au plus, en deux par deux : le dossier garde une forme de carré.
    let gap = bounds.width * 0.08
    let side = (bounds.width - gap) / 2
    for (index, view) in thumbnails.enumerated() {
      let column = CGFloat(index % 2)
      let row = CGFloat(index / 2)
      view.frame = NSRect(
        x: column * (side + gap), y: bounds.height - side - row * (side + gap), width: side,
        height: side)
    }
  }
}

/// Une appli dans le panneau du dossier : son icône cliquable et son nom dessous.
private final class DockPopoverCellView: NSView {
  let iconView = DockIconView()
  private let label = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    label.font = .systemFont(ofSize: 10)
    label.textColor = NSColor.white.withAlphaComponent(0.75)
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    addSubview(iconView)
    addSubview(label)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func setInk(_ ink: NSColor) {
    iconView.setInk(ink)
    label.textColor = ink.withAlphaComponent(0.75)
  }

  func apply(_ item: DockItem) {
    iconView.apply(item)
    label.stringValue = item.name
  }

  func place(iconSize: CGFloat) {
    label.frame = NSRect(x: 2, y: 0, width: bounds.width - 4, height: 14)
    iconView.frame = NSRect(
      x: (bounds.width - iconSize) / 2, y: 16, width: iconSize,
      height: iconSize + DockIconView.dotGap)
  }
}

/// Contenu du panneau du dock : capsule de la couleur de l'encoche, groupe de gauche (crayon,
/// profils, bulle), séparateur, puis les icônes. Les vues sont créées une fois et
/// réutilisées d'une mise à jour à l'autre.
///
/// Les cotes sont données pour une icône de 52 pt et mises à l'échelle sur la taille d'icône du
/// Dock macOS. La fenêtre est plus grande que la capsule : elle réserve la place où les icônes
/// s'agrandissent au survol.
final class DockContentView: NSView {

  private static let designIconSize: CGFloat = 52
  static let iconTileCornerRatio: CGFloat = 0.18

  var onActivate: ((DockItem) -> Void)?
  var onContextMenu: ((DockItem, DockIconView, NSEvent) -> Void)?
  /// Une appli déposée dans le dock (glissée d'ici ou du Finder) à l'indice donné des épinglées.
  var onPlaceApp: ((DockPinnedApp, Int) -> Void)?
  /// Une icône épinglée lâchée hors du dock : elle en sort.
  var onRemoveApp: ((DockItem, NSPoint) -> Void)?
  /// Les widgets du dock après un dépôt ou un retrait, chacun avec sa position dans la rangée.
  var onWidgetsChanged: (([DockWidgetPlacement]) -> Void)?
  /// Clic droit sur un widget (son identifiant) ou sur le fond du dock.
  var onWidgetContextMenu: ((String, NSView, NSEvent) -> Void)?
  var onBackgroundContextMenu: ((NSEvent) -> Void)?

  private(set) var dockLook = DockAppearance()
  private(set) var theme = DockTheme.dark
  private let backdrop = DockSurfaceView()
  /// La capsule du dossier : collée à celle du dock, de la même couleur.
  private let folderBackdrop = DockSurfaceView()
  private var iconViews: [String: DockIconView] = [:]
  private var items: [DockItem] = []
  private var overflow: [DockItem] = []
  private var widgets: [DockWidgetPlacement] = []
  private var widgetViews: [String: DockWidgetHostView] = [:]
  /// La rangée d'icônes : applis et widgets, dans l'ordre d'affichage.
  private var row: [DockRowEntry] = []
  private let folderView = DockFolderView()
  private let popover = DockSurfaceView()
  private var popoverCells: [String: DockPopoverCellView] = [:]
  private(set) var isExpanded = false
  private var collapseTask: Task<Void, Never>?
  private var bouncing: Set<String> = []
  private var hasLaidOut = false
  /// Pendant un glisser au-dessus du dock : l'emplacement vide où l'appli va tomber.
  private var gapIndex: Int?

  // Agrandissement : le curseur et le degré d'agrandissement sont lissés image par image, pour
  // que l'entrée et la sortie glissent au lieu de sauter.
  private var hoverX: CGFloat?
  private var smoothX: CGFloat?
  private var magnify: CGFloat = 0
  private var displayLink: CADisplayLink?
  /// Léger agrandissement du dossier sous le curseur (0...1), lissé comme celui des icônes.
  private var folderMagnify: CGFloat = 0
  private var folderTarget: CGFloat = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true

    // Même fond que le panneau de l'encoche (`OverlayPalette.panelBackground`).
    backdrop.apply(theme: theme)
    addSubview(backdrop)
    folderBackdrop.apply(theme: theme)
    folderBackdrop.isHidden = true
    addSubview(folderBackdrop)

    addSubview(folderView)
    folderView.isHidden = true
    popover.apply(theme: theme)
    popover.isHidden = true
    addSubview(popover)
    applyScaledStyle()
    // Le vrai Dock suit le système : la teinte du verre aussi, sans relancer l'app. Le dock vit
    // aussi longtemps que l'app (fenêtre unique), l'observateur n'est donc jamais retiré.
    DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshInk() }
    }
    registerForDraggedTypes([.dockApp, .dockWidget, .fileURL])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  // MARK: - Cotes

  /// Les cotes sont celles d'un dock réel : peu d'air autour des icônes, capsule serrée.
  private var k: CGFloat { dockLook.iconSize / Self.designIconSize }
  private var sidePadding: CGFloat { 12 * k }
  private var iconGap: CGFloat { dockLook.style.widgetSpacing * k }
  /// Hauteur dont les icônes agrandies dépassent de la capsule.
  var magnificationReserve: CGFloat { growth }
  private var growth: CGFloat {
    dockLook.magnification ? dockLook.magnifiedSize - dockLook.iconSize : 0
  }
  private var iconRowBottom: CGFloat { 2 }
  private var iconTopPadding: CGFloat { 6 }

  /// Hauteur de la capsule : icône, point dessous, un peu d'air au-dessus.
  var capsuleHeight: CGFloat {
    iconRowBottom + DockIconView.dotGap + dockLook.iconSize + iconTopPadding
  }
  /// Hauteur de la fenêtre : la capsule plus la place de l'agrandissement.
  var panelHeight: CGFloat {
    capsuleHeight + max(growth, overflow.isEmpty ? 0 : popoverSize.height + 8)
  }

  // Panneau du dossier : une grille de cellules (icône + nom), cinq par rangée au plus.
  private var popoverCellSize: NSSize {
    NSSize(width: dockLook.iconSize + 22, height: dockLook.iconSize + DockIconView.dotGap + 16)
  }
  private var popoverColumns: Int { max(1, min(overflow.count, 5)) }
  private var popoverSize: NSSize {
    guard !overflow.isEmpty else { return .zero }
    let rows = (overflow.count + popoverColumns - 1) / popoverColumns
    return NSSize(
      width: CGFloat(popoverColumns) * popoverCellSize.width + 24,
      height: CGFloat(rows) * popoverCellSize.height + 24)
  }

  /// Cadre du panneau ouvert, dans la fenêtre ; `nil` quand il est fermé.
  var expandedPopoverRect: NSRect? { isExpanded ? popover.frame : nil }

  private func contentWidth(sizes: [CGFloat]) -> CGFloat {
    let icons = sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * iconGap
    return sidePadding * 2 + icons
  }

  /// La capsule du dossier : l'icône du dossier entourée du même air que celles du dock.
  private var folderCapsuleWidth: CGFloat { dockLook.iconSize + 20 * k }
  private var folderGap: CGFloat { 8 * k }
  /// Place que le dossier ajoute à droite du dock.
  private var folderExtra: CGFloat { overflow.isEmpty ? 0 : folderGap + folderCapsuleWidth }

  /// Largeur de la fenêtre pour `count` icônes : le contenu au repos plus la place de la
  /// croissance des icônes agrandies.
  func panelWidth(forIconCount count: Int) -> CGFloat {
    max(
      contentWidth(sizes: Array(repeating: dockLook.iconSize, count: count)) + folderExtra + growth
        * 3 + dockLook.iconSize + iconGap,
      popoverSize.width + 16)
  }

  /// Rectangle de la capsule dans la fenêtre — ce que le survol doit toucher pour révéler le dock.
  var capsuleRect: NSRect {
    overflow.isEmpty ? backdrop.frame : backdrop.frame.union(folderBackdrop.frame)
  }

  // MARK: - Mise à jour

  func apply(theme newTheme: DockTheme) {
    theme = newTheme
    for surface in [backdrop, folderBackdrop, popover] {
      surface.apply(theme: newTheme, opaque: dockLook.style.reduceTransparency)
    }
    refreshInk()
  }

  /// Icônes et widgets selon le style : fond des icônes, niveaux de gris, widgets monochromes.
  private func applyItemStyle() {
    let style = dockLook.style
    for icon in iconViews.values {
      icon.setStyle(
        tiles: style.tileBackgrounds, grayscale: style.grayscaleIcons,
        cornerRatio: Self.iconTileCornerRatio)
    }
    for widget in widgetViews.values {
      widget.contentFilters = style.monochromeWidgets ? [Self.monochromeFilter()] : []
    }
  }

  private static func monochromeFilter() -> CIFilter {
    let filter = CIFilter(name: "CIColorControls") ?? CIFilter()
    filter.setValue(0, forKey: kCIInputSaturationKey)
    return filter
  }

  /// Reteint ce qui se dessine sur le fond (points, noms) selon le thème.
  private func refreshInk() {
    let ink = theme.ink
    iconViews.values.forEach { $0.setInk(ink) }
    popoverCells.values.forEach { $0.setInk(ink) }
  }

  func apply(appearance newAppearance: DockAppearance) {
    guard newAppearance != dockLook else { return }
    dockLook = newAppearance
    applyScaledStyle()
    needsLayout = true
  }

  private func applyScaledStyle() {
    backdrop.cornerRadius = dockLook.style.cornerRadius * k
    folderBackdrop.cornerRadius = dockLook.style.cornerRadius * k
    backdrop.shadow = dockLook.style.shadow ? Self.dockShadow(scale: k) : nil
    for surface in [backdrop, folderBackdrop, popover] {
      surface.apply(theme: theme, opaque: dockLook.style.reduceTransparency)
    }
    applyItemStyle()
  }

  private static func dockShadow(scale: CGFloat) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 12 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -4 * scale)
    return shadow
  }

  private func item(withID id: String) -> DockItem? {
    items.first { $0.id == id } ?? overflow.first { $0.id == id }
  }

  func apply(items newItems: [DockItem], overflow newOverflow: [DockItem]) {
    let ids = Set(newItems.map(\.id))
    for (id, view) in iconViews where !ids.contains(id) {
      iconViews[id] = nil
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration =
            hasLaidOut && OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
          view.animator().alphaValue = 0
        },
        completionHandler: {
          MainActor.assumeIsolated { view.removeFromSuperview() }
        })
    }
    for item in newItems {
      let isNew = iconViews[item.id] == nil
      let view = iconViews[item.id] ?? makeIconView(for: item.id)
      view.apply(item)
      if isNew && hasLaidOut { view.alphaValue = 0 }
    }
    items = newItems
    rebuildRow()
    syncBouncing()
    applyOverflow(newOverflow)
  }

  /// Nombre de cases de la rangée (applis et widgets) : ce qui dimensionne la fenêtre.
  var rowCount: Int { row.count }

  private func rebuildRow() {
    row = DockRow.entries(items: items, widgets: widgets)
  }

  /// Pose les widgets du dock. Un type que le registre ne connaît plus est ignoré.
  func apply(widgets newWidgets: [DockWidgetPlacement]) {
    let known = newWidgets.filter { DockWidgetRegistry.kind(for: $0.kind) != nil }
    let ids = Set(known.map(\.id))
    for (id, host) in widgetViews where !ids.contains(id) {
      host.tearDown()
      widgetViews[id] = nil
    }
    for placement in known where widgetViews[placement.id] == nil {
      guard let kind = DockWidgetRegistry.kind(for: placement.kind) else { continue }
      let host = DockWidgetHostView(placement: placement, widget: kind.make())
      host.onDragEnded = { [weak self] point, operation in
        self?.widgetDragEnded(id: placement.id, at: point, operation: operation)
      }
      host.onContextMenu = { [weak self, weak host] event in
        guard let host else { return }
        self?.onWidgetContextMenu?(placement.id, host, event)
      }
      if hasLaidOut { host.alphaValue = 0 }
      addSubview(host)
      widgetViews[placement.id] = host
    }
    widgets = known
    rebuildRow()
    needsLayout = true
  }

  /// Retire un widget de la rangée (menu contextuel).
  func removeWidget(id: String) {
    onWidgetsChanged?(DockRow.placements(removing: id, from: row))
  }

  override func rightMouseDown(with event: NSEvent) { onBackgroundContextMenu?(event) }

  /// Un widget lâché sans qu'un dépôt l'accepte sort du dock s'il est tombé hors de la capsule ;
  /// refusé au-dessus du dock (les profils), il reste où il était.
  private func widgetDragEnded(id: String, at screenPoint: NSPoint, operation: NSDragOperation) {
    guard operation.isEmpty, let window else { return }
    let local = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
    guard !capsuleRect.contains(local) else { return }
    onWidgetsChanged?(DockRow.placements(removing: id, from: row))
  }

  private func applyOverflow(_ newOverflow: [DockItem]) {
    overflow = newOverflow
    folderView.isHidden = overflow.isEmpty
    folderBackdrop.isHidden = overflow.isEmpty
    folderView.apply(items: overflow)
    let ids = Set(overflow.map(\.id))
    for (id, cell) in popoverCells where !ids.contains(id) {
      cell.removeFromSuperview()
      popoverCells[id] = nil
    }
    for item in overflow {
      let cell =
        popoverCells[item.id]
        ?? {
          let created = DockPopoverCellView()
          configure(created.iconView, id: item.id)
          created.setInk(theme.ink)
          popover.addSubview(created)
          popoverCells[item.id] = created
          return created
        }()
      cell.apply(item)
    }
    if overflow.isEmpty && isExpanded {
      isExpanded = false
      popover.isHidden = true
    }
  }

  private func makeIconView(for id: String) -> DockIconView {
    let view = DockIconView()
    configure(view, id: id)
    view.setInk(theme.ink)
    addSubview(view)
    iconViews[id] = view
    return view
  }

  private func configure(_ view: DockIconView, id: String) {
    view.onClick = { [weak self] in
      guard let self, let item = self.item(withID: id) else { return }
      self.onActivate?(item)
    }
    view.onDragOut = { [weak self] point in
      guard let self, let item = self.item(withID: id), item.isPinned else { return }
      self.onRemoveApp?(item, point)
    }
    view.onContextMenu = { [weak self, weak view] event in
      guard let self, let view, let item = self.item(withID: id) else { return }
      self.onContextMenu?(item, view, event)
    }
  }

  func setBouncing(_ ids: Set<String>) {
    bouncing = ids
    syncBouncing()
  }

  private func syncBouncing() {
    for (id, view) in iconViews { view.setBouncing(bouncing.contains(id)) }
  }

  // MARK: - Agrandissement au survol

  /// Position du curseur dans la vue, ou `nil` hors du dock. C'est le contrôleur qui la fournit, à
  /// partir de la position globale du curseur : les marges transparentes des icônes ne livrent
  /// pas d'événements de souris, et une zone de survol propre à la vue clignoterait.
  func setHover(_ point: NSPoint?) {
    updateFolder(with: point)
    // Les icônes ne s'agrandissent que sous le curseur qui les survole : ni au-dessus du panneau du
    // dossier, ni sur le dossier lui-même, ni au-delà de la rangée — sinon la dernière icône gonflait
    // quand on visait le dossier, jusque sur le panneau ouvert.
    guard let point else {
      setFolderTarget(0)
      setMagnifyX(nil)
      return
    }
    let overFolder =
      !overflow.isEmpty && folderBackdrop.frame.insetBy(dx: -4, dy: -6).contains(point)
    setFolderTarget(overFolder && dockLook.magnification ? 1 : 0)
    let overPopover = isExpanded && popover.frame.insetBy(dx: -8, dy: -8).contains(point)
    let rowStart = restRowStart()
    let rowEnd = rowStart + CGFloat(items.count) * (dockLook.iconSize + iconGap)
    let inRow = point.x >= rowStart - iconGap && point.x <= rowEnd
    setMagnifyX(overFolder || overPopover || !inRow ? nil : point.x)
  }

  private func setMagnifyX(_ x: CGFloat?) {
    guard dockLook.magnification || hoverX != nil else { return }
    hoverX = x
    if let x, smoothX == nil { smoothX = x }
    startTicking()
  }

  private func setFolderTarget(_ target: CGFloat) {
    guard target != folderTarget else { return }
    folderTarget = target
    startTicking()
  }

  private func startTicking() {
    guard displayLink == nil else { return }
    let link = displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  // MARK: - Dossier

  /// Le panneau s'ouvre dès que le curseur touche le dossier et reste ouvert tant qu'il est sur le
  /// dossier ou sur lui ; il se referme un instant après — le temps de traverser l'espace entre les deux.
  private func updateFolder(with point: NSPoint?) {
    guard !overflow.isEmpty, let point else {
      scheduleCollapse()
      return
    }
    let overFolder = folderBackdrop.frame.insetBy(dx: -4, dy: -6).contains(point)
    let overPopover = isExpanded && popover.frame.insetBy(dx: -8, dy: -8).contains(point)
    if overFolder || overPopover {
      collapseTask?.cancel()
      collapseTask = nil
      if !isExpanded { expand() }
    } else {
      scheduleCollapse()
    }
  }

  private func expand() {
    isExpanded = true
    layoutPopover()
    if popover.isHidden, let layer = popover.layer {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.opacity = 0
      layer.setValue(CGFloat(-10), forKeyPath: "transform.translation.y")
      CATransaction.commit()
    }
    popover.isHidden = false
    popover.layer?.springAnimate(keyPath: "transform.translation.y", to: CGFloat(0))
    popover.layer?.springAnimate(keyPath: "opacity", to: Float(1))
  }

  private func scheduleCollapse() {
    guard isExpanded, collapseTask == nil else { return }
    collapseTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, let self else { return }
      self.collapseTask = nil
      self.isExpanded = false
      self.popover.layer?.springAnimate(keyPath: "transform.translation.y", to: CGFloat(-10))
      self.popover.layer?.springAnimate(keyPath: "opacity", to: Float(0)) { [weak self] in
        guard let self, !self.isExpanded else { return }
        self.popover.isHidden = true
      }
    }
  }

  private func layoutPopover() {
    let size = popoverSize
    let target = NSRect(
      x: max(4, min(folderView.frame.maxX + 6 - size.width, bounds.width - size.width - 4)),
      y: capsuleHeight + 8, width: size.width, height: size.height)
    popover.frame = target
    popover.cornerRadius = 20 * k
    let cell = popoverCellSize
    let rows = (overflow.count + popoverColumns - 1) / popoverColumns
    for (index, item) in overflow.enumerated() {
      guard let view = popoverCells[item.id] else { continue }
      view.frame = NSRect(
        x: 12 + CGFloat(index % popoverColumns) * cell.width,
        y: 12 + CGFloat(rows - 1 - index / popoverColumns) * cell.height, width: cell.width,
        height: cell.height)
      view.place(iconSize: dockLook.iconSize)
    }
  }

  @objc private func tick(_ link: CADisplayLink) {
    let dt = max(0.001, link.targetTimestamp - link.timestamp)
    let target: CGFloat = hoverX == nil ? 0 : 1
    magnify += (target - magnify) * CGFloat(1 - exp(-dt * 16))
    if let hoverX, let current = smoothX {
      smoothX = current + (hoverX - current) * CGFloat(1 - exp(-dt * 40))
    }
    folderMagnify += (folderTarget - folderMagnify) * CGFloat(1 - exp(-dt * 16))
    let folderSettled = abs(folderTarget - folderMagnify) < 0.003
    let settled =
      abs(target - magnify) < 0.003 && folderSettled
      && (hoverX == nil || abs((smoothX ?? 0) - (hoverX ?? 0)) < 0.2)
    if settled {
      folderMagnify = folderTarget
      magnify = target
      if let hoverX { smoothX = hoverX } else { smoothX = nil }
    }
    layoutIcons(animated: false)
    if settled {
      link.invalidate()
      displayLink = nil
    }
  }

  /// Début de la rangée d'icônes quand tout est au repos.
  private func restRowStart() -> CGFloat {
    let restWidth =
      contentWidth(sizes: Array(repeating: dockLook.iconSize, count: row.count)) + folderExtra
    let restOrigin = (bounds.width - restWidth) / 2
    return restOrigin + sidePadding
  }

  /// Taille de chaque icône : cosinus sur 2,5 pas autour du curseur, calculé sur la disposition
  /// au repos pour que le résultat ne dépende pas de l'agrandissement déjà appliqué.
  private func iconSizes() -> [CGFloat] {
    let base = dockLook.iconSize
    guard dockLook.magnification, magnify > 0, gapIndex == nil, let cursor = smoothX else {
      return Array(repeating: base, count: row.count)
    }
    let first = restRowStart()
    let pitch = base + iconGap
    let radius = pitch * 2.5
    return row.indices.map { index in
      let center = first + CGFloat(index) * pitch + base / 2
      let t = min(1, abs(center - cursor) / radius)
      return base + (dockLook.magnifiedSize - base) * 0.5 * (1 + cos(.pi * t)) * magnify
    }
  }

  /// Décalage horizontal qui garde sous le curseur le point de la rangée qu'il visait au repos :
  /// sans lui, la rangée s'élargit autour de son centre et l'icône agrandie glisse hors du curseur.
  private func anchorShift(sizes: [CGFloat], capsuleX: CGFloat) -> CGFloat {
    guard let cursor = smoothX, dockLook.magnification, magnify > 0, gapIndex == nil, !row.isEmpty
    else { return 0 }
    let base = dockLook.iconSize
    let pitch = base + iconGap
    let rel = (cursor - restRowStart()) / pitch
    guard rel >= 0, rel < CGFloat(row.count) else { return 0 }
    let index = Int(rel)
    let offset = (rel - CGFloat(index)) * pitch
    let within = offset <= base ? offset / base * sizes[index] : sizes[index] + (offset - base)
    let before = sizes[..<index].reduce(0, +) + CGFloat(index) * iconGap
    let rowStart = capsuleX + sidePadding
    return cursor - (rowStart + before + within)
  }

  // MARK: - Disposition

  override func layout() {
    super.layout()
    layoutIcons(animated: false)
  }

  /// Replace tout en une fois. `shiftingBy` compense un déplacement de la fenêtre : les vues partent
  /// de leur place à l'écran d'avant pour glisser vers la nouvelle, au lieu de sauter.
  func relayout(shiftingBy dx: CGFloat = 0, animated: Bool) {
    let animate = animated && hasLaidOut
    if animate && dx != 0 {
      for view in subviews where view.alphaValue > 0 { view.frame.origin.x += dx }
    }
    layoutIcons(animated: animate)
  }

  private func layoutIcons(animated: Bool) {
    applyItemStyle()
    var sizes = iconSizes()
    // Un glisser en cours : un emplacement vide s'ouvre là où l'appli va tomber.
    let slot = gapIndex.map { min($0, sizes.count) }
    if let slot { sizes.insert(dockLook.iconSize, at: slot) }
    let width = contentWidth(sizes: sizes)
    // Le dock et son dossier se centrent ensemble.
    let total = width + folderExtra
    var capsuleX = (bounds.width - total) / 2
    capsuleX += anchorShift(sizes: sizes, capsuleX: capsuleX)
    capsuleX = max(0, min(capsuleX, bounds.width - total))
    // La capsule colle au bas de la fenêtre : au-dessus d'elle, la réserve d'agrandissement.
    let capsule = NSRect(x: capsuleX, y: 0, width: width, height: capsuleHeight)
    let midY = iconRowBottom + DockIconView.dotGap + dockLook.iconSize / 2

    var frames: [(NSView, NSRect)] = [(backdrop, capsule)]
    var x = capsule.minX + sidePadding
    for index in sizes.indices {
      let size = sizes[index]
      defer { x += size + iconGap }
      if index == slot { continue }
      let itemIndex = (slot != nil && index > slot!) ? index - 1 : index
      guard row.indices.contains(itemIndex), let view = rowView(for: row[itemIndex]) else {
        continue
      }
      let frame = NSRect(x: x, y: iconRowBottom, width: size, height: size + DockIconView.dotGap)
      // Une icône qui arrive monte légèrement de sa position finale en apparaissant.
      if animated && view.alphaValue == 0 { view.frame = frame.offsetBy(dx: 0, dy: -12) }
      frames.append((view, frame))
    }
    if !overflow.isEmpty {
      let base = NSRect(
        x: capsule.maxX + folderGap, y: 0, width: folderCapsuleWidth, height: capsuleHeight)
      let inner = NSRect(
        x: base.minX + 10 * k, y: iconRowBottom + DockIconView.dotGap, width: dockLook.iconSize,
        height: dockLook.iconSize)
      // Léger agrandissement au survol, autour du bas-centre de la capsule : il s'élève comme une icône.
      let scale = 1 + 0.14 * folderMagnify
      let anchor = NSPoint(x: base.midX, y: 0)
      func scaled(_ rect: NSRect) -> NSRect {
        NSRect(
          x: anchor.x + (rect.minX - anchor.x) * scale,
          y: anchor.y + (rect.minY - anchor.y) * scale,
          width: rect.width * scale, height: rect.height * scale)
      }
      frames.append((folderBackdrop, scaled(base)))
      frames.append((folderView, scaled(inner)))
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated && OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = animated
      for (view, frame) in frames {
        if animated {
          view.animator().frame = frame
          if view is DockIconView || view is DockWidgetHostView { view.animator().alphaValue = 1 }
        } else {
          view.frame = frame
          if view is DockIconView && view.alphaValue == 0
            && iconViews.values.contains(where: { $0 === view })
          {
            view.alphaValue = 1
          }
          if view is DockWidgetHostView && view.alphaValue == 0 { view.alphaValue = 1 }
        }
      }
    }
    hasLaidOut = true
    if !overflow.isEmpty { layoutPopover() }
  }

  private func rowView(for entry: DockRowEntry) -> NSView? {
    switch entry {
    case .app(let item): iconViews[item.id]
    case .widget(let placement): widgetViews[placement.id]
    }
  }

  // MARK: - Dépôt d'applis et de widgets

  /// L'indice d'insertion dans la rangée sous l'abscisse `x` ; `nil` sur le groupe des profils.
  private func rowIndex(atX x: CGFloat) -> Int? {
    let first = restRowStart()
    return DockDropZone.rowIndex(
      x: x, profileEnd: -.infinity, rowStart: first, iconSize: dockLook.iconSize,
      pitch: dockLook.iconSize + iconGap, count: row.count)
  }

  /// Où un widget lâché à `x` irait : l'indice dans la rangée, ou `nil` sur les profils.
  func widgetDropIndex(atX x: CGFloat) -> Int? { rowIndex(atX: x) }

  /// Lâche un widget à l'abscisse `x` (repère de la vue). Faux, sans rien changer, sur les profils.
  @discardableResult
  func dropWidget(_ payload: DockWidgetDragPayload, atX x: CGFloat) -> Bool {
    guard DockWidgetRegistry.kind(for: payload.kind) != nil, let index = widgetDropIndex(atX: x)
    else { return false }
    let moved =
      payload.placementID.flatMap { id in widgets.first { $0.id == id } }
      ?? DockWidgetPlacement(kind: payload.kind, index: index)
    onWidgetsChanged?(DockRow.placements(placing: moved, at: index, in: row))
    return true
  }

  /// L'indice d'insertion d'une appli dans la rangée, sans dépasser la dernière épinglée — les
  /// applis seulement lancées restent après.
  private func appSlot(for sender: NSDraggingInfo) -> Int {
    let x = convert(sender.draggingLocation, from: nil).x
    let first = restRowStart()
    let pitch = dockLook.iconSize + iconGap
    let before = row.indices.filter { first + CGFloat($0) * pitch + dockLook.iconSize / 2 < x }
      .count
    return min(before, DockRow.lastAppDropPosition(in: row))
  }

  private func droppedApp(from pasteboard: NSPasteboard) -> DockPinnedApp? {
    if let app = DockAppDrag.app(from: pasteboard) { return app }
    // Une appli glissée depuis le Finder : un fichier `.app`.
    guard
      let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: {
        $0.pathExtension == "app"
      }),
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else { return nil }
    return DockPinnedApp(bundleID: bundleID, path: url.path)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let operation: NSDragOperation =
      sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    if let widget = DockWidgetDrag.payload(from: sender.draggingPasteboard) {
      guard DockWidgetRegistry.kind(for: widget.kind) != nil,
        let index = widgetDropIndex(atX: convert(sender.draggingLocation, from: nil).x)
      else {
        clearGap()
        return []
      }
      setGap(index)
      return operation
    }
    guard droppedApp(from: sender.draggingPasteboard) != nil else { return [] }
    setGap(appSlot(for: sender))
    return operation
  }

  private func setGap(_ index: Int) {
    guard index != gapIndex else { return }
    gapIndex = index
    layoutIcons(animated: true)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { clearGap() }
  override func draggingEnded(_ sender: NSDraggingInfo) { clearGap() }

  private func clearGap() {
    guard gapIndex != nil else { return }
    gapIndex = nil
    layoutIcons(animated: true)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    gapIndex = nil
    if let widget = DockWidgetDrag.payload(from: sender.draggingPasteboard) {
      let dropped = dropWidget(widget, atX: convert(sender.draggingLocation, from: nil).x)
      layoutIcons(animated: true)
      return dropped
    }
    guard let app = droppedApp(from: sender.draggingPasteboard) else { return false }
    let slot = appSlot(for: sender)
    onPlaceApp?(app, DockRow.pinnedIndex(beforeRowIndex: slot, in: row))
    return true
  }
}
