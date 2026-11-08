import AppKit

/// Teinte du bouton « Pick », le bleu de la maquette : il ne suit pas l'accent des Préférences.
enum ColorPickerStyle {
  static let accent = NSColor(srgbRed: 0.20, green: 0.43, blue: 0.90, alpha: 1)
}

/// L'onglet Color : à gauche l'aperçu de la couleur et « Pick », au centre ses trois écritures
/// (HEX, RGB, HSL) avec un bouton de copie chacune, à droite les couleurs récentes.
final class ColorPickerTabView: NSView {

  var onAction: ((ColorPickerAction) -> Void)?

  private var state = ColorPickerState()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())

  private let swatch = NSView()
  private let pickButton = ColorPickerClickView()
  private let pickIcon = NSImageView()
  private let pickLabel = NSTextField(labelWithString: "Pick")
  private let rows: [FormatRow]
  private let divider = NSView()
  private let recentLabel = NSTextField(labelWithString: "Recent")
  private let clearButton = ColorPickerClickView()
  private let clearLabel = NSTextField(labelWithString: "Clear")
  private let dots: [ColorPickerClickView]

  private static let swatchSize: CGFloat = 70
  private static let rowHeight: CGFloat = 34
  private static let rowGap: CGFloat = 6
  private static let dotSize: CGFloat = 16
  private static let dotGap: CGFloat = 5
  private static let recentWidth: CGFloat =
    CGFloat(ColorPickerViewModel.recentLimit) * (dotSize + dotGap) - dotGap + 6

  override init(frame: NSRect) {
    rows = [FormatRow(title: "HEX"), FormatRow(title: "RGB"), FormatRow(title: "HSL")]
    dots = (0..<ColorPickerViewModel.recentLimit).map { _ in ColorPickerClickView() }
    super.init(frame: frame)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    swatch.wantsLayer = true
    swatch.layer?.cornerRadius = 16
    swatch.layer?.cornerCurve = .continuous
    addSubview(swatch)

    pickButton.wantsLayer = true
    pickButton.layer?.backgroundColor = ColorPickerStyle.accent.cgColor
    pickButton.onClick = { [weak self] in self?.onAction?(.pick) }
    pickIcon.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Pick")?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
    pickIcon.contentTintColor = .white
    pickLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    pickLabel.textColor = .white
    pickButton.addSubview(pickIcon)
    pickButton.addSubview(pickLabel)
    addSubview(pickButton)

    for row in rows {
      addSubview(row)
    }
    rows[0].onCopy = { [weak self] in self?.copy(self?.state.current.hexString) }
    rows[1].onCopy = { [weak self] in self?.copy(self?.state.current.rgbString) }
    rows[2].onCopy = { [weak self] in self?.copy(self?.state.current.hslString) }

    divider.wantsLayer = true
    addSubview(divider)

    recentLabel.font = .systemFont(ofSize: 11, weight: .medium)
    clearLabel.font = .systemFont(ofSize: 11, weight: .medium)
    clearLabel.alignment = .right
    clearButton.addSubview(clearLabel)
    clearButton.onClick = { [weak self] in self?.onAction?(.clearRecent) }
    addSubview(recentLabel)
    addSubview(clearButton)

    for (index, dot) in dots.enumerated() {
      dot.wantsLayer = true
      dot.onClick = { [weak self] in
        guard let self, self.state.recent.indices.contains(index) else { return }
        self.onAction?(.select(self.state.recent[index]))
      }
      addSubview(dot)
    }

    applyPalette(palette)
    apply(state)
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    divider.layer?.backgroundColor = palette.strokeColor
    rows.forEach { $0.applyPalette(palette) }
    recentLabel.textColor = palette.tabInactiveContent
    clearLabel.textColor = palette.tabInactiveContent
  }

  func apply(_ newState: ColorPickerState) {
    let previousColor = state.current
    state = newState
    let color = newState.current
    if color != previousColor, window != nil {
      swatch.layer?.springAnimate(keyPath: "backgroundColor", to: color.nsColor.cgColor)
    } else {
      swatch.layer?.backgroundColor = color.nsColor.cgColor
    }
    rows[0].value = color.hexString
    rows[1].value = color.rgbString
    rows[2].value = color.hslString
    for (index, dot) in dots.enumerated() {
      let recent = newState.recent.indices.contains(index) ? newState.recent[index] : nil
      dot.isHidden = recent == nil
      dot.layer?.backgroundColor = recent?.nsColor.cgColor
      let selected = recent == color
      dot.layer?.borderWidth = selected ? 2 : 0
      dot.layer?.borderColor = NSColor.white.cgColor
    }
    clearButton.isHidden = newState.recent.isEmpty
  }

  private func copy(_ text: String?) {
    guard let text else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
  }

  override func layout() {
    super.layout()

    // Colonne de gauche : l'aperçu puis « Pick », centrés ensemble sur la hauteur.
    let buttonHeight: CGFloat = 28
    let leftHeight = Self.swatchSize + 8 + buttonHeight
    let leftTop = bounds.midY + leftHeight / 2
    swatch.frame = NSRect(
      x: 0, y: leftTop - Self.swatchSize, width: Self.swatchSize, height: Self.swatchSize)
    pickButton.frame = NSRect(
      x: 0, y: swatch.frame.minY - 8 - buttonHeight, width: Self.swatchSize, height: buttonHeight)
    pickButton.layer?.cornerRadius = buttonHeight / 2
    let labelSize = pickLabel.intrinsicContentSize
    let content = 13 + 4 + ceil(labelSize.width)
    let startX = max(4, (pickButton.bounds.width - content) / 2)
    pickIcon.frame = NSRect(x: startX, y: pickButton.bounds.midY - 6.5, width: 13, height: 13)
    pickLabel.frame = NSRect(
      x: startX + 17, y: pickButton.bounds.midY - labelSize.height / 2,
      width: ceil(labelSize.width) + 4, height: labelSize.height)

    // Colonne de droite : l'en-tête « Recent / Clear », puis la rangée de pastilles.
    let rightX = bounds.maxX - Self.recentWidth
    let dividerX = rightX - 12
    divider.frame = NSRect(
      x: dividerX, y: bounds.minY + 14, width: 1, height: max(0, bounds.height - 28))
    recentLabel.frame = NSRect(x: rightX, y: bounds.midY + 8, width: 60, height: 16)
    clearButton.frame = NSRect(x: bounds.maxX - 40, y: bounds.midY + 8, width: 40, height: 16)
    clearLabel.frame = clearButton.bounds
    for (index, dot) in dots.enumerated() {
      dot.frame = NSRect(
        x: rightX + 3 + CGFloat(index) * (Self.dotSize + Self.dotGap), y: bounds.midY - 18,
        width: Self.dotSize, height: Self.dotSize)
      dot.layer?.cornerRadius = Self.dotSize / 2
    }

    // Colonne du milieu : les trois écritures, centrées sur la hauteur.
    let rowsX = swatch.frame.maxX + 12
    let rowsWidth = max(0, dividerX - 12 - rowsX)
    let rowsHeight = CGFloat(rows.count) * Self.rowHeight + CGFloat(rows.count - 1) * Self.rowGap
    var y = bounds.midY + rowsHeight / 2 - Self.rowHeight
    for row in rows {
      row.frame = NSRect(x: rowsX, y: y, width: rowsWidth, height: Self.rowHeight)
      y -= Self.rowHeight + Self.rowGap
    }
  }
}

