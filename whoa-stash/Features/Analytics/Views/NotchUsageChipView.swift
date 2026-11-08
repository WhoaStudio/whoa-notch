import AppKit

/// Pastille de l'en-tête du panneau de l'encoche, à gauche du bouton tasse : jetons et coût du
/// mois en cours, sur une seule ligne. Un clic ouvre l'onglet Analytics.
final class NotchUsageChipView: NSView {

  var onClick: (() -> Void)?

  var text: String = "" {
    didSet {
      guard text != oldValue else { return }
      label.stringValue = text
      needsLayout = true
    }
  }

  /// Allumée tant que l'onglet Analytics est ouvert, comme la tasse pour Stay Awake.
  var isActive = false {
    didSet { applyTint() }
  }

  private let label = NSTextField(labelWithString: "")
  private let iconView = NSImageView()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  private let horizontalPadding: CGFloat = 10
  private let iconSize: CGFloat = 12
  private let iconGap: CGFloat = 5

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    label.lineBreakMode = .byClipping
    label.maximumNumberOfLines = 1
    let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
    iconView.image = NSImage(
      systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Analytics")?
      .withSymbolConfiguration(configuration)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)
    addSubview(label)
    applyTint()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    applyTint()
  }

  private func applyTint() {
    let tint = isHovered || isActive ? palette.tabActiveContent : palette.tabInactiveContent
    label.textColor = tint
    iconView.contentTintColor = tint
    layer?.backgroundColor = NSColor.white.withAlphaComponent(isActive ? 0.16 : 0.08).cgColor
  }

  /// Largeur qui laisse l'icône et tout le texte sur une ligne.
  var fittingWidth: CGFloat {
    horizontalPadding + iconSize + iconGap + ceil(label.intrinsicContentSize.width)
      + horizontalPadding
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    iconView.frame = NSRect(
      x: horizontalPadding, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
    let size = label.intrinsicContentSize
    label.frame = NSRect(
      x: iconView.frame.maxX + iconGap, y: (bounds.height - size.height) / 2,
      width: ceil(size.width), height: size.height)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    applyTint()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    applyTint()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    ButtonSound.shared.playClick()
    onClick?()
  }
}
