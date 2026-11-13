import AppKit

/// Matrice d'échelle autour du centre du calque, comme `CALayer.springScale(to:)` la pose.
@MainActor
private func scaleMatrix(for layer: CALayer, _ scale: CGFloat) -> CATransform3D {
  let anchor = CGPoint(
    x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
  var matrix = CATransform3DIdentity
  matrix.m11 = scale
  matrix.m22 = scale
  matrix.m41 = (1 - scale) * (layer.bounds.width / 2 - anchor.x)
  matrix.m42 = (1 - scale) * (layer.bounds.height / 2 - anchor.y)
  return matrix
}

/// Une vue qui répond au clic : le texte et le glyphe qu'elle porte sont des sous-vues, et c'est
/// eux que le clic atteindrait sinon. Retour d'appui au ressort.
final class ColorPickerClickView: NSView {

  var onClick: ((NSEvent) -> Void)?
  var pressScale: CGFloat = 0.94
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      layer?.springScale(to: isPressed ? pressScale : 1)
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isHidden ? nil : bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    ButtonSound.shared.playClick()
    onClick?(NSEvent())
    return true
  }

  override func mouseDown(with event: NSEvent) { isPressed = true }

  override func mouseDragged(with event: NSEvent) {
    isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    let inside = bounds.contains(convert(event.locationInWindow, from: nil))
    isPressed = false
    guard inside else { return }
    ButtonSound.shared.playClick()
    onClick?(event)
  }
}

/// Une surface de couleur sur laquelle on clique et que l'on peut emporter : le glisser sort la
/// couleur vers une autre app (couleur native et `#RRGGBB` en texte).
class ColorDraggableView: NSView, NSDraggingSource {

  var dragColor: PickedColor?
  var onClick: ((NSEvent) -> Void)?
  /// Appelé quand un glisser vers l'extérieur démarre.
  var onDragBegan: (() -> Void)?
  var pressScale: CGFloat = 0.96

  private var mouseDownLocation: NSPoint?
  private let dragThreshold: CGFloat = 3

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    onClick?(NSEvent())
    return true
  }

  override func mouseDown(with event: NSEvent) {
    mouseDownLocation = convert(event.locationInWindow, from: nil)
    layer?.springScale(to: pressScale)
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
    ButtonSound.shared.playClick()
    onClick?(event)
  }

  private func beginDrag(with event: NSEvent) {
    guard let color = dragColor else { return }
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(color.hexString, forType: .string)
    if let list = color.nsColor.pasteboardPropertyList(forType: .color) {
      pasteboardItem.setPropertyList(list, forType: .color)
    }
    let side: CGFloat = 36
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
      color.nsColor.setFill()
      path.fill()
      NSColor.white.withAlphaComponent(0.35).setStroke()
      path.lineWidth = 1
      path.stroke()
      return true
    }
    let dragItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
    let origin = convert(event.locationInWindow, from: nil)
    dragItem.setDraggingFrame(
      NSRect(x: origin.x - side / 2, y: origin.y - side / 2, width: side, height: side),
      contents: image)
    onDragBegan?()
    // Le panneau se replie dès que le curseur le quitte : on gèle ce suivi le temps du glisser.
    FileShelfStore.shared.isDraggingOut = true
    beginDraggingSession(with: [dragItem], event: event, source: self)
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

/// Une pastille de l'historique : clic pour la reprendre, glisser pour l'emporter, ✕ au survol.
final class ColorChipView: ColorDraggableView {

  var onRemove: (() -> Void)?

