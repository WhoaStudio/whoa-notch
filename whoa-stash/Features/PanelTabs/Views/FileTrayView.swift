import AppKit
import OSLog
import QuickLookThumbnailing

/// Onglet Tray : une zone de dépôt qui retient les fichiers qu'on y lâche, rangés en grille de
/// vignettes — l'aperçu du fichier, son nom dessous — comme dans la vue en icônes du Finder.
///
/// La vue n'est qu'une lecture de `FileShelfStore` — c'est lui qui retient les fichiers, et donc
/// le bac survit au repli du panneau, au changement d'onglet et au relancement de l'app. Les
/// fichiers sont déplacés dans le dossier du bac, puis référencés par des signets.
///
/// La vue **ne s'enregistre pas** comme cible de dépôt : c'est le panneau tout entier qui la
/// porte (`NotchPanelContentView`), parce qu'un fichier se lâche sur l'encoche — en haut, là où
/// la silhouette repliée se voit — et pas dans le rectangle du bac, qui est tout en bas du
/// panneau déplié. Il n'y a donc toujours qu'une cible, simplement plus large que le bac : le
/// panneau lui confie ce qu'il reçoit (`canAccept(_:)` / `accept(_:)`).
///
/// Un fichier en ressort comme de n'importe quel bac du système : on le glisse vers le Finder ou
/// une autre app, et il ne quitte le bac qu'une fois le dépôt abouti (voir `FileTrayItemView`).
final class FileTrayView: NSView {

  private let emptyLabel = NSTextField(labelWithString: "Drop files here")
  private let dropHighlightLayer = CAShapeLayer()
  private var items: [FileTrayItemView] = []

  private let store: FileShelfStore
  /// `nonisolated(unsafe)` pour pouvoir être retiré depuis `deinit`, qui n'est pas isolé sur
  /// le main actor : le jeton n'est touché qu'à l'installation et à la destruction de la vue,
  /// toutes deux sur le main actor de fait.
  nonisolated(unsafe) private var storeObserver: NSObjectProtocol?

  private let tileSpacing: CGFloat = 8

  /// Cible actuellement survolée par un glisser, `nil` hors glisser. Tant qu'elle est non
  /// nulle, le bac montre ses deux zones : « Keep in tray » et AirDrop.
  private var dropTarget: FileTrayDropTarget?
  private var isDragActive = false
  private var isDragFromTray = false
  private let airDropZone = AirDropZoneView()
  private let keepIcon = NSImageView()
  /// Bouton « Transform », présent tant que le glisser est une image venue du bac : la lâcher
  /// dessus ouvre la vue Transform (voir `showsTransformTile`).
  private let transformTile = TransformDropTileView()
  private var showsTransformTile = false
  /// Fichiers cochés dans le bac : un clic sur une vignette la coche ou la décoche, et le menu
  /// contextuel (Copy, Open) porte sur toute la sélection.
  private var selection: Set<URL> = []
  /// Défilement de la grille quand elle dépasse le bac, et sa course maximale.
  private var scrollOffset: CGFloat = 0
  private var maxScrollOffset: CGFloat = 0

  private static let transformTileSize = NSSize(width: 96, height: 52)

