import AppKit
import OSLog
import Quartz
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
///
/// Les vignettes sont **réutilisées** d'une mise à jour à l'autre (appariées par URL) : seules
/// celles qui arrivent ou partent s'animent, les autres glissent vers leur nouvelle place.
final class FileTrayView: NSView {

  private let emptyIcon = NSImageView()
  private let emptyLabel = NSTextField(labelWithString: "Drop files here")
  private let emptyHint = NSTextField(labelWithString: "Up to 4 files · drag them back out to move")
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
  private let keepLabel = NSTextField(labelWithString: "Keep in tray")
  /// Bouton « Transform », présent tant que le glisser est une image venue du bac : la lâcher
  /// dessus ouvre la vue Transform (voir `showsTransformTile`).
  private let transformTile = TransformDropTileView()
  private var showsTransformTile = false
  /// Fichiers cochés dans le bac : un clic sur une vignette la coche ou la décoche, et le menu
  /// contextuel (Copy, Open…) porte sur toute la sélection.
  private var selection: Set<URL> = []
  /// Défilement de la grille quand elle dépasse le bac, et sa course maximale.
  private var scrollOffset: CGFloat = 0
  private var maxScrollOffset: CGFloat = 0
  /// Vrai pour la prochaine mise en page : les vignettes déjà posées glissent vers leur place
  /// au lieu d'y sauter. Faux pour un simple redimensionnement.
  private var animatesNextLayout = false

  /// Bandeau du haut, présent tant que le bac contient des fichiers : « Clear ».
  private let clearButton = HomePillButton()
  private static let stripHeight: CGFloat = 20

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