  private let removeButton = ColorPickerClickView()
  private let removeGlyph = NSImageView()
  private var trackingArea: NSTrackingArea?
  private var isHovered = false
  private var isShrunk = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    pressScale = 0.88
    layer?.cornerRadius = 6
    layer?.cornerCurve = .continuous
    removeButton.wantsLayer = true
    removeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
    removeButton.layer?.opacity = 0
    removeButton.isHidden = true
    removeButton.onClick = { [weak self] _ in self?.onRemove?() }
    removeButton.toolTip = "Remove"
    removeButton.setAccessibilityLabel("Remove")
    removeGlyph.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 6, weight: .heavy))
    removeGlyph.contentTintColor = .white
    removeButton.addSubview(removeGlyph)
    addSubview(removeButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Pose la couleur de la case (`nil` : case vide, masquée).
  func set(color: PickedColor?, selected: Bool, visible: Bool, animated: Bool) {
    dragColor = color
    isHidden = color == nil || !visible
    guard let color else { return }
    resetIfShrunk()
    if animated {
      layer?.springAnimate(keyPath: "backgroundColor", to: color.nsColor.cgColor)
    } else {
      layer?.backgroundColor = color.nsColor.cgColor
    }
    layer?.borderWidth = selected ? 1.5 : 0.5
    layer?.borderColor =
      (selected ? NSColor.white : NSColor.white.withAlphaComponent(0.18)).cgColor
    toolTip = color.hexString
    setAccessibilityLabel(color.hexString)
  }

  /// Arrivée d'une nouvelle couleur : elle grossit de 0,6 à 1 en fondu.
  func popIn() {
    guard let layer, OverlayAnimation.allowsMotion else { return }
    layer.springAnimate(
      keyPath: "transform", to: NSValue(caTransform3D: CATransform3DIdentity),
      from: NSValue(caTransform3D: scaleMatrix(for: layer, 0.6)))
    layer.springAnimate(keyPath: "opacity", to: Float(1), from: Float(0))
  }

  /// Départ : la pastille rétrécit et s'efface, puis `completion` retire la couleur de l'état.
  func shrinkOut(completion: @escaping () -> Void) {
    guard let layer else { return completion() }
    isShrunk = true
    setHovered(false)
    layer.springAnimate(
      keyPath: "transform",
      to: NSValue(caTransform3D: scaleMatrix(for: layer, 0.6)))
    layer.springAnimate(keyPath: "opacity", to: Float(0), completion: completion)
  }

  private func resetIfShrunk() {
    guard isShrunk, let layer else { return }
    isShrunk = false
    layer.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.transform = CATransform3DIdentity
    layer.opacity = 1
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    let side: CGFloat = 11
    removeButton.frame = NSRect(
      x: bounds.maxX - side - 1, y: bounds.maxY - side - 1, width: side, height: side)
    removeButton.layer?.cornerRadius = side / 2
    removeGlyph.frame = removeButton.bounds
  }

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
    guard hovered != isHovered else { return }
    isHovered = hovered
    if hovered { removeButton.isHidden = false }
    removeButton.layer?.springAnimate(keyPath: "opacity", to: hovered ? Float(1) : Float(0)) {
      [weak self] in
      if self?.isHovered == false { self?.removeButton.isHidden = true }
    }
  }
}

/// Le grand aperçu : clic pour copier le HEX, glisser pour emporter la couleur, défilement pour
/// régler luminosité (vertical) et teinte (horizontal, ou ⇧ + vertical).
final class ColorSwatchView: ColorDraggableView {

  /// Boutons posés sur l'aperçu : ils reçoivent leur clic, le reste appartient à l'aperçu.
  var overlayControls: [NSView] = []
  var onScroll: ((_ dx: CGFloat, _ dy: CGFloat, _ shift: Bool) -> Void)?

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard !isHidden, bounds.contains(local) else { return nil }
    for control in overlayControls where !control.isHidden && control.frame.contains(local) {
      return control.hitTest(local)
    }
    return self
  }

  override func scrollWheel(with event: NSEvent) {
    guard dragColor != nil else { return super.scrollWheel(with: event) }
    let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 6
    onScroll?(
      event.scrollingDeltaX * scale, event.scrollingDeltaY * scale,
      event.modifierFlags.contains(.shift))
  }
}

