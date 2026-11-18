import AppKit

/// Bouton des Préférences, en haut à droite du panneau de l'encoche. Un simple glyphe qui
/// s'éclaircit au survol.
final class NotchGearButtonView: NSView {

  var onClick: (() -> Void)?

  private let iconView = NSImageView()
  private var palette = OverlayPalette.resolved(for: .currentDrawing())
  private var isHovered = false {
    didSet { updateWell() }
  }
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      updateWell()
      layer?.springScale(to: isPressed ? 0.92 : 1)
    }
  }
  /// Cuvette noire et creuse, la même que celle des boutons du lecteur : elle apparaît au survol
  /// et au clic, le glyphe repose dedans.
  private let wellLayer = CALayer()
  private var trackingArea: NSTrackingArea?

  private let symbolName: String
  private let symbolDescription: String

  /// Grisé et sans effet au clic quand il n'y a rien à faire.
  var isEnabled = true {
    didSet {
      applyTint()
      updateWell()
    }
  }

  /// Teinte imposée, au repos comme au survol — le bouton tasse s'allume ainsi tant que le Mac
  /// est tenu éveillé. `nil` : les teintes de la palette.
  var tintOverride: NSColor? {
    didSet { applyTint() }
  }

  init(symbolName: String = "gearshape", description: String = "Settings") {
    self.symbolName = symbolName
    self.symbolDescription = description
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    wellLayer.backgroundColor = NSColor.black.cgColor
    wellLayer.borderWidth = 1
    wellLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    wellLayer.opacity = 0
    layer?.insertSublayer(wellLayer, at: 0)

    let configuration = NSImage.SymbolConfiguration(
      pointSize: TabBarMetrics.iconSize,
      weight: .medium
    )
    iconView.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: symbolDescription)?
      .withSymbolConfiguration(configuration)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    applyTint()
  }

  /// Plus franche à l'appui qu'au survol ; rien quand le bouton est grisé.
  private func updateWell() {
    let target: Float = !isEnabled ? 0 : (isPressed ? 1 : (isHovered ? 0.75 : 0))
    CATransaction.begin()
    if OverlayAnimation.allowsMotion {
      CATransaction.setAnimationDuration(0.15)
    } else {
      CATransaction.setDisableActions(true)
    }
    wellLayer.opacity = target
    CATransaction.commit()
  }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    applyTint()
  }

  private func applyTint() {
    iconView.contentTintColor =
      tintOverride
      ?? (isHovered && isEnabled ? palette.tabActiveContent : palette.tabInactiveContent)
    iconView.alphaValue = isEnabled ? 1 : 0.4
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
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

  override func layout() {
    super.layout()
    let side = min(bounds.width, bounds.height)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    wellLayer.frame = NSRect(
      x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    wellLayer.cornerRadius = side / 2
    CATransaction.commit()
    let icon = TabBarMetrics.iconSize
    iconView.frame = NSRect(
      x: bounds.midX - icon / 2,
      y: bounds.midY - icon / 2,
      width: icon,
      height: icon
    )
  }

  /// Même raison que pour une bulle : le glyphe est une sous-vue, et c'est lui que le clic
  /// atteindrait.
  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func mouseDown(with event: NSEvent) { isPressed = isEnabled }

  override func mouseDragged(with event: NSEvent) {
    isPressed = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    isPressed = false
    let location = convert(event.locationInWindow, from: nil)
    guard isEnabled, bounds.contains(location) else { return }
    ButtonSound.shared.playClick()
    onClick?()
  }
}
