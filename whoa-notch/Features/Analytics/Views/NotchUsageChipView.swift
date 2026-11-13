import AppKit

/// Pastille de l'en-tête du panneau de l'encoche, à gauche de l'encoche : jetons et coût du
/// mois en cours, réduits à l'icône : les chiffres sont dans l'info-bulle. Un clic ouvre
/// l'onglet Analytics.
final class NotchUsageChipView: NSView {

  var onClick: (() -> Void)?

  /// Jetons et coût du mois, montrés en info-bulle et lus par VoiceOver, plus dans la pastille.
  var text: String = "" {
    didSet {
      guard text != oldValue else { return }
      toolTip = text
      setAccessibilityLabel(text.isEmpty ? "Analytics" : "Analytics, \(text)")
    }
  }

  /// Allumée tant que l'onglet Analytics est ouvert, comme la tasse pour Stay Awake.
  var isActive = false {
    didSet { applyTint() }
  }

  private let iconView = NSImageView()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  /// Marges égales sur les quatre côtés.
  static let edgePadding: CGFloat = 4
  static let topPadding: CGFloat = 4
  private static let iconSize: CGFloat = 12
  static var fittingHeight: CGFloat { iconSize + edgePadding + topPadding }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    let configuration = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .medium)
    iconView.image = NSImage(
      systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Analytics")?
      .withSymbolConfiguration(configuration)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)
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
    iconView.contentTintColor = tint
    layer?.backgroundColor = NSColor.white.withAlphaComponent(isActive ? 0.16 : 0.08).cgColor
  }

  /// Largeur qui laisse l'icône entre ses deux marges.
  var fittingWidth: CGFloat {
    Self.edgePadding + Self.iconSize + Self.edgePadding
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    // La marge basse est `edgePadding` ; le reste de la hauteur va au haut.
    iconView.frame = NSRect(
      x: Self.edgePadding, y: Self.edgePadding, width: Self.iconSize, height: Self.iconSize)
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