/// Une vue qui répond au clic : le texte et le glyphe qu'elle porte sont des sous-vues, et c'est
/// eux que le clic atteindrait sinon.
private final class ColorPickerClickView: NSView {

  var onClick: (() -> Void)?
  private var isPressed = false {
    didSet { alphaValue = isPressed ? 0.65 : 1 }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isHidden ? nil : bounds.contains(convert(point, from: superview)) ? self : nil
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
    onClick?()
  }
}

/// Une ligne « HEX #0A6FE8 » avec son bouton de copie, qui passe un instant en coche.
private final class FormatRow: NSView {

  var onCopy: (() -> Void)?

  var value = "" {
    didSet { valueLabel.stringValue = value }
  }

  private let titleLabel: NSTextField
  private let valueLabel = NSTextField(labelWithString: "")
  private let copyButton = ColorPickerClickView()
  private let copyIcon = NSImageView()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())

  init(title: String) {
    titleLabel = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 9
    layer?.cornerCurve = .continuous

    titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
    valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    valueLabel.lineBreakMode = .byTruncatingTail
    copyButton.onClick = { [weak self] in self?.copyTapped() }
    copyButton.addSubview(copyIcon)
    for view in [titleLabel, valueLabel, copyButton] { addSubview(view) }
    showCopyIcon(copied: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    layer?.backgroundColor = palette.tabCapsuleFill
    titleLabel.textColor = palette.tabInactiveContent
    valueLabel.textColor = palette.tabActiveContent
    copyIcon.contentTintColor = palette.tabInactiveContent
  }

  private func copyTapped() {
    onCopy?()
    showCopyIcon(copied: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.showCopyIcon(copied: false)
    }
  }

  private func showCopyIcon(copied: Bool) {
    guard
      let image = NSImage(
        systemSymbolName: copied ? "checkmark" : "doc.on.doc", accessibilityDescription: "Copy")?
        .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    else { return }
    if copyIcon.image != nil, window != nil, OverlayAnimation.allowsMotion {
      copyIcon.setSymbolImage(image, contentTransition: .replace)
    } else {
      copyIcon.image = image
    }
  }

  override func layout() {
    super.layout()
    let titleHeight = titleLabel.intrinsicContentSize.height
    titleLabel.frame = NSRect(
      x: 10, y: bounds.midY - titleHeight / 2, width: 28, height: titleHeight)
    copyButton.frame = NSRect(x: bounds.maxX - 30, y: 0, width: 30, height: bounds.height)
    copyIcon.frame = NSRect(x: 8, y: bounds.midY - 7, width: 14, height: 14)
    let valueHeight = valueLabel.intrinsicContentSize.height
    valueLabel.frame = NSRect(
      x: 42, y: bounds.midY - valueHeight / 2, width: max(0, copyButton.frame.minX - 42),
      height: valueHeight)
  }
}