    emptyIcon.image = NSImage(
      systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 24, weight: .light))
    emptyIcon.imageScaling = .scaleNone
    emptyIcon.wantsLayer = true
    addSubview(emptyIcon)

    for (label, size, weight) in [
      (emptyLabel, NSFont.systemFontSize(for: .small), NSFont.Weight.medium),
      (emptyHint, 10, .regular),
    ] {
      label.isBezeled = false
      label.drawsBackground = false
      label.isEditable = false
      label.isSelectable = false
      label.alignment = .center
      label.font = .systemFont(ofSize: size, weight: weight)
      label.lineBreakMode = .byTruncatingTail
      label.wantsLayer = true
      addSubview(label)
    }

    keepIcon.image = NSImage(
      systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Keep in tray")?
      .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))
    keepIcon.imageScaling = .scaleNone
    keepIcon.wantsLayer = true
    keepIcon.isHidden = true
    addSubview(keepIcon)

    keepLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
    keepLabel.alignment = .center
    keepLabel.isBezeled = false
    keepLabel.drawsBackground = false
    keepLabel.wantsLayer = true
    keepLabel.isHidden = true
    addSubview(keepLabel)

    airDropZone.isHidden = true
    addSubview(airDropZone)

    transformTile.isHidden = true
    addSubview(transformTile)

    clearButton.title = "Clear"
    clearButton.toolTip = "Move every file to the Bin"
    clearButton.isHidden = true
    clearButton.onClick = { [weak self] in self?.clearAll() }
    addSubview(clearButton)

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
    updateChrome(animated: false)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  private func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    // Gris au repos, blanc quand la zone est survolée : le bleu est réservé à AirDrop.
    let hovered = dropTarget == .keep
    emptyIcon.contentTintColor = .gray
    emptyLabel.textColor = .lightGray
    emptyHint.textColor = .gray
    keepIcon.contentTintColor = hovered ? .white : .gray
    keepLabel.textColor = hovered ? .white : .gray
    dropHighlightLayer.strokeColor = (hovered ? NSColor.white : NSColor.gray).cgColor
    dropHighlightLayer.fillColor =
      hovered ? NSColor.white.withAlphaComponent(0.06).cgColor : nil
    dropHighlightLayer.lineDashPattern = hovered ? nil : [4, 4]
    items.forEach { $0.applyPalette(palette) }
  }

  /// Pose l'opacité d'un calque, au ressort ou d'un coup.
  private func setOpacity(_ layer: CALayer?, _ value: Float, animated: Bool) {
    guard let layer else { return }
    if animated {
      layer.springAnimate(keyPath: "opacity", to: value)
    } else {
      layer.removeAnimation(forKey: "opacity")
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.opacity = value
      CATransaction.commit()
    }
  }

  /// Ce qui est visible hors des vignettes : l'état vide au repos, le liseré quand le bac est
  /// vide ou qu'un glisser le survole, le bandeau (compte, Clear) quand il y a des fichiers.
  private func updateChrome(animated: Bool) {
    let idleEmpty = store.isEmpty && !isDragActive
    let showsStrip = !store.isEmpty && !isDragActive
    let animated = animated && OverlayAnimation.allowsMotion

    for layer in [emptyIcon.layer, emptyLabel.layer, emptyHint.layer] {
      setOpacity(layer, idleEmpty ? 1 : 0, animated: animated)
    }
    setOpacity(dropHighlightLayer, idleEmpty || isDragActive ? 1 : 0, animated: animated)

    let stripWasHidden = clearButton.isHidden
    clearButton.isHidden = !showsStrip
    if showsStrip, stripWasHidden, animated {
      clearButton.layer?.crossfadeIn(delay: 0.05, duration: 0.18)
    }
    needsLayout = true
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
    let previousTarget = dropTarget
    isDragActive = active
    isDragFromTray = fromTray
    dropTarget = active ? target : nil
    showsTransformTile = showsTile
    transformTile.isHidden = !showsTile
    airDropZone.isHidden = !active
    keepIcon.isHidden = !active
    keepLabel.isHidden = !active
    airDropZone.isHighlighted = dropTarget == .airDrop
    transformTile.isHighlighted = dropTarget == .transform
    keepIcon.alphaValue = dropTarget == .keep ? 1 : 0.6
    keepLabel.alphaValue = dropTarget == .keep ? 1 : 0.6
    // Les vignettes s'effacent sous les zones au lieu de disparaître d'un coup.
    items.forEach { $0.setDimmed(active, animated: true) }
    if previousTarget != dropTarget {
      keepIcon.layer?.springScale(to: dropTarget == .keep ? 1.12 : 1)
    }
    applyPalette()
    updateChrome(animated: true)
    needsLayout = true
    if appearing {
      layoutSubtreeIfNeeded()
      airDropZone.playEntrance()
      keepIcon.layer?.springReveal(y: 10, preset: .gentle)
      keepLabel.layer?.springReveal(y: 10, preset: .gentle)
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

  /// Cible du menu contextuel et du glisser : la sélection si la vignette cliquée en fait
  /// partie, sinon cette vignette seule — comme dans le Finder.
  private func urlsForMenu(on url: URL) -> [URL] {
    selection.contains(url) ? store.urls.filter(selection.contains) : [url]
  }

  /// Met les fichiers à la corbeille. Vrai si au moins un est parti.
  private func trash(_ urls: [URL]) -> Bool {
    var removedAny = false
    for url in urls where store.trash(url) { removedAny = true }
    return removedAny
  }

  private func clearAll() {
    _ = trash(store.urls)
  }

  private func quickLook(_ url: URL) {
    let urls = items.map(\.url)
    guard let index = urls.firstIndex(of: url) else { return }
    TrayQuickLook.shared.show(urls, at: index)
  }

  private func makeItem(for url: URL) -> FileTrayItemView {
    let item = FileTrayItemView(url: url, store: store)
    item.isSelected = selection.contains(url)
    item.onToggleSelection = { [weak self] in self?.toggleSelection(of: url) }
    item.urlsForMenu = { [weak self] in self?.urlsForMenu(on: url) ?? [url] }
    item.onQuickLook = { [weak self] in self?.quickLook(url) }
    item.onTrash = { [weak self] urls in self?.trash(urls) ?? false }
    return item
  }

  /// Aligne les vignettes sur le bac sans rien reconstruire : celles qui y sont encore gardent
  /// leur vue (donc leur aperçu), celles qui n'y sont plus s'animent vers la sortie, celles qui
  /// arrivent entrent l'une après l'autre.
  private func rebuildRows() {
    let wasEmpty = items.isEmpty
    let current = Dictionary(items.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
    selection.formIntersection(store.urls)

    let animated =
      window != nil && !isHiddenOrHasHiddenAncestor && !isDragActive && OverlayAnimation.allowsMotion

    for item in items where !store.urls.contains(item.url) {
      item.leave { [weak item] in item?.removeFromSuperview() }
    }

    var arrivals: [FileTrayItemView] = []
    items = store.urls.map { url in
      if let existing = current[url] { return existing }
      let item = makeItem(for: url)
      item.setDimmed(isDragActive, animated: false)
      addSubview(item)
      arrivals.append(item)
      return item
    }
    // Les vignettes déjà posées glissent vers leur nouvelle place.
    animatesNextLayout = animated

    for (index, item) in arrivals.enumerated() {
      item.appear(delay: animated ? 0.05 * Double(index) : 0)
    }

    if wasEmpty != items.isEmpty, items.isEmpty, animated {
      emptyIcon.layer?.crossfadeIn(delay: 0.1, duration: 0.22)
      emptyLabel.layer?.crossfadeIn(delay: 0.12, duration: 0.22)
      emptyHint.layer?.crossfadeIn(delay: 0.14, duration: 0.22)
    }
    applyPalette()
    updateChrome(animated: animated)
    needsLayout = true
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
    let keepLabelHeight = keepLabel.intrinsicContentSize.height
    let keepTotal = iconSize.height + 4 + keepLabelHeight
    keepIcon.frame = NSRect(
      x: keepFrame.midX - iconSize.width / 2,
      y: keepFrame.midY + keepTotal / 2 - iconSize.height,
      width: iconSize.width, height: iconSize.height
    )
    keepLabel.frame = NSRect(
      x: keepFrame.minX, y: keepIcon.frame.minY - 4 - keepLabelHeight,
      width: keepFrame.width, height: keepLabelHeight)

    dropHighlightLayer.frame = bounds
    dropHighlightLayer.path = CGPath(
      roundedRect: keepFrame.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: 10,
      cornerHeight: 10,
      transform: nil
    )

    // État vide : icône, invite et indication, centrées en pile.
    let emptyIconSize = emptyIcon.intrinsicContentSize
    let titleHeight = emptyLabel.intrinsicContentSize.height
    let hintHeight = emptyHint.intrinsicContentSize.height
    let emptyTotal = emptyIconSize.height + 6 + titleHeight + 2 + hintHeight
    let emptyTop = bounds.midY + emptyTotal / 2
    emptyIcon.frame = NSRect(
      x: bounds.midX - emptyIconSize.width / 2, y: emptyTop - emptyIconSize.height,
      width: emptyIconSize.width, height: emptyIconSize.height)
    emptyLabel.frame = NSRect(
      x: bounds.minX + 8, y: emptyIcon.frame.minY - 6 - titleHeight,
      width: max(0, bounds.width - 16), height: titleHeight)
    emptyHint.frame = NSRect(
      x: bounds.minX + 8, y: emptyLabel.frame.minY - 2 - hintHeight,
      width: max(0, bounds.width - 16), height: hintHeight)

    // Bandeau du haut : « Clear » à droite.
    let inset: CGFloat = 8
    let strip = store.isEmpty ? 0 : Self.stripHeight + 4
    let stripY = bounds.maxY - 2 - Self.stripHeight
    let clearWidth = min(bounds.width / 2, clearButton.fittingWidth)
    clearButton.frame = NSRect(
      x: bounds.maxX - inset - clearWidth, y: stripY, width: clearWidth, height: Self.stripHeight)

    // Grille centrée dans ce qui reste sous le bandeau, rangée par rangée : le nombre de
    // colonnes est fixe, et une rangée incomplète se centre d'elle-même.
    let tile = FileTrayItemView.tileSize
    let columns = 4
    // Quatre vignettes par rangée ; si le bac est trop étroit, elles rétrécissent plutôt que de sortir.
    let tileWidth = min(
      tile.width, (bounds.width - 2 * inset - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
    )
    let rowCount = (items.count + columns - 1) / columns
    let gridHeight = CGFloat(rowCount) * tile.height + CGFloat(max(0, rowCount - 1)) * tileSpacing
    let area = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - strip))

    // Quand la grille dépasse le bac, elle défile depuis le haut et les vignettes coupées sont
    // rognées au bord ; sinon elle reste centrée.
    maxScrollOffset = max(0, gridHeight - (area.height - 2 * inset))
    scrollOffset = min(max(0, scrollOffset), maxScrollOffset)
    let gridTop =
      maxScrollOffset > 0
      ? area.maxY - inset + scrollOffset
      : area.midY + gridHeight / 2

    let animate = animatesNextLayout
    animatesNextLayout = false
    for (position, item) in items.enumerated() {
      let row = position / columns
      let column = position % columns
      let inRow = min(columns, items.count - row * columns)
      let rowWidth = CGFloat(inRow) * tileWidth + CGFloat(inRow - 1) * tileSpacing
      item.place(
        NSRect(
          x: bounds.midX - rowWidth / 2 + CGFloat(column) * (tileWidth + tileSpacing),
          y: gridTop - CGFloat(row + 1) * tile.height - CGFloat(row) * tileSpacing,
          width: tileWidth,
          height: tile.height
        ),
        animated: animate)
    }
  }
}

// MARK: - Coupe des noms

/// Coupe un nom **au milieu** quand il ne tient pas, comme le Finder : on garde le début et la
/// fin, donc l'extension. Séparé de la vue pour pouvoir se tester : `fits` dit si un texte tient.
enum TrayNameFitter {

  /// `tailLength` : nombre de caractères gardés en fin de nom (l'extension, point compris) ;
  /// trois de plus sont toujours conservés pour que la fin reste reconnaissable.
  static func fit(_ name: String, tailLength: Int, fits: (String) -> Bool) -> String {
    guard !fits(name) else { return name }

    let characters = Array(name)
    let kept = min(characters.count / 2, tailLength + 3)
    let tail = String(characters.suffix(kept))
    var low = 0
    var high = characters.count - kept
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
}

// MARK: - Quick Look

/// Le panneau Quick Look du bac. Le panneau de l'encoche ne prend pas le clavier sur cet onglet,
/// donc la chaîne des répondeurs ne peut pas le piloter : on lui donne ses fichiers directement.
/// Il s'ouvre dans sa propre fenêtre, qui reste quand le panneau de l'encoche se replie.
@MainActor
final class TrayQuickLook: NSObject, QLPreviewPanelDataSource {

  static let shared = TrayQuickLook()

  private var urls: [URL] = []

  func show(_ urls: [URL], at index: Int) {
    guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
    self.urls = urls
    panel.dataSource = self
    panel.reloadData()
    panel.currentPreviewItemIndex = min(max(0, index), urls.count - 1)
    // L'app n'a pas d'icône du Dock : sans activation, l'aperçu s'ouvrirait derrière.
    NSApp.activate()
    panel.makeKeyAndOrderFront(nil)
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    urls.indices.contains(index) ? urls[index] as NSURL : nil
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
///
/// Gestes : clic = cocher, double clic = Quick Look, survol = ✕ de retrait, balayage vers le
/// haut à deux doigts = retrait, glisser = sortir le fichier (toute la sélection si la vignette
/// en fait partie).
private final class FileTrayItemView: NSView, NSDraggingSource {

  static let tileSize = NSSize(width: 104, height: 110)

  let url: URL
  private let store: FileShelfStore
  private let iconView = NSImageView()
  private let hoverLayer = CALayer()
  private let selectionLayer = CAShapeLayer()
  private let checkBadge = NSImageView()
  private let removeButton = TrayRemoveButton()

  /// Appelé au clic simple (sans glisser) : le bac coche ou décoche la vignette.
  var onToggleSelection: (() -> Void)?
  /// Fichiers visés par le menu contextuel et le glisser, donnés par le bac.
  var urlsForMenu: (() -> [URL])?
  var onQuickLook: (() -> Void)?
  /// Met des fichiers à la corbeille ; faux si rien n'a pu partir.
  var onTrash: (([URL]) -> Bool)?

  var isSelected = false {
    didSet {
      guard isSelected != oldValue else { return }
      selectionLayer.isHidden = !isSelected
      checkBadge.isHidden = !isSelected
      if isSelected { checkBadge.layer?.springReveal(y: -3) }
    }
  }
  private let label = NSTextField(wrappingLabelWithString: "")
  private var thumbnailTask: Task<Void, Never>?

  private let previewSize: CGFloat = 64
  private let labelGap: CGFloat = 6
  private let maxLabelLines = 2
  private let labelFont = NSFont.systemFont(
    ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
  /// Largeur pour laquelle le nom a été coupé : on ne le recoupe que si elle change.
  private var fittedWidth: CGFloat = -1

  /// Distance à parcourir avant qu'un `mouseDragged` devienne un glisser : sans ce seuil, le
  /// moindre tremblement au clic en lancerait un.
  private let dragThreshold: CGFloat = 3
  private var mouseDownLocation: NSPoint?
  private var draggedURLs: [URL] = []

  private var trackingArea: NSTrackingArea?
  private var isHovered = false
  private var hasBeenPlaced = false
  private var isLeaving = false
  private var isDimmed = false
  private var exitsUpward = false

  // Balayage vers le haut : retrait. Décidé une fois, au début du geste.
  private enum Swipe { case idle, undecided, engaged, passthrough }
  private var swipe = Swipe.idle
  private var swipeUp: CGFloat = 0
  private var swipeSideways: CGFloat = 0
  private var swallowsMomentum = false
  private static let swipeEngage: CGFloat = 4
  private static let swipeCommit: CGFloat = 40

  init(url: URL, store: FileShelfStore) {
    self.url = url
    self.store = store
    super.init(frame: .zero)
    wantsLayer = true

    hoverLayer.cornerRadius = 12
    hoverLayer.cornerCurve = .continuous
    hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    hoverLayer.opacity = 0
    layer?.insertSublayer(hoverLayer, at: 0)

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
    layer?.insertSublayer(selectionLayer, at: 1)

    checkBadge.image = NSImage(
      systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Selected")?
      .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
    checkBadge.contentTintColor = .systemBlue
    checkBadge.wantsLayer = true
    checkBadge.isHidden = true
    addSubview(checkBadge)

    removeButton.alphaValue = 0
    removeButton.isHidden = true
    removeButton.onClick = { [weak self] in self?.trashSelf() }
    addSubview(removeButton)

    label.isBezeled = false
    label.drawsBackground = false
    label.isEditable = false
    label.isSelectable = false
    label.alignment = .center
    label.font = labelFont
    label.lineBreakMode = .byCharWrapping
    label.maximumNumberOfLines = maxLabelLines
    label.stringValue = url.lastPathComponent
    addSubview(label)

    toolTip = url.lastPathComponent
    setAccessibilityLabel(url.lastPathComponent)
    setAccessibilityRole(.button)

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

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isLeaving ? nil : super.hitTest(point)
  }

  override func accessibilityPerformPress() -> Bool {
    onQuickLook?()
    return true
  }

  // MARK: - Apparition, sortie, place

  /// Entre en ressort après `delay` : fondu, léger grossissement et petite montée. Sans
  /// mouvement autorisé, la vignette est simplement là.
  func appear(delay: TimeInterval) {
    guard OverlayAnimation.allowsMotion, let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    layer.setValue(0.85, forKeyPath: "transform.scale")
    layer.setValue(-8, forKeyPath: "transform.translation.y")
    CATransaction.commit()

    let run: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self, !self.isLeaving, let layer = self.layer else { return }
      let target: Float = self.isDimmed ? 0 : 1
      layer.springAnimate(keyPath: "opacity", to: target)
      layer.springAnimate(keyPath: "transform.scale", to: CGFloat(1), preset: .gentle)
      layer.springAnimate(keyPath: "transform.translation.y", to: CGFloat(0), preset: .gentle)
    }
    if delay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
    } else {
      run()
    }
  }

  /// Sort : fondu et rétrécissement (en montant, si c'est un balayage), puis `completion`.
  func leave(completion: @escaping () -> Void) {
    guard !isLeaving else { return }
    isLeaving = true
    thumbnailTask?.cancel()
    guard OverlayAnimation.allowsMotion, let layer else {
      completion()
      return
    }
    layer.springAnimate(keyPath: "transform.scale", to: CGFloat(0.8))
    if exitsUpward {
      layer.springAnimate(keyPath: "transform.translation.y", to: CGFloat(24))
    }
    layer.springAnimate(keyPath: "opacity", to: Float(0), completion: completion)
  }

  /// S'efface (ou revient) quand un glisser survole le bac, pour laisser la place aux zones.
  func setDimmed(_ dimmed: Bool, animated: Bool) {
    isDimmed = dimmed
    guard !isLeaving, let layer else { return }
    let value: Float = dimmed ? 0 : 1
    if animated {
      layer.springAnimate(keyPath: "opacity", to: value)
    } else {
      layer.removeAnimation(forKey: "opacity")
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.opacity = value
      CATransaction.commit()
    }
  }

  /// Pose la vignette ; si elle était déjà posée et que `animated`, elle glisse depuis son
  /// ancienne place au ressort.
  func place(_ frame: NSRect, animated: Bool) {
    guard !isLeaving else { return }
    let previous = layer?.presentation()?.position ?? layer?.position
    self.frame = frame
    defer { hasBeenPlaced = true }
    guard animated, hasBeenPlaced, let layer, let previous, previous != layer.position else {
      return
    }
    layer.springAnimate(
      keyPath: "position", to: NSValue(point: layer.position), from: NSValue(point: previous),
      preset: .gentle)
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
        self?.iconView.layer?.crossfadeIn(delay: 0, duration: 0.15)
      } catch {
        // Pas de vignette de contenu pour ce type : l'icône du Finder reste.
        Log.sidePanel.debug(
          "Pas de vignette QuickLook : \(error.localizedDescription, privacy: .private)")
      }
    }
  }

  // MARK: - Nom

  /// Coupe le nom au milieu pour qu'il tienne sur `maxLabelLines` lignes **dans la largeur
  /// réelle du champ**. Mesuré avec la cellule du champ — qui compte ses marges internes — et
  /// refait quand la largeur change : une mesure faite une fois, à une autre largeur, laissait
  /// le texte déborder sur une troisième ligne.
  private func fitName(forWidth width: CGFloat) {
    guard width > 0, abs(width - fittedWidth) > 0.5 else { return }
    fittedWidth = width
    let name = url.lastPathComponent

    // Le champ dessine son texte dans une marge et coupe un peu plus court que `boundingRect` :
    // on mesure avec de la marge de sécurité, avec la même coupe de ligne que lui.
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byCharWrapping
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .paragraphStyle: style]
    let inner = NSSize(width: max(1, width - 10), height: .greatestFiniteMagnitude)
    func height(of text: String) -> CGFloat {
      ceil(
        (text as NSString).boundingRect(
          with: inner, options: .usesLineFragmentOrigin, attributes: attributes
        ).height)
    }
    let limit = height(of: "Ag") * CGFloat(maxLabelLines)

    label.stringValue = TrayNameFitter.fit(name, tailLength: url.pathExtension.count + 1) {
      height(of: $0) <= limit
    }
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  private func setHovered(_ hovered: Bool) {
    guard hovered != isHovered, !isLeaving else { return }
    isHovered = hovered
    if hovered { toolTip = Self.description(of: url) }
    hoverLayer.setValue(hovered ? Float(1) : Float(0), forKeyPath: "opacity")
    hoverLayer.springAnimate(keyPath: "opacity", to: hovered ? Float(1) : Float(0))
    if hovered { removeButton.isHidden = false }
    removeButton.layer?.springAnimate(
      keyPath: "opacity", to: hovered ? Float(1) : Float(0)
    ) { [weak self] in
      if self?.isHovered == false { self?.removeButton.isHidden = true }
    }
  }

  /// Nom, type et taille : l'infobulle dit ce que la vignette ne montre pas.
  private static func description(of url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [
      .localizedTypeDescriptionKey, .fileSizeKey, .totalFileSizeKey,
    ])
    var parts = [url.lastPathComponent]
    if let kind = values?.localizedTypeDescription { parts.append(kind) }
    if let size = values?.totalFileSize ?? values?.fileSize {
      parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
    }
    return parts.joined(separator: "\n")
  }

  // MARK: - Souris

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = convert(event.locationInWindow, from: nil)
    layer?.springScale(to: 0.96)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let origin = mouseDownLocation else { return }
    let location = convert(event.locationInWindow, from: nil)
    guard hypot(location.x - origin.x, location.y - origin.y) >= dragThreshold else { return }
    mouseDownLocation = nil
    layer?.springScale(to: 1)
    beginDrag(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    layer?.springScale(to: 1)
    defer { mouseDownLocation = nil }
    guard mouseDownLocation != nil else { return }
    // Double clic : Quick Look. Le premier clic a déjà coché la vignette, le second ne la
    // décoche pas.
    if event.clickCount >= 2 {
      onQuickLook?()
    } else {
      onToggleSelection?()
    }
  }

  // MARK: - Balayage vers le haut

  override func scrollWheel(with event: NSEvent) {
    guard event.hasPreciseScrollingDeltas, !isLeaving else { return super.scrollWheel(with: event) }

    if !event.momentumPhase.isEmpty {
      if swallowsMomentum { return }
      return super.scrollWheel(with: event)
    }
    if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
      swipe = .undecided
      swipeUp = 0
      swipeSideways = 0
      swallowsMomentum = false
    }

    switch swipe {
    case .idle, .passthrough:
      super.scrollWheel(with: event)
    case .undecided:
      swipeUp -= event.scrollingDeltaY
      swipeSideways += event.scrollingDeltaX
      if abs(swipeUp) > Self.swipeEngage || abs(swipeSideways) > Self.swipeEngage {
        // Surtout vers le haut : c'est un retrait. Sinon le geste appartient au panneau
        // (balayage d'onglet) et on le lui laisse.
        if swipeUp > 0, swipeUp > abs(swipeSideways) * 1.5 {
          swipe = .engaged
          layer?.removeAnimation(forKey: "transform")
          followSwipe()
        } else {
          swipe = .passthrough
          super.scrollWheel(with: event)
        }
      } else {
        super.scrollWheel(with: event)
      }
    case .engaged:
      swipeUp -= event.scrollingDeltaY
      followSwipe()
    }

    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      finishSwipe(cancelled: event.phase.contains(.cancelled))
    }
  }

  /// La vignette suit les doigts ; au-delà du seuil le déplacement se durcit, pour dire
  /// « c'est bon, tu peux lâcher ».
  private func followSwipe() {
    let up = max(0, swipeUp)
    let shown = min(up, Self.swipeCommit) + max(0, up - Self.swipeCommit) * 0.25
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.transform = CATransform3DMakeTranslation(0, shown, 0)
    layer?.opacity = Float(isDimmed ? 0 : 1 - min(0.5, shown / 120))
    CATransaction.commit()
  }

  private func finishSwipe(cancelled: Bool) {
    defer {
      swipe = .idle
      swipeUp = 0
      swipeSideways = 0
    }
    guard swipe == .engaged else { return }
    swallowsMomentum = true
    if !cancelled, swipeUp >= Self.swipeCommit {
      exitsUpward = true
      if onTrash?([url]) == true { return }
      exitsUpward = false
    }
    settleBack()
  }

  private func settleBack() {
    layer?.springAnimate(
      keyPath: "transform", to: NSValue(caTransform3D: CATransform3DIdentity), preset: .snappy)
    layer?.springAnimate(keyPath: "opacity", to: Float(isDimmed ? 0 : 1))
  }

  private func trashSelf() {
    exitsUpward = false
    _ = onTrash?([url])
  }

  // MARK: - Menu contextuel

  override func menu(for event: NSEvent) -> NSMenu? {
    let urls = urlsForMenu?() ?? [url]
    let menu = NSMenu()
    // Le suivi du curseur du panneau se gèle tant qu'un menu est ouvert (voir
    // `OverlayContextMenu.isPresenting`) : sans cela, il se replierait sous ce menu.
    menu.delegate = OverlayContextMenu.shared

    func add(_ title: String, _ symbol: String, _ action: Selector) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      item.target = self
      item.representedObject = urls
      menu.addItem(item)
    }
    add("Quick Look", "eye", #selector(quickLook(_:)))
    add("Open", "arrow.up.forward.app", #selector(openFiles(_:)))
    add("Show in Finder", "folder", #selector(revealFiles(_:)))
    add("Copy", "doc.on.doc", #selector(copyFiles(_:)))
    menu.addItem(.separator())
    add("Move to Bin", "trash", #selector(trashFiles(_:)))
    return menu
  }

  @objc private func quickLook(_ sender: NSMenuItem) { onQuickLook?() }

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

  @objc private func revealFiles(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL] else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @objc private func trashFiles(_ sender: NSMenuItem) {
    guard let urls = sender.representedObject as? [URL] else { return }
    exitsUpward = false
    _ = onTrash?(urls)
  }

  // MARK: - Glisser vers l'extérieur

  private func beginDrag(with event: NSEvent) {
    setHovered(false)
    // La sélection part avec la vignette si celle-ci en fait partie ; sinon, elle seule.
    let urls = urlsForMenu?() ?? [url]
    draggedURLs = urls
    let image = iconView.image
    let items = urls.enumerated().map { index, fileURL -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
      // L'image sous le curseur est l'aperçu de la vignette, pas la vignette entière : c'est
      // le fichier qu'on déplace. Les suivants sont décalés en éventail.
      let offset = CGFloat(index) * 4
      item.setDraggingFrame(iconView.frame.offsetBy(dx: offset, dy: -offset), contents: image)
      return item
    }

    // Le panneau se replie dès que le curseur le quitte : il faut geler ce suivi le temps du
    // glisser, sans quoi le bac se refermerait sous la main qui en sort un fichier.
    store.isDraggingOut = true
    beginDraggingSession(with: items, event: event, source: self)
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
    let moved = draggedURLs
    draggedURLs = []
    // Seul un déplacement hors de l'app retire les fichiers : vide (annulé) ou copie (AirDrop
    // depuis le bac), ils restent.
    guard operation.contains(.move) else { return }
    moved.forEach { store.remove($0) }
  }

  override func layout() {
    super.layout()

    hoverLayer.frame = bounds
    let preview = min(previewSize, max(0, bounds.width - 10))
    iconView.frame = NSRect(
      x: bounds.midX - preview / 2,
      y: bounds.maxY - preview - 4,
      width: preview,
      height: preview
    )

    selectionLayer.frame = bounds
    selectionLayer.path = CGPath(
      roundedRect: iconView.frame.insetBy(dx: -4, dy: -4), cornerWidth: 18, cornerHeight: 18,
      transform: nil)
    let badge = checkBadge.intrinsicContentSize
    checkBadge.frame = NSRect(
      x: iconView.frame.maxX - badge.width / 2 - 6, y: iconView.frame.minY - badge.height / 2 + 6,
      width: badge.width, height: badge.height)
    removeButton.frame = NSRect(
      x: max(0, iconView.frame.minX - 6), y: iconView.frame.maxY - 12, width: 18, height: 18)

    let labelTop = iconView.frame.minY - labelGap
    let labelWidth = max(0, bounds.width - 4)
    fitName(forWidth: labelWidth)
    let textHeight = min(
      label.sizeThatFits(NSSize(width: labelWidth, height: .greatestFiniteMagnitude)).height,
      max(0, labelTop))
    label.frame = NSRect(x: 2, y: labelTop - textHeight, width: labelWidth, height: textHeight)
  }
}

// MARK: - Bouton de retrait

/// Le ✕ qui apparaît au survol d'une vignette : une pastille sombre, un petit rétrécissement à
/// l'appui, l'action au relâchement dans la pastille.
private final class TrayRemoveButton: NSView {

  var onClick: (() -> Void)?

  private let glyph = NSImageView()
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      layer?.springScale(to: isPressed ? 0.88 : 1)
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    layer?.borderWidth = 0.5
    glyph.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Move to Bin")?
      .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
    glyph.contentTintColor = .white
    glyph.imageScaling = .scaleNone
    addSubview(glyph)
    toolTip = "Move to Bin"
    setAccessibilityRole(.button)
    setAccessibilityLabel("Move to Bin")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }

  override func mouseDown(with event: NSEvent) { isPressed = true }
  override func mouseDragged(with event: NSEvent) {
    isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
  }
  override func mouseUp(with event: NSEvent) {
    let inside = bounds.contains(convert(event.locationInWindow, from: nil))
    isPressed = false
    if inside { onClick?() }
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    let size = glyph.intrinsicContentSize
    glyph.frame = NSRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
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
