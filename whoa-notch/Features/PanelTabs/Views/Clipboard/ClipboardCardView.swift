import AppKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

extension ClipboardKind {
  /// Couleur de la bordure basse de la carte. L'app est toujours en `.darkAqua` : pas de variante.
  var accentColor: NSColor {
    switch self {
    case .image: NSColor(srgbRed: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
    case .text: NSColor(srgbRed: 0x5C / 255, green: 0xC8 / 255, blue: 0x5A / 255, alpha: 1)
    case .link: NSColor(srgbRed: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255, alpha: 1)
    case .file: NSColor(srgbRed: 0xB0 / 255, green: 0x3F / 255, blue: 0xE0 / 255, alpha: 1)
    case .video: NSColor(srgbRed: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
    }
  }
}

/// Aperçus déjà calculés, par identifiant d'élément : une carte recréée (changement de filtre)
/// ne relit ni le disque ni Quick Look.
@MainActor
enum ClipboardThumbnailCache {
  static let images = NSCache<NSString, CGImage>()
}

/// Résultat d'un chargement hors du thread principal. `CGImage` est immuable.
private struct LoadedImage: @unchecked Sendable {
  let image: CGImage
}

/// Une carte de l'historique : aperçu selon le type, pied (appli source, âge), bordure basse
/// colorée. Un clic la remet dans le presse-papiers ; au survol, ✕ la retire et l'épingle la
/// garde en tête ; un balayage vers le haut la retire ; la glisser la dépose dans une autre app.
final class ClipboardCardView: NSView, NSDraggingSource {

  static let size = NSSize(width: 124, height: 104)

  /// Clic simple : remettre dans le presse-papiers.
  var onClick: (() -> Void)?
  var onDelete: (() -> Void)?
  var onTogglePin: (() -> Void)?

  private(set) var item: ClipboardItem

  private let imageURL: URL?
  private let previewView = NSImageView()
  private let coverView = NSView()
  private let swatchView = NSView()
  private let textLabel = NSTextField(wrappingLabelWithString: "")
  private let secondaryLabel = NSTextField(wrappingLabelWithString: "")
  private let glyphView = NSImageView()
  private let chipLabel = NSTextField(labelWithString: "")
  private let playBadge = NSImageView()
  private let sourceIconView = NSImageView()
  private let ageLabel = NSTextField(labelWithString: "")
  private let pinMarker = NSImageView()
  private let deleteButton = ClipboardCardButton(symbol: "xmark", label: "Delete")
  private let pinButton = ClipboardCardButton(symbol: "pin", label: "Pin")
  private let copiedView = NSView()
  private let shade = CAGradientLayer()
  private let hoverLayer = CALayer()
  private let accentBar = CALayer()
  private var thumbnailTask: Task<Void, Never>?
  private var copiedWork: DispatchWorkItem?

  private let barHeight: CGFloat = 4
  private let padding: CGFloat = 10
  private let textFont = NSFont.systemFont(ofSize: 12, weight: .regular)
  private let codeFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
  private let maxTextLines = 3

  // Animations d'entrée, de sortie et de place
  private(set) var hasBeenPlaced = false
  private var isLeaving = false
  private var exitsUpward = false

  // Survol, appui, glisser
  private var trackingArea: NSTrackingArea?
  private var isHovered = false
  private var mouseDownLocation: NSPoint?
  private let dragThreshold: CGFloat = 3

  // Balayage vers le haut : retrait. Décidé une fois, au début du geste.
  private enum Swipe { case idle, undecided, engaged, passthrough }
  private var swipe = Swipe.idle
  private var swipeUp: CGFloat = 0
  private var swipeSideways: CGFloat = 0
  private var swallowsMomentum = false
  private static let swipeEngage: CGFloat = 4
  private static let swipeCommit: CGFloat = 40

  init(item: ClipboardItem, imageURL: URL?) {
    self.item = item
    self.imageURL = imageURL
    super.init(frame: NSRect(origin: .zero, size: Self.size))
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit { thumbnailTask?.cancel() }

  // MARK: - Construction

  private func setUp() {
    accentBar.backgroundColor = item.kind.accentColor.cgColor
    layer?.addSublayer(accentBar)

    switch item.kind {
    case .text where colorValue != nil:
      swatchView.wantsLayer = true
      swatchView.layer?.cornerRadius = 8
      swatchView.layer?.cornerCurve = .continuous
      swatchView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
      swatchView.layer?.borderWidth = 0.5
      addSubview(swatchView)
      configure(textLabel, font: .monospacedSystemFont(ofSize: 12, weight: .semibold), lines: 1)
      textLabel.alignment = .center
      textLabel.lineBreakMode = .byTruncatingTail
      swatchView.addSubview(textLabel)
    case .text:
      configure(textLabel, font: textFont, lines: maxTextLines)
      addSubview(textLabel)
    case .link:
      let glyph = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
      glyphView.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
        .withSymbolConfiguration(glyph)
      glyphView.contentTintColor = item.kind.accentColor
      addSubview(glyphView)
      configure(textLabel, font: .systemFont(ofSize: 12, weight: .semibold), lines: 1)
      textLabel.lineBreakMode = .byTruncatingMiddle
      addSubview(textLabel)
      configure(secondaryLabel, font: .systemFont(ofSize: 11), lines: 2)
      secondaryLabel.textColor = NSColor(white: 0.62, alpha: 1)
      addSubview(secondaryLabel)
    case .image, .video:
      coverView.wantsLayer = true
      coverView.layer?.contentsGravity = .resizeAspectFill
      addSubview(coverView)
      // Voile bas : l'icône et l'âge restent lisibles sur n'importe quelle image.
      shade.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.6).cgColor]
      layer?.insertSublayer(shade, above: coverView.layer)
      if item.kind == .video {
        playBadge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)?
          .withSymbolConfiguration(.init(pointSize: 26, weight: .regular))
        playBadge.contentTintColor = .white.withAlphaComponent(0.9)
        addSubview(playBadge)
      } else {
        chipLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        chipLabel.textColor = .white
        chipLabel.wantsLayer = true
        chipLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        chipLabel.layer?.cornerRadius = 7
        chipLabel.alignment = .center
        chipLabel.isHidden = true
        addSubview(chipLabel)
      }
      loadPreview()
    case .file:
      previewView.imageScaling = .scaleProportionallyUpOrDown
      addSubview(previewView)
      configure(textLabel, font: .systemFont(ofSize: 11, weight: .medium), lines: 1)
      textLabel.alignment = .center
      textLabel.lineBreakMode = .byTruncatingMiddle
      addSubview(textLabel)
      loadPreview()
    }

    hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    hoverLayer.opacity = 0
    layer?.addSublayer(hoverLayer)

    sourceIconView.imageScaling = .scaleProportionallyUpOrDown
    sourceIconView.image = Self.sourceIcon(bundleID: item.sourceBundleID)
    addSubview(sourceIconView)

    ageLabel.font = .systemFont(ofSize: 11, weight: .regular)
    ageLabel.textColor = NSColor(white: 0.85, alpha: 1)
    addSubview(ageLabel)

    pinMarker.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
      .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
    pinMarker.contentTintColor = .white.withAlphaComponent(0.8)
    addSubview(pinMarker)

    for button in [deleteButton, pinButton] {
      button.alphaValue = 0
      button.isHidden = true
      addSubview(button)
    }
    deleteButton.onClick = { [weak self] in
      self?.exitsUpward = false
      self?.onDelete?()
    }
    pinButton.onClick = { [weak self] in self?.onTogglePin?() }

    setUpCopiedOverlay()
    setAccessibilityRole(.button)
    apply(item: item)
  }