  init(frame frameRect: NSRect = .zero, store: FileShelfStore = .shared) {
    self.store = store
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let storeObserver {
      NotificationCenter.default.removeObserver(storeObserver)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard maxScrollOffset > 0 else { return super.scrollWheel(with: event) }
    scrollOffset = min(max(0, scrollOffset - event.scrollingDeltaY), maxScrollOffset)
    needsLayout = true
  }

  private func setUp() {
    // Les vignettes qui débordent du bac sont rognées au bord, au lieu de sortir de la zone.
    layer?.masksToBounds = true

    // Liseré en tirets : il dit « on peut déposer ici » sans peser autant qu'un cadre plein,
    // et c'est lui qui s'allume quand un glisser survole la zone.
    dropHighlightLayer.fillColor = nil
    dropHighlightLayer.lineWidth = 1
    dropHighlightLayer.lineDashPattern = [4, 4]
    layer?.addSublayer(dropHighlightLayer)

    emptyLabel.isBezeled = false
    emptyLabel.drawsBackground = false
    emptyLabel.isEditable = false
    emptyLabel.isSelectable = false
    emptyLabel.alignment = .center
    emptyLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
    addSubview(emptyLabel)

    keepIcon.image = NSImage(
      systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Keep in tray")?
      .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
    keepIcon.imageScaling = .scaleNone
    keepIcon.isHidden = true
    addSubview(keepIcon)

    airDropZone.isHidden = true
    addSubview(airDropZone)

    transformTile.isHidden = true
    addSubview(transformTile)

    // Il y a une vue par écran, et elles vont et viennent avec les fenêtres : chacune suit
    // le bac partagé plutôt que d'être tenue par lui.
    storeObserver = NotificationCenter.default.addObserver(
      forName: FileShelfStore.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.rebuildRows() }
    }

    rebuildRows()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  private func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    // Gris au repos, blanc quand la zone est survolée : le bleu est réservé à AirDrop.
    emptyLabel.textColor = .gray
    keepIcon.contentTintColor = dropTarget == .keep ? .white : .gray
    dropHighlightLayer.strokeColor = (dropTarget == .keep ? NSColor.white : NSColor.gray).cgColor
    items.forEach { $0.applyPalette(palette) }
  }

  // MARK: - Dépôt

  /// Le glisser porte-t-il des fichiers ? Un glisser venu du bac lui-même n'est pas rangé à
  /// nouveau (`accept` le refuse) : il ne peut que partir en AirDrop.
  func canAccept(_ sender: any NSDraggingInfo) -> Bool {
    return sender.draggingPasteboard.canReadObject(
      forClasses: [NSURL.self], options: readingOptions)
  }

  /// Range dans le bac ce que le panneau vient de recevoir. Un fichier qui vient du bac y est
  /// déjà : le lâcher sur « garder » le laisse en place.
  func accept(_ sender: any NSDraggingInfo) -> Bool {
    if isFromTray(sender) { return true }
    guard
      canAccept(sender),
      let dropped = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: readingOptions
      ) as? [URL],
      !dropped.isEmpty
    else { return false }

    return !store.add(dropped).isEmpty
  }

  /// Montre les deux zones et allume celle que le glisser survole (`nil` : le glisser est
  /// parti, le bac reprend son aspect de repos). La cible du système reste tout le panneau ;
  /// ce sont ces zones qui disent où le fichier va tomber.
  ///
  /// `imageFormat` est le format de l'image glissée depuis le bac, `nil` pour tout le reste :
  /// seule une image du bac montre la rangée de conversion.
  func setDragActive(
    _ active: Bool,
    fromTray: Bool = false,
    hovered target: FileTrayDropTarget? = nil,
    imageFormat: ImageFormat? = nil
  ) {
    let showsTile = active && fromTray && imageFormat != nil
    guard
      active != isDragActive || fromTray != isDragFromTray || target != dropTarget
        || showsTile != showsTransformTile
    else { return }
    let appearing = active && !isDragActive
    isDragActive = active
    isDragFromTray = fromTray
    dropTarget = active ? target : nil
    showsTransformTile = showsTile
    transformTile.isHidden = !showsTile
    airDropZone.isHidden = !active
    keepIcon.isHidden = !active
    airDropZone.isHighlighted = dropTarget == .airDrop
    transformTile.isHighlighted = dropTarget == .transform
    keepIcon.alphaValue = dropTarget == .keep ? 1 : 0.6
    items.forEach { $0.isHidden = active }
    emptyLabel.isHidden = active || !store.isEmpty
    applyPalette()
    needsLayout = true
    if appearing {
      layoutSubtreeIfNeeded()
      airDropZone.playEntrance()
    }
  }

  /// Y a-t-il une rangée de conversion à montrer ? Le panneau grandit alors de
  /// `NotchPanelGeometry.trayConversionExtraHeight`.
  var hasConversionRow: Bool { showsTransformTile }