/// Un contrôle à trois cases (HEX, RGB, HSL) dont la sélection glisse d'une case à l'autre.
final class ColorFormatControl: NSView {

  var onSelect: ((ColorFormat) -> Void)?

  private let formats = ColorFormat.allCases
  private let selection = NSView()
  private let labels: [NSTextField]
  private(set) var selected: ColorFormat = .hex
  private var palette = OverlayPalette.resolved(for: .currentDrawing())

  override init(frame frameRect: NSRect) {
    labels = ColorFormat.allCases.map { NSTextField(labelWithString: $0.title) }
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    selection.wantsLayer = true
    selection.layer?.cornerRadius = 6
    selection.layer?.cornerCurve = .continuous
    addSubview(selection)
    for label in labels {
      label.font = .systemFont(ofSize: 10, weight: .semibold)
      label.alignment = .center
      addSubview(label)
    }
    setAccessibilityRole(.radioGroup)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    layer?.backgroundColor = palette.tabCapsuleFill
    selection.layer?.backgroundColor = palette.tabPillFill
    refreshLabels()
  }

  func setSelected(_ format: ColorFormat, animated: Bool) {
    guard format != selected else { return }
    let oldCenter = selectionFrame(for: selected).midX
    selected = format
    let target = selectionFrame(for: format)
    selection.frame = target
    if animated {
      selection.layer?.springAnimate(keyPath: "position.x", to: target.midX, from: oldCenter)
    }
    refreshLabels()
  }

  private func refreshLabels() {
    for (format, label) in zip(formats, labels) {
      label.textColor = format == selected ? palette.tabActiveContent : palette.tabInactiveContent
    }
  }

  private func selectionFrame(for format: ColorFormat) -> NSRect {
    let width = bounds.width / CGFloat(formats.count)
    let index = CGFloat(formats.firstIndex(of: format) ?? 0)
    return NSRect(x: index * width + 2, y: 2, width: width - 4, height: bounds.height - 4)
  }

  override func layout() {
    super.layout()
    selection.frame = selectionFrame(for: selected)
    let width = bounds.width / CGFloat(formats.count)
    for (index, label) in labels.enumerated() {
      let height = label.intrinsicContentSize.height
      label.frame = NSRect(
        x: CGFloat(index) * width, y: bounds.midY - height / 2, width: width, height: height)
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isHidden ? nil : bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    guard bounds.contains(location) else { return }
    let index = min(formats.count - 1, max(0, Int(location.x / (bounds.width / 3))))
    let format = formats[index]
    guard format != selected else { return }
    ButtonSound.shared.playClick()
    setSelected(format, animated: window != nil)
    onSelect?(format)
  }
}

/// Le champ de la valeur copiable : un clic copie, avec une confirmation qui recouvre la valeur.
final class ColorValuePill: NSView {

  var onCopy: ((NSEvent.ModifierFlags) -> Void)?

  private let valueLabel = NSTextField(labelWithString: "")
  private let copyIcon = NSImageView()
  private let copiedLabel = NSTextField(labelWithString: "")
  private var copiedWork: DispatchWorkItem?
  private var palette = OverlayPalette.resolved(for: .currentDrawing())
  private var hasValue = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.cornerCurve = .continuous
    valueLabel.wantsLayer = true
    valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    valueLabel.lineBreakMode = .byTruncatingTail
    copyIcon.wantsLayer = true
    copiedLabel.wantsLayer = true
    copiedLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    copiedLabel.alignment = .center
    copiedLabel.layer?.opacity = 0
    copiedLabel.isHidden = true
    for view in [valueLabel, copyIcon, copiedLabel] { addSubview(view) }
    setAccessibilityRole(.button)
    showCopyIcon(copied: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    layer?.backgroundColor = palette.tabCapsuleFill
    refreshTint()
  }

