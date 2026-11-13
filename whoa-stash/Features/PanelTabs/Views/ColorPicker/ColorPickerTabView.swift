import AppKit

/// L'onglet Color : à gauche le grand aperçu (clic = copier le HEX, glisser = emporter, défiler =
/// régler luminosité et teinte) avec « Pick » et l'étoile, à droite le choix d'écriture, la valeur
/// copiable, puis les rangées « Recent » et « Saved ».
final class ColorPickerTabView: NSView {

  var onAction: ((ColorPickerAction) -> Void)?

  private var state = ColorPickerState()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())

  private let swatch = ColorSwatchView()
  private let emptyHint = NSTextField(wrappingLabelWithString: "Pick a colour\nfrom the screen")
  private let contrastLabel = NSTextField(labelWithString: "")
  private let starButton = ColorPickerClickView()
  private let starIcon = NSImageView()
  private let pickButton = ColorPickerClickView()
  private let pickIcon = NSImageView()
  private let pickLabel = NSTextField(labelWithString: "Pick")

  private let formatControl = ColorFormatControl()
  private let pill = ColorValuePill()

  private let recentRow = ColorDropStrip()
  private let recentLabel = NSTextField(labelWithString: "Recent")
  private let recentHint = NSTextField(labelWithString: "Picked colours show here")
  private let clearButton = ColorPickerClickView()
  private let clearLabel = NSTextField(labelWithString: "Clear")
  private let recentChips: [ColorChipView]

  private let savedRow = ColorDropStrip()
  private let savedLabel = NSTextField(labelWithString: "Saved")
  private let savedHint = NSTextField(labelWithString: "Drop a colour or tap ★")
  private let savedChips: [ColorChipView]

  /// Teinte, saturation et luminosité de travail pendant un défilement : elles évitent la dérive
  /// d'arrondi des 8 bits. Remises à zéro quand la couleur change par ailleurs.
  private var working: (hue: Double, saturation: Double, brightness: Double)?
  private var lastAdjusted: PickedColor?

  private static let rowHeight: CGFloat = 20
  private static let rowGap: CGFloat = 4
  private static let chipSize: CGFloat = 18
  private static let chipPitch: CGFloat = 23
  private static let labelWidth: CGFloat = 46
  private static let clearWidth: CGFloat = 38

  override init(frame: NSRect) {
    recentChips = (0..<ColorPickerViewModel.recentLimit).map { _ in ColorChipView() }
    savedChips = (0..<ColorPickerViewModel.savedLimit).map { _ in ColorChipView() }
    super.init(frame: frame)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Mise en place

  private func setUp() {
    setUpSwatch()

    formatControl.onSelect = { [weak self] in self?.onAction?(.selectFormat($0)) }
    addSubview(formatControl)

    pill.onCopy = { [weak self] flags in self?.copyValue(flags) }
    addSubview(pill)

    for label in [recentLabel, savedLabel] { label.font = .systemFont(ofSize: 10, weight: .medium) }
    for hint in [recentHint, savedHint] {
      hint.font = .systemFont(ofSize: 10, weight: .regular)
      hint.lineBreakMode = .byTruncatingTail
    }
    clearLabel.font = .systemFont(ofSize: 10, weight: .medium)
    clearLabel.alignment = .right
    clearButton.addSubview(clearLabel)
    clearButton.onClick = { [weak self] _ in self?.onAction?(.clearRecent) }

    recentRow.addSubview(recentLabel)
    recentRow.addSubview(recentHint)
    savedRow.addSubview(savedLabel)
    savedRow.addSubview(savedHint)
    for chip in recentChips {
      chip.onClick = { [weak self, weak chip] _ in
        guard let color = chip?.dragColor else { return }
        self?.onAction?(.select(color))
      }
      chip.onRemove = { [weak self, weak chip] in
        guard let color = chip?.dragColor else { return }
        chip?.shrinkOut { self?.onAction?(.removeRecent(color)) }
      }
      recentRow.addSubview(chip)
    }
    for chip in savedChips {
      chip.onClick = { [weak self, weak chip] _ in
        guard let color = chip?.dragColor else { return }
        self?.onAction?(.select(color))
      }
      chip.onRemove = { [weak self, weak chip] in
        guard let color = chip?.dragColor else { return }
        chip?.shrinkOut { self?.onAction?(.removeSaved(color)) }
      }
      savedRow.addSubview(chip)
    }
    recentRow.addSubview(clearButton)
    savedRow.onDrop = { [weak self] in self?.onAction?(.save($0)) }
    addSubview(recentRow)
    addSubview(savedRow)

    applyPalette(palette)
    apply(state)
  }

  private func setUpSwatch() {
    swatch.layer?.cornerRadius = 18
    swatch.layer?.cornerCurve = .continuous
    swatch.layer?.borderWidth = 0.5
    swatch.toolTip = "Click to copy HEX · scroll to adjust brightness, ⇧ or sideways for hue · drag to export"
    swatch.setAccessibilityLabel("Colour preview")
    swatch.onClick = { [weak self] _ in self?.copyHex() }
    swatch.onDragBegan = { [weak self] in self?.onAction?(.commit) }
    swatch.onScroll = { [weak self] dx, dy, shift in self?.adjust(dx: dx, dy: dy, shift: shift) }

    emptyHint.font = .systemFont(ofSize: 11, weight: .medium)
    emptyHint.alignment = .center
    emptyHint.isSelectable = false
    contrastLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    contrastLabel.wantsLayer = true
    contrastLabel.toolTip = "Best WCAG contrast of text on this colour"

    starIcon.imageScaling = .scaleNone
    starButton.addSubview(starIcon)
    starButton.wantsLayer = true
    starButton.toolTip = "Save colour"
    starButton.setAccessibilityLabel("Save colour")
    starButton.onClick = { [weak self] _ in
      self?.onAction?(.commit)
      self?.onAction?(.toggleSaved)
    }

    pickButton.wantsLayer = true
    pickButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    pickButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    pickButton.layer?.borderWidth = 0.5
    pickButton.onClick = { [weak self] _ in self?.onAction?(.pick) }
    pickIcon.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Pick")?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
    pickIcon.contentTintColor = .white
    pickLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    pickLabel.textColor = .white
    pickButton.addSubview(pickIcon)
    pickButton.addSubview(pickLabel)

    swatch.addSubview(emptyHint)
    swatch.addSubview(contrastLabel)
    swatch.addSubview(starButton)
    swatch.addSubview(pickButton)
    swatch.overlayControls = [starButton, pickButton]
    addSubview(swatch)
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    formatControl.applyPalette(palette)
    pill.applyPalette(palette)
    emptyHint.textColor = palette.tabInactiveContent
    for label in [recentLabel, savedLabel, clearLabel] { label.textColor = palette.tabInactiveContent }
    for hint in [recentHint, savedHint] { hint.textColor = palette.tabInactiveContent.withAlphaComponent(0.7) }
    swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    savedRow.highlightColor = NSColor.white.withAlphaComponent(0.08)
    refreshSwatchFill(animated: false)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
  }

  // MARK: - État

  private func refreshSwatchFill(animated: Bool) {
    let fill: CGColor = state.current?.nsColor.cgColor ?? palette.tabCapsuleFill
    if animated {
      swatch.layer?.springAnimate(keyPath: "backgroundColor", to: fill)
    } else {
      swatch.layer?.backgroundColor = fill
    }
  }

  func apply(_ newState: ColorPickerState) {
    let previous = state
    state = newState
    let animated = window != nil
    let color = newState.current

    swatch.dragColor = color
    refreshSwatchFill(animated: animated && color != previous.current)
    emptyHint.isHidden = color != nil
    contrastLabel.isHidden = color == nil
    starButton.isHidden = color == nil
    if let color {
      let contrast = color.contrast
      let content: NSColor = contrast.onWhite ? .white : .black
      let text = String(format: "Aa %.1f %@", contrast.ratio, contrast.grade)
      if animated, contrastLabel.stringValue != text { contrastLabel.layer?.crossfadeIn(delay: 0) }
      contrastLabel.stringValue = text
      contrastLabel.textColor = content.withAlphaComponent(0.85)
      starIcon.contentTintColor = content
      let saved = newState.isCurrentSaved
      let symbol = saved ? "star.fill" : "star"
      if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
      {
        if starIcon.image != nil, animated, OverlayAnimation.allowsMotion {
          starIcon.setSymbolImage(image, contentTransition: .replace)
        } else {
          starIcon.image = image
        }
      }
      starButton.toolTip = saved ? "Remove from Saved" : "Save colour"
      starButton.setAccessibilityLabel(starButton.toolTip)
    }

    formatControl.setSelected(newState.format, animated: animated)
    pill.setValue(color?.string(for: newState.format), animated: animated && color != previous.current)

    updateChips(
      recentChips, colors: newState.recent, previous: previous.recent, selected: color,
      animated: animated)
    updateChips(
      savedChips, colors: newState.saved, previous: previous.saved, selected: color,
      animated: animated)
    recentHint.isHidden = !newState.recent.isEmpty
    savedHint.isHidden = !newState.saved.isEmpty
    clearButton.isHidden = newState.recent.isEmpty
    needsLayout = true
  }

  private func updateChips(
    _ chips: [ColorChipView], colors: [PickedColor], previous: [PickedColor],
    selected: PickedColor?, animated: Bool
  ) {
    let fitting = visibleChipCount
    for (index, chip) in chips.enumerated() {
      let color = colors.indices.contains(index) ? colors[index] : nil
      chip.set(color: color, selected: color != nil && color == selected, visible: index < fitting, animated: animated)
      if animated, let color, !previous.contains(color) { chip.popIn() }
    }
  }

  // MARK: - Gestes

  private func writeToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func copyValue(_ flags: NSEvent.ModifierFlags) {
    guard let color = state.current else { return }
    let text: String
    let caption: String
    if flags.contains(.option) && flags.contains(.shift) {
      text = color.nsColorCode
      caption = "Copied NSColor"
    } else if flags.contains(.option) {
      text = color.swiftUICode
      caption = "Copied Swift"
    } else {
      text = color.string(for: state.format)
      caption = "Copied \(state.format.title)"
    }
    writeToPasteboard(text)
    pill.showCopied(caption)
    onAction?(.commit)
  }

  private func copyHex() {
    guard let color = state.current else { return }
    writeToPasteboard(color.hexString)
    pill.showCopied("Copied HEX")
    onAction?(.commit)
  }

  /// Défilement sur l'aperçu : vertical = luminosité, horizontal (ou ⇧ + vertical) = teinte.
  private func adjust(dx: CGFloat, dy: CGFloat, shift: Bool) {
    guard let current = state.current else { return }
    if working == nil || lastAdjusted != current { working = current.hsb }
    guard var next = working else { return }
    let previousSector = Int(next.hue / 30)
    if shift || abs(dx) > abs(dy) {
      let delta = abs(dx) > abs(dy) ? dx : dy
      next.hue = (next.hue - Double(delta) * 0.6).truncatingRemainder(dividingBy: 360)
      if next.hue < 0 { next.hue += 360 }
    } else {
      next.brightness = min(max(next.brightness + Double(dy) * 0.004, 0), 1)
    }
    working = next
    let adjusted = PickedColor(
      hue: next.hue, saturation: next.saturation, brightness: next.brightness)
    if Int(next.hue / 30) != previousSector {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    guard adjusted != current else { return }
    lastAdjusted = adjusted
    onAction?(.adjust(adjusted))
  }

  // MARK: - Mise en page

  /// Pastilles visibles par rangée : ce que la largeur laisse après l'étiquette et « Clear ».
  private var visibleChipCount: Int {
    let rowWidth = max(0, bounds.width - rightColumnX)
    let room = rowWidth - Self.labelWidth - Self.clearWidth + (Self.chipPitch - Self.chipSize)
    return min(ColorPickerViewModel.recentLimit, max(0, Int(room / Self.chipPitch)))
  }

  private var swatchSide: CGFloat { min(bounds.height - 12, bounds.width >= 420 ? 132 : 108) }
  private var rightColumnX: CGFloat { swatchSide + 14 }

  override func layout() {
    super.layout()
    let side = swatchSide
    let top = bounds.midY + side / 2
    let bottom = top - side
    swatch.frame = NSRect(x: 0, y: bottom, width: side, height: side)
    layoutSwatchContents(side: side)

    let x = rightColumnX
    let width = max(0, bounds.width - x)
    formatControl.frame = NSRect(x: x, y: top - 22, width: min(width, 192), height: 22)
    pill.frame = NSRect(x: x, y: top - 22 - 5 - 28, width: width, height: 28)

    savedRow.frame = NSRect(x: x, y: bottom, width: width, height: Self.rowHeight)
    recentRow.frame = NSRect(
      x: x, y: bottom + Self.rowHeight + Self.rowGap, width: width, height: Self.rowHeight)
    layoutRow(recentRow, label: recentLabel, hint: recentHint, chips: recentChips)
    layoutRow(savedRow, label: savedLabel, hint: savedHint, chips: savedChips)
    clearButton.frame = NSRect(
      x: width - Self.clearWidth, y: 0, width: Self.clearWidth, height: Self.rowHeight)
    clearLabel.frame = clearButton.bounds.insetBy(dx: 0, dy: 3)
  }

  private func layoutSwatchContents(side: CGFloat) {
    let hintSize = emptyHint.sizeThatFits(NSSize(width: side - 16, height: 60))
    emptyHint.frame = NSRect(
      x: 8, y: side / 2 + 2, width: side - 16, height: ceil(hintSize.height))
    let labelSize = contrastLabel.intrinsicContentSize
    contrastLabel.frame = NSRect(
      x: 10, y: side - 10 - ceil(labelSize.height), width: ceil(labelSize.width) + 4,
      height: ceil(labelSize.height))
    starButton.frame = NSRect(x: side - 8 - 26, y: side - 8 - 26, width: 26, height: 26)
    starIcon.frame = starButton.bounds
    let buttonHeight: CGFloat = 26
    let buttonWidth: CGFloat = 76
    pickButton.frame = NSRect(
      x: (side - buttonWidth) / 2, y: 8, width: buttonWidth, height: buttonHeight)
    pickButton.layer?.cornerRadius = buttonHeight / 2
    let text = pickLabel.intrinsicContentSize
    let content = 13 + 5 + ceil(text.width)
    let startX = (buttonWidth - content) / 2
    pickIcon.frame = NSRect(x: startX, y: buttonHeight / 2 - 6.5, width: 13, height: 13)
    pickLabel.frame = NSRect(
      x: startX + 18, y: buttonHeight / 2 - text.height / 2, width: ceil(text.width) + 2,
      height: text.height)
    // L'aperçu vide ne porte pas de lecture de couleur : « Pick » reste en bas.
  }

  private func layoutRow(
    _ row: NSView, label: NSTextField, hint: NSTextField, chips: [ColorChipView]
  ) {
    let labelHeight = label.intrinsicContentSize.height
    label.frame = NSRect(
      x: 4, y: row.bounds.midY - labelHeight / 2, width: Self.labelWidth - 4, height: labelHeight)
    let hintHeight = hint.intrinsicContentSize.height
    let hintRoom = row.bounds.width - Self.labelWidth - (row === recentRow ? Self.clearWidth : 0)
    hint.frame = NSRect(
      x: Self.labelWidth, y: row.bounds.midY - hintHeight / 2, width: max(0, hintRoom),
      height: hintHeight)
    for (index, chip) in chips.enumerated() {
      chip.frame = NSRect(
        x: Self.labelWidth + CGFloat(index) * Self.chipPitch,
        y: row.bounds.midY - Self.chipSize / 2, width: Self.chipSize, height: Self.chipSize)
    }
  }
}