  /// Format de l'image que porte un glisser venu du bac, `nil` si le glisser vient d'ailleurs,
  /// porte plusieurs fichiers ou autre chose qu'une image jpg, jpeg, png ou heic.
  func imageFormat(of sender: any NSDraggingInfo) -> ImageFormat? {
    guard
      isFromTray(sender),
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: readingOptions) as? [URL],
      urls.count == 1
    else { return nil }
    return ImageFormat(url: urls[0])
  }

  /// Le fichier que porte un glisser venu du bac, pour l'ouvrir dans la vue Transform.
  func transformSource(_ sender: any NSDraggingInfo) -> URL? {
    guard
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: readingOptions) as? [URL],
      urls.count == 1, ImageFormat(url: urls[0]) != nil
    else { return nil }
    return urls[0]
  }

  /// Zone des deux grandes cibles : tout le bac, moins la rangée de conversion quand elle est là.
  private var zonesBounds: NSRect {
    guard hasConversionRow else { return bounds }
    let extra = NotchPanelGeometry.trayConversionExtraHeight
    return NSRect(
      x: bounds.minX, y: bounds.minY + extra, width: bounds.width,
      height: max(0, bounds.height - extra))
  }

  /// Le glisser vient-il d'une vignette du bac ? Il ne peut alors que partir en AirDrop.
  func isFromTray(_ sender: any NSDraggingInfo) -> Bool {
    sender.draggingSource is FileTrayItemView
  }

  /// Cible sous la position d'un glisser, donnée dans le repère de `view`.
  func dropTarget(for sender: any NSDraggingInfo, in view: NSView) -> FileTrayDropTarget {
    let point = convert(sender.draggingLocation, from: view)
    if showsTransformTile, transformTile.frame.contains(point) { return .transform }
    return FileTrayDropTarget.target(at: point, in: zonesBounds)
  }

  /// Envoie par AirDrop ce que le panneau vient de recevoir, sans le ranger dans le bac.
  func airDrop(_ sender: any NSDraggingInfo) -> Bool {
    guard
      canAccept(sender),
      let dropped = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: readingOptions
      ) as? [URL],
      !dropped.isEmpty,
      let service = NSSharingService(named: .sendViaAirDrop),
      service.canPerform(withItems: dropped)
    else {
      Log.sidePanel.error("AirDrop indisponible pour ce dépôt")
      return false
    }
    // L'app n'a pas d'icône du Dock : sans activation, le sélecteur s'ouvrirait derrière.
    NSApp.activate()
    service.perform(withItems: dropped)
    return true
  }

  private var readingOptions: [NSPasteboard.ReadingOptionKey: Any] {
    [.urlReadingFileURLsOnly: true]
  }

  private func toggleSelection(of url: URL) {
    if selection.contains(url) {
      selection.remove(url)
    } else {
      selection.insert(url)
    }
    items.forEach { $0.isSelected = selection.contains($0.url) }
  }

  /// Cible du menu contextuel : la sélection si la vignette cliquée en fait partie, sinon cette
  /// vignette seule — comme dans le Finder.
  private func urlsForMenu(on url: URL) -> [URL] {
    selection.contains(url) ? store.urls.filter(selection.contains) : [url]
  }

  private func rebuildRows() {
    let previousURLs = items.map(\.url)
    items.forEach { $0.removeFromSuperview() }
    selection.formIntersection(store.urls)
    items = store.urls.map { url in
      let item = FileTrayItemView(url: url, store: store)
      item.isSelected = selection.contains(url)
      item.onToggleSelection = { [weak self] in self?.toggleSelection(of: url) }
      item.urlsForMenu = { [weak self] in self?.urlsForMenu(on: url) ?? [url] }
      return item
    }
    items.forEach(addSubview)
    emptyLabel.isHidden = isDragActive || !store.isEmpty
    items.forEach { $0.isHidden = isDragActive }
    applyPalette()
    needsLayout = true
    if !isDragActive, window != nil, !isHiddenOrHasHiddenAncestor, previousURLs != store.urls {
      if items.isEmpty {
        emptyLabel.wantsLayer = true
        emptyLabel.layer?.springReveal()
      } else {
        for (index, item) in items.enumerated()
        where previousURLs.indices.contains(index) == false
          || previousURLs[index] != item.url
        {
          item.layer?.springReveal()
        }
      }
    }
  }

  override func layout() {
    super.layout()

    // Pendant un glisser, la moitié gauche est « Keep in tray », la droite est AirDrop.
    let gap: CGFloat = 6
    let zones = zonesBounds
    let keepFrame =
      isDragActive
      ? NSRect(
        x: zones.minX, y: zones.minY, width: zones.midX - gap / 2 - zones.minX, height: zones.height
      )
      : bounds
    airDropZone.frame = NSRect(
      x: zones.midX + gap / 2, y: zones.minY,
      width: zones.maxX - zones.midX - gap / 2, height: zones.height
    )

    // Bouton Transform : sous les deux zones, centré.
    let tileSize = Self.transformTileSize
    transformTile.frame = NSRect(
      x: bounds.midX - tileSize.width / 2, y: bounds.minY + 2, width: tileSize.width,
      height: tileSize.height)
    let iconSize = keepIcon.intrinsicContentSize
    keepIcon.frame = NSRect(
      x: keepFrame.midX - iconSize.width / 2, y: keepFrame.midY - iconSize.height / 2,
      width: iconSize.width, height: iconSize.height
    )

    dropHighlightLayer.frame = bounds
    dropHighlightLayer.path = CGPath(
      roundedRect: keepFrame.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: 10,
      cornerHeight: 10,
      transform: nil
    )

    let labelHeight = emptyLabel.intrinsicContentSize.height
    emptyLabel.frame = NSRect(
      x: bounds.minX,
      y: bounds.midY - labelHeight / 2,
      width: bounds.width,
      height: labelHeight
    )

    // Grille centrée, rangée par rangée : le nombre de colonnes suit la largeur, et une
    // rangée incomplète se centre d'elle-même plutôt que de coller à gauche.
    let tile = FileTrayItemView.tileSize
    let inset: CGFloat = 8
    let columns = 4
    // Quatre vignettes par rangée ; si le bac est trop étroit, elles rétrécissent plutôt que de sortir.
    let tileWidth = min(
      tile.width, (bounds.width - 2 * inset - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
    )
    let rowCount = (items.count + columns - 1) / columns
    let gridHeight = CGFloat(rowCount) * tile.height + CGFloat(max(0, rowCount - 1)) * tileSpacing

    // Quand la grille dépasse le bac, elle défile depuis le haut et les vignettes coupées sont
    // rognées au bord ; sinon elle reste centrée.
    maxScrollOffset = max(0, gridHeight - (bounds.height - 2 * inset))
    scrollOffset = min(max(0, scrollOffset), maxScrollOffset)
    let gridTop =
      maxScrollOffset > 0
      ? bounds.maxY - inset + scrollOffset
      : bounds.midY + gridHeight / 2

    for (position, item) in items.enumerated() {
      let row = position / columns
      let column = position % columns
      let inRow = min(columns, items.count - row * columns)
      let rowWidth = CGFloat(inRow) * tileWidth + CGFloat(inRow - 1) * tileSpacing
      item.frame = NSRect(
        x: bounds.midX - rowWidth / 2 + CGFloat(column) * (tileWidth + tileSpacing),
        y: gridTop - CGFloat(row + 1) * tile.height - CGFloat(row) * tileSpacing,
        width: tileWidth,
        height: tile.height
      )
    }
  }
}