  private func refreshTint() {
    valueLabel.textColor = hasValue ? palette.tabActiveContent : palette.tabInactiveContent
    copyIcon.contentTintColor = palette.tabInactiveContent
    copiedLabel.textColor = palette.tabActiveContent
    copyIcon.isHidden = !hasValue
  }

  /// `nil` : pas encore de couleur.
  func setValue(_ text: String?, animated: Bool) {
    hasValue = text != nil
    let newText = text ?? "Nothing picked yet"
    if animated, newText != valueLabel.stringValue { valueLabel.layer?.crossfadeIn(delay: 0) }
    valueLabel.stringValue = newText
    toolTip = hasValue ? "Click to copy · ⌥ Swift code · ⇧⌥ NSColor" : nil
    setAccessibilityLabel(newText)
    refreshTint()
  }

  /// Confirmation : la légende recouvre la valeur un instant. Un nouveau clic relance le délai.
  func showCopied(_ caption: String) {
    copiedWork?.cancel()
    copiedLabel.stringValue = caption
    copiedLabel.isHidden = false
    copiedLabel.layer?.springAnimate(keyPath: "opacity", to: Float(1))
    copiedLabel.layer?.springReveal(y: -4, preset: .gentle)
    valueLabel.layer?.springAnimate(keyPath: "opacity", to: Float(0))
    copyIcon.layer?.springAnimate(keyPath: "opacity", to: Float(0))
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.valueLabel.layer?.springAnimate(keyPath: "opacity", to: Float(1))
      self.copyIcon.layer?.springAnimate(keyPath: "opacity", to: Float(1))
      self.copiedLabel.layer?.springAnimate(keyPath: "opacity", to: Float(0)) { [weak self] in
        self?.copiedLabel.isHidden = true
      }
    }
    copiedWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
  }

  private func showCopyIcon(copied: Bool) {
    copyIcon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
  }

  override func layout() {
    super.layout()
    let height = valueLabel.intrinsicContentSize.height
    valueLabel.frame = NSRect(
      x: 12, y: bounds.midY - height / 2, width: max(0, bounds.width - 12 - 34), height: height)
    copyIcon.frame = NSRect(x: bounds.maxX - 28, y: bounds.midY - 7, width: 14, height: 14)
    let captionHeight = copiedLabel.intrinsicContentSize.height
    copiedLabel.frame = NSRect(
      x: 0, y: bounds.midY - captionHeight / 2, width: bounds.width, height: captionHeight)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isHidden ? nil : bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    guard hasValue else { return }
    layer?.springScale(to: 0.98)
  }

  override func mouseUp(with event: NSEvent) {
    layer?.springScale(to: 1)
    guard hasValue, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    ButtonSound.shared.playClick()
    onCopy?(event.modifierFlags)
  }
}

/// Une rangée de pastilles qui accepte une couleur déposée (d'une autre app ou de l'aperçu).
final class ColorDropStrip: NSView {

  var onDrop: ((PickedColor) -> Void)? {
    didSet {
      if onDrop != nil { registerForDraggedTypes([.color, .string]) } else { unregisterDraggedTypes() }
    }
  }
  var highlightColor = NSColor.white.withAlphaComponent(0.08)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func color(from pasteboard: NSPasteboard) -> PickedColor? {
    if let ns = (pasteboard.readObjects(forClasses: [NSColor.self]) as? [NSColor])?.first,
      let color = PickedColor(ns)
    {
      return color
    }
    return pasteboard.string(forType: .string).flatMap {
      PickedColor(hex: $0.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private func setHighlighted(_ on: Bool) {
    layer?.springAnimate(
      keyPath: "backgroundColor", to: (on ? highlightColor : NSColor.clear).cgColor)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard color(from: sender.draggingPasteboard) != nil else { return [] }
    setHighlighted(true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { setHighlighted(false) }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    setHighlighted(false)
    guard let color = color(from: sender.draggingPasteboard) else { return false }
    onDrop?(color)
    return true
  }
}