  private func configure(_ label: NSTextField, font: NSFont, lines: Int) {
    label.font = font
    label.textColor = .white
    label.isBordered = false
    label.drawsBackground = false
    label.isSelectable = false
    label.maximumNumberOfLines = lines
    // Plusieurs lignes : à la ligne par mots, la dernière ligne visible se termine par « … ».
    // Avec `.byTruncatingTail` le label ne passerait jamais à la ligne.
    label.lineBreakMode = lines > 1 ? .byWordWrapping : .byTruncatingTail
    label.cell?.truncatesLastVisibleLine = true
    label.alignment = .left
  }

  private func setUpCopiedOverlay() {
    copiedView.wantsLayer = true
    copiedView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
    copiedView.layer?.opacity = 0
    copiedView.isHidden = true
    let check = NSImageView(
      image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 22, weight: .regular)) ?? NSImage())
    check.contentTintColor = item.kind.accentColor
    check.tag = 1
    let caption = NSTextField(labelWithString: "Copied")
    caption.font = .systemFont(ofSize: 11, weight: .semibold)
    caption.textColor = .white
    caption.alignment = .center
    caption.tag = 2
    copiedView.addSubview(check)
    copiedView.addSubview(caption)
    addSubview(copiedView)
  }

  // MARK: - Mise à jour

  private var colorValue: ClipboardPreview.ColorValue? {
    item.kind == .text ? item.text.flatMap(ClipboardPreview.colorValue(in:)) : nil
  }

  /// Applique l'état de l'élément (épingle, date) à une carte déjà à l'écran.
  func apply(item newItem: ClipboardItem) {
    item = newItem
    switch item.kind {
    case .text:
      if let color = colorValue {
        swatchView.layer?.backgroundColor = color.color.cgColor
        textLabel.stringValue = color.label
        textLabel.textColor = color.ink
      } else {
        let display = ClipboardPreview.displayText(item.text ?? "")
        textLabel.stringValue = display
        textLabel.font = ClipboardPreview.looksLikeCode(display) ? codeFont : textFont
      }
    case .link:
      let parts = ClipboardPreview.linkParts(item.text ?? "")
      textLabel.stringValue = parts.host
      secondaryLabel.stringValue = parts.rest
    case .file:
      textLabel.stringValue = item.fileURL?.lastPathComponent ?? item.tag
    default: break
    }
    toolTip = Self.tooltip(for: item)
    setAccessibilityLabel(
      item.text.map { String($0.prefix(80)) } ?? item.fileURL?.lastPathComponent ?? item.tag)
    pinButton.update(symbol: item.isPinned ? "pin.slash" : "pin", label: item.isPinned ? "Unpin" : "Pin")
    pinMarker.isHidden = !item.isPinned || isHovered
    refreshAge()
    needsLayout = true
  }

  /// Recalcule « il y a N min » — appelé à chaque dépliage du panneau.
  func refreshAge() {
    ageLabel.stringValue = ClipboardItem.ageText(since: item.date)
    needsLayout = true
  }

  private static func tooltip(for item: ClipboardItem) -> String {
    if let url = item.fileURL { return url.path }
    if let text = item.text { return String(text.prefix(400)) }
    return item.tag
  }

  private static func sourceIcon(bundleID: String?) -> NSImage? {
    guard
      let bundleID,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  // MARK: - Aperçu

  private func loadPreview() {
    let key = item.id.uuidString as NSString
    if let cached = ClipboardThumbnailCache.images.object(forKey: key) {
      show(cached)
      return
    }
    if item.kind == .file, let url = item.fileURL {
      previewView.image = Self.icon(for: url)
      return
    }
    let fileURL = item.fileURL
    let imageURL = imageURL
    let pixels = Self.size.width * (NSScreen.main?.backingScaleFactor ?? 2)
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    thumbnailTask = Task { [weak self] in
      var loaded: LoadedImage?
      if let imageURL {
        loaded = await Task.detached(priority: .utility) {
          Self.thumbnail(at: imageURL, maxPixel: pixels * 1.5)
        }.value
      } else if let fileURL {
        let request = QLThumbnailGenerator.Request(
          fileAt: fileURL, size: Self.size, scale: scale, representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared
          .generateBestRepresentation(for: request)
        {
          loaded = LoadedImage(image: representation.cgImage)
        }
      }
      guard let loaded, !Task.isCancelled, let self else { return }
      ClipboardThumbnailCache.images.setObject(loaded.image, forKey: key)
      self.show(loaded.image)
    }
  }

  /// Lit une miniature sans décoder toute l'image sur le thread principal.
  private nonisolated static func thumbnail(at url: URL, maxPixel: CGFloat) -> LoadedImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return LoadedImage(image: image)
  }

  private func show(_ image: CGImage) {
    coverView.layer?.contents = image
    coverView.layer?.contentsScale = window?.backingScaleFactor ?? 2
    if item.kind == .image, let imageURL,
      let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    {
      chipLabel.stringValue = "\(width)×\(height)"
      chipLabel.isHidden = false
    }
    // L'aperçu arrive après la carte : fondu plutôt qu'apparition sèche.
    coverView.layer?.crossfadeIn(delay: 0, duration: 0.18)
    needsLayout = true
  }

  /// Icône du Finder, ou celle du type quand le fichier n'existe plus.
  private static func icon(for url: URL) -> NSImage {
    if FileManager.default.fileExists(atPath: url.path) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    accentBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
    hoverLayer.frame = bounds

    let iconSide: CGFloat = 22
    let footerY = barHeight + 8
    let hasIcon = sourceIconView.image != nil
    sourceIconView.isHidden = !hasIcon
    sourceIconView.frame = CGRect(x: padding, y: footerY, width: iconSide, height: iconSide)
    let ageSize = ageLabel.sizeThatFits(NSSize(width: 200, height: 20))
    let ageX = hasIcon ? sourceIconView.frame.maxX + 6 : padding
    ageLabel.frame = CGRect(
      x: ageX, y: footerY + (iconSide - ceil(ageSize.height)) / 2,
      width: max(0, min(ceil(ageSize.width), bounds.width - ageX - 6)), height: ceil(ageSize.height))
    shade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2)

    let contentWidth = bounds.width - 2 * padding
    let top = bounds.maxY - padding
    let bottom = footerY + iconSide + 6

    switch item.kind {
    case .text where colorValue != nil:
      swatchView.frame = CGRect(x: padding, y: bottom, width: contentWidth, height: top - bottom)
      let height = ceil(textLabel.intrinsicContentSize.height)
      textLabel.frame = CGRect(
        x: 4, y: (swatchView.bounds.height - height) / 2, width: swatchView.bounds.width - 8,
        height: height)
    case .text:
      // Hauteur de `maxTextLines` lignes exactement : une quatrième ligne ne peut pas dépasser.
      let line = ceil(textLabel.font?.boundingRectForFont.height ?? 14)
      let height = min(top - bottom, line * CGFloat(maxTextLines))
      textLabel.preferredMaxLayoutWidth = contentWidth
      textLabel.frame = CGRect(x: padding, y: top - height, width: contentWidth, height: max(0, height))
    case .link:
      glyphView.frame = CGRect(x: padding, y: top - 14, width: 14, height: 14)
      let hostHeight = ceil(textLabel.intrinsicContentSize.height)
      textLabel.frame = CGRect(
        x: padding, y: glyphView.frame.minY - 4 - hostHeight, width: contentWidth, height: hostHeight)
      let restTop = textLabel.frame.minY - 2
      secondaryLabel.preferredMaxLayoutWidth = contentWidth
      secondaryLabel.frame = CGRect(
        x: padding, y: bottom, width: contentWidth, height: max(0, restTop - bottom))
    case .image, .video:
      coverView.frame = bounds
      playBadge.frame = CGRect(
        x: bounds.midX - 16, y: bounds.midY - 10, width: 32, height: 32)
      let chip = chipLabel.intrinsicContentSize
      chipLabel.frame = CGRect(
        x: padding, y: top - 14, width: min(contentWidth, ceil(chip.width) + 10), height: 14)
    case .file:
      let side: CGFloat = 40
      previewView.frame = CGRect(x: bounds.midX - side / 2, y: top - side, width: side, height: side)
      let height = ceil(textLabel.intrinsicContentSize.height)
      textLabel.frame = CGRect(
        x: padding, y: previewView.frame.minY - 4 - height, width: contentWidth, height: height)
    }

    let button: CGFloat = 20
    deleteButton.frame = CGRect(
      x: bounds.maxX - 6 - button, y: bounds.maxY - 6 - button, width: button, height: button)
    pinButton.frame = deleteButton.frame.offsetBy(dx: -(button + 4), dy: 0)
    pinMarker.frame = CGRect(x: bounds.maxX - 6 - 14, y: bounds.maxY - 6 - 14, width: 14, height: 14)

    copiedView.frame = bounds
    if let check = copiedView.viewWithTag(1), let caption = copiedView.viewWithTag(2) {
      check.frame = CGRect(x: bounds.midX - 14, y: bounds.midY - 2, width: 28, height: 28)
      caption.frame = CGRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 16)
    }
  }

  // MARK: - Entrée, sortie, place

  /// Entre en ressort après `delay` : fondu, léger grossissement et petite montée.
  func appear(delay: TimeInterval) {
    guard OverlayAnimation.allowsMotion, let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    layer.setValue(0.88, forKeyPath: "transform.scale")
    layer.setValue(-10, forKeyPath: "transform.translation.y")
    CATransaction.commit()

    let run: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self, !self.isLeaving, let layer = self.layer else { return }
      layer.springAnimate(keyPath: "opacity", to: Float(1))
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
  func leave(delay: TimeInterval = 0, completion: @escaping () -> Void) {
    guard !isLeaving else { return }
    isLeaving = true
    thumbnailTask?.cancel()
    isHidden = false
    guard OverlayAnimation.allowsMotion, let layer else {
      completion()
      return
    }
    let run: @MainActor @Sendable () -> Void = { [weak self] in
      guard let self else { return completion() }
      layer.springAnimate(keyPath: "transform.scale", to: CGFloat(0.8))
      if self.exitsUpward {
        layer.springAnimate(keyPath: "transform.translation.y", to: CGFloat(24))
      }
      layer.springAnimate(keyPath: "opacity", to: Float(0), completion: completion)
    }
    if delay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
    } else {
      run()
    }
  }

  /// Pose la carte ; si elle était déjà posée et que `animated`, elle glisse depuis son
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

  // MARK: - Confirmation de copie

  /// « Copied » : voile et coche pendant un instant. Sans mouvement, c'est seulement posé.
  func showCopied() {
    copiedWork?.cancel()
    copiedView.isHidden = false
    copiedView.layer?.springAnimate(keyPath: "opacity", to: Float(1))
    copiedView.viewWithTag(1)?.layer?.springReveal(y: -4, preset: .gentle)
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.copiedView.layer?.springAnimate(keyPath: "opacity", to: Float(0)) { [weak self] in
        self?.copiedView.isHidden = true
      }
    }
    copiedWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
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
    pinMarker.isHidden = !item.isPinned || hovered
    hoverLayer.springAnimate(keyPath: "opacity", to: hovered ? Float(1) : Float(0))
    for button in [deleteButton, pinButton] {
      if hovered { button.isHidden = false }
      button.layer?.springAnimate(keyPath: "opacity", to: hovered ? Float(1) : Float(0)) {
        [weak self, weak button] in
        if self?.isHovered == false { button?.isHidden = true }
      }
    }
  }

  // MARK: - Souris

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    click()
    return true
  }

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
    guard mouseDownLocation != nil, bounds.contains(convert(event.locationInWindow, from: nil))
    else { return }
    click()
  }

  private func click() {
    showCopied()
    onClick?()
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
        // Surtout vers le haut : c'est un retrait. Sinon le geste appartient à la rangée (défilement
        // horizontal) ou au panneau (balayage d'onglet) et on le leur laisse.
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

  /// La carte suit les doigts ; au-delà du seuil le déplacement se durcit.
  private func followSwipe() {
    let up = max(0, swipeUp)
    let shown = min(up, Self.swipeCommit) + max(0, up - Self.swipeCommit) * 0.25
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.transform = CATransform3DMakeTranslation(0, shown, 0)
    layer?.opacity = Float(1 - min(0.5, shown / 120))
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
      onDelete?()
      return
    }
    layer?.springAnimate(
      keyPath: "transform", to: NSValue(caTransform3D: CATransform3DIdentity), preset: .snappy)
    layer?.springAnimate(keyPath: "opacity", to: Float(1))
  }

  // MARK: - Glisser vers l'extérieur

  private var pasteboardWriter: (any NSPasteboardWriting)? {
    switch item.kind {
    case .text: return item.text.map { $0 as NSString }
    case .link: return item.text.flatMap(ClipboardPreview.url(from:)).map { $0 as NSURL }
    case .image:
      return imageURL.flatMap { NSImage(contentsOf: $0) }
    case .video, .file: return item.fileURL.map { $0 as NSURL }
    }
  }

  private func beginDrag(with event: NSEvent) {
    guard let writer = pasteboardWriter else { return }
    setHovered(false)
    let dragItem = NSDraggingItem(pasteboardWriter: writer)
    dragItem.setDraggingFrame(bounds, contents: snapshot())
    // Le panneau se replie dès que le curseur le quitte : on gèle ce suivi le temps du glisser,
    // sans quoi il se refermerait sous la main qui emporte la carte.
    FileShelfStore.shared.isDraggingOut = true
    beginDraggingSession(with: [dragItem], event: event, source: self)
  }

  /// Image de la carte, pour le curseur pendant le glisser.
  private func snapshot() -> NSImage {
    let image = NSImage(size: bounds.size)
    guard let representation = bitmapImageRepForCachingDisplay(in: bounds),
      let context = NSGraphicsContext(bitmapImageRep: representation)
    else { return image }
    layer?.render(in: context.cgContext)
    image.addRepresentation(representation)
    return image
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    FileShelfStore.shared.isDraggingOut = false
  }
}

/// Petit bouton rond de la carte (✕, épingle) : même style que celui des vignettes du Tray,
/// retour d'appui au ressort.
final class ClipboardCardButton: NSView {

  var onClick: (() -> Void)?

  private let glyph = NSImageView()
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      layer?.springScale(to: isPressed ? 0.88 : 1)
    }
  }

  init(symbol: String, label: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    layer?.borderWidth = 0.5
    glyph.contentTintColor = .white
    glyph.imageScaling = .scaleNone
    addSubview(glyph)
    setAccessibilityRole(.button)
    update(symbol: symbol, label: label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(symbol: String, label: String) {
    glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
    toolTip = label
    setAccessibilityLabel(label)
    needsLayout = true
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