// MARK: - Une vignette

/// Une vignette du bac : l'aperçu du fichier, et son nom dessous.
///
/// L'aperçu part de l'icône que le Finder donne au fichier — l'icône de dossier, ou celle du
/// type avec le badge de l'app par défaut —, puis passe à la vignette de contenu de QuickLook
/// (texte, JSON, image…) dès qu'elle est prête. Un fichier sans vignette garde son icône.
///
/// C'est aussi la source du glisser vers l'extérieur. Le fichier ne quitte le bac que si le
/// dépôt a abouti — `draggingSession(_:endedAt:operation:)` reçoit alors une opération non
/// vide ; un glisser annulé, ou relâché dans le vide, en reçoit une vide et laisse la vignette en
/// place.
private final class FileTrayItemView: NSView, NSDraggingSource {

  static let tileSize = NSSize(width: 104, height: 110)

  let url: URL
  private let store: FileShelfStore
  private let iconView = NSImageView()
  private let selectionLayer = CAShapeLayer()
  private let checkBadge = NSImageView()

  /// Appelé au clic simple (sans glisser) : le bac coche ou décoche la vignette.
  var onToggleSelection: (() -> Void)?
  /// Fichiers visés par le menu contextuel, donnés par le bac.
  var urlsForMenu: (() -> [URL])?

  var isSelected = false {
    didSet {
      guard isSelected != oldValue else { return }
      selectionLayer.isHidden = !isSelected
      checkBadge.isHidden = !isSelected
      if isSelected { checkBadge.layer?.springReveal(y: -3) }
    }
  }
  private let label = NSTextField(labelWithString: "")
  private var thumbnailTask: Task<Void, Never>?

  private let previewSize: CGFloat = 64
  private let labelGap: CGFloat = 6
  private let maxLabelLines = 2
  private let labelFont = NSFont.systemFont(
    ofSize: NSFont.systemFontSize(for: .small), weight: .regular)

  /// Distance à parcourir avant qu'un `mouseDragged` devienne un glisser : sans ce seuil, le
  /// moindre tremblement au clic en lancerait un.
  private let dragThreshold: CGFloat = 3
  private var mouseDownLocation: NSPoint?

  init(url: URL, store: FileShelfStore) {
    self.url = url
    self.store = store
    super.init(frame: .zero)
    wantsLayer = true

    iconView.image = NSWorkspace.shared.icon(forFile: url.path)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    // Aperçu en carré aux coins arrondis, comme les vignettes du Finder.
    iconView.wantsLayer = true
    iconView.layer?.cornerRadius = 14
    iconView.layer?.cornerCurve = .continuous
    iconView.layer?.masksToBounds = true
    addSubview(iconView)

    selectionLayer.fillColor = NSColor.white.withAlphaComponent(0.08).cgColor
    selectionLayer.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
    selectionLayer.lineWidth = 2
    selectionLayer.isHidden = true
    layer?.insertSublayer(selectionLayer, at: 0)

    checkBadge.image = NSImage(
      systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Selected")?
      .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
    checkBadge.contentTintColor = .systemBlue
    checkBadge.wantsLayer = true
    checkBadge.isHidden = true
    addSubview(checkBadge)

    label.isBezeled = false
    label.drawsBackground = false
    label.isEditable = false
    label.isSelectable = false
    label.alignment = .center
    label.font = labelFont
    label.lineBreakMode = .byCharWrapping
    label.maximumNumberOfLines = maxLabelLines
    label.stringValue = truncatedName(url.lastPathComponent)
    addSubview(label)

    loadThumbnail()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette(_ palette: OverlayPalette) {
    label.textColor = palette.tabActiveContent
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    // La vignette retirée du bac n'a plus besoin de son aperçu.
    if superview == nil { thumbnailTask?.cancel() }
  }

  // MARK: - Aperçu

  private func loadThumbnail() {
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: CGSize(width: previewSize, height: previewSize),
      scale: scale,
      representationTypes: .thumbnail
    )
    thumbnailTask = Task { [weak self] in
      do {
        let representation = try await QLThumbnailGenerator.shared
          .generateBestRepresentation(for: request)
        guard !Task.isCancelled else { return }
        self?.iconView.image = representation.nsImage
      } catch {
        // Pas de vignette de contenu pour ce type : l'icône du Finder reste.
        Log.sidePanel.debug(
          "Pas de vignette QuickLook : \(error.localizedDescription, privacy: .private)")
      }
    }
  }

  // MARK: - Nom

  /// Coupe le nom **au milieu** quand il ne tient pas sur `maxLabelLines` lignes, comme le
  /// Finder : on garde le début et la fin, donc l'extension. `NSTextField` ne sait couper qu'en
  /// fin de dernière ligne sur plusieurs lignes, d'où la mesure à la main.
  private func truncatedName(_ name: String) -> String {
    let width = Self.tileSize.width
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byCharWrapping
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .paragraphStyle: style]
    let lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading)

    func fits(_ text: String) -> Bool {
      let rect = (text as NSString).boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: .usesLineFragmentOrigin,
        attributes: attributes
      )
      return ceil(rect.height) <= lineHeight * CGFloat(maxLabelLines)
    }

    guard !fits(name) else { return name }

    let characters = Array(name)
    let tailLength = min(characters.count / 2, (url.pathExtension.count + 1) + 3)
    let tail = String(characters.suffix(tailLength))
    var low = 0
    var high = characters.count - tailLength
    while low < high {
      let middle = (low + high + 1) / 2
      if fits(String(characters.prefix(middle)) + "…" + tail) {
        low = middle
      } else {
        high = middle - 1
      }
    }
    return String(characters.prefix(low)) + "…" + tail
  }

  // MARK: - Glisser vers l'extérieur

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = convert(event.locationInWindow, from: nil)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let origin = mouseDownLocation else { return }
    let location = convert(event.locationInWindow, from: nil)
    guard hypot(location.x - origin.x, location.y - origin.y) >= dragThreshold else { return }
    mouseDownLocation = nil
    beginDrag(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    // Sans glisser entre-temps, c'est un clic : il coche la vignette.
    if mouseDownLocation != nil { onToggleSelection?() }
    mouseDownLocation = nil
  }

  // MARK: - Menu contextuel

  override func menu(for event: NSEvent) -> NSMenu? {
    let urls = urlsForMenu?() ?? [url]
    let menu = NSMenu()
    // Le suivi du curseur du panneau se gèle tant qu'un menu est ouvert (voir
    // `OverlayContextMenu.isPresenting`) : sans cela, il se replierait sous ce menu.
    menu.delegate = OverlayContextMenu.shared

    let copy = NSMenuItem(title: "Copy", action: #selector(copyFiles(_:)), keyEquivalent: "")
    copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
    copy.target = self
    copy.representedObject = urls
    menu.addItem(copy)

    let open = NSMenuItem(title: "Open", action: #selector(openFiles(_:)), keyEquivalent: "")
    open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
    open.target = self
    open.representedObject = urls
    menu.addItem(open)
    return menu
  }

  @objc private func copyFiles(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL] else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(urls as [NSURL])
  }

  @objc private func openFiles(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL] else { return }
    urls.forEach { NSWorkspace.shared.open($0) }
  }

  private func beginDrag(with event: NSEvent) {
    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
    // L'image sous le curseur est l'aperçu de la vignette, pas la vignette entière : c'est
    // le fichier qu'on déplace.
    item.setDraggingFrame(iconView.frame, contents: iconView.image)

    // Le panneau se replie dès que le curseur le quitte : il faut geler ce suivi le temps du
    // glisser, sans quoi le bac se refermerait sous la main qui en sort un fichier.
    store.isDraggingOut = true
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    switch context {
    // Le bac possède réellement les fichiers qu'il contient : Finder doit donc déplacer
    // le fichier hors de son dossier géré, plutôt que d'en créer une copie.
    case .outsideApplication: .move
    // Dans l'app, seule la zone AirDrop du bac reçoit : en copie, le fichier reste dans le bac.
    default: .copy
    }
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    store.isDraggingOut = false
    // Seul un déplacement hors de l'app retire le fichier : vide (annulé) ou copie (AirDrop
    // depuis le bac), il reste.
    guard operation.contains(.move) else { return }
    store.remove(url)
  }

  override func layout() {
    super.layout()

    iconView.frame = NSRect(
      x: bounds.midX - previewSize / 2,
      y: bounds.maxY - previewSize,
      width: previewSize,
      height: previewSize
    )

    selectionLayer.frame = bounds
    selectionLayer.path = CGPath(
      roundedRect: iconView.frame.insetBy(dx: -4, dy: -4), cornerWidth: 18, cornerHeight: 18,
      transform: nil)
    let badge = checkBadge.intrinsicContentSize
    checkBadge.frame = NSRect(
      x: iconView.frame.maxX - badge.width / 2 - 6, y: iconView.frame.minY - badge.height / 2 + 6,
      width: badge.width, height: badge.height)

    let labelTop = iconView.frame.minY - labelGap
    label.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, labelTop))
    // Le texte se cale en haut de la zone, juste sous l'aperçu, quelle que soit sa hauteur.
    let textHeight = min(
      label.sizeThatFits(NSSize(width: bounds.width, height: .greatestFiniteMagnitude)).height,
      labelTop)
    label.frame = NSRect(x: 0, y: labelTop - textHeight, width: bounds.width, height: textHeight)
  }
}

// MARK: - Bouton Transform

/// Le bouton « Transform » de la rangée de conversion : une icône de flèches circulaires et son
/// libellé, qui s'allume quand le glisser le survole.
private final class TransformDropTileView: NSView {

  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "Transform")

  var isHighlighted = false {
    didSet {
      guard isHighlighted != oldValue else { return }
      updateAppearance()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12

    iconView.image = NSImage(
      systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Transform")?
      .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    iconView.imageScaling = .scaleNone
    addSubview(iconView)

    label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
    label.alignment = .center
    label.isBezeled = false
    label.drawsBackground = false
    addSubview(label)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateAppearance() {
    layer?.backgroundColor =
      (isHighlighted
      ? NSColor.systemBlue.withAlphaComponent(0.4) : NSColor.white.withAlphaComponent(0.1)).cgColor
    iconView.contentTintColor = isHighlighted ? .white : .lightGray
    label.textColor = isHighlighted ? .white : .lightGray
  }

  override func layout() {
    super.layout()
    let icon = iconView.intrinsicContentSize
    let textHeight = label.intrinsicContentSize.height
    let total = icon.height + 2 + textHeight
    let top = bounds.midY + total / 2
    iconView.frame = NSRect(
      x: bounds.midX - icon.width / 2, y: top - icon.height, width: icon.width, height: icon.height)
    label.frame = NSRect(
      x: 0, y: top - icon.height - 2 - textHeight, width: bounds.width, height: textHeight)
  }
}
