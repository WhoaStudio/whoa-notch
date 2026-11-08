import AppKit

/// Curseur de luminosité de l'aperçu : une piste courbe qui longe le bord gauche du cercle, un
/// petit soleil à son pied, un grand à son sommet, et une poignée ronde entre les deux.
///
/// Seule la piste répond : le reste du cadre — qui couvre tout l'onglet — laisse passer les
/// clics (voir `hitTest(_:)`).
final class CurvedBrightnessSlider: NSView {

  var onChange: ((Double) -> Void)?

  private(set) var value: Double = CameraBrightness.neutral

  /// Le cercle que la piste longe, dans le repère de cette vue ; posé par la vue parente.
  var arc = ArcSliderGeometry(center: .zero, radius: 0) {
    didSet { needsLayout = true }
  }

  private let trackLayer = CAShapeLayer()
  private let thumbLayer = CALayer()
  private let lowIcon = CurvedBrightnessSlider.sunView(symbol: "sun.min", pointSize: 12)
  private let highIcon = CurvedBrightnessSlider.sunView(symbol: "sun.max", pointSize: 20)

  private static let thumbSize: CGFloat = 18
  /// Écart entre le bout de la piste et son soleil, le long du rayon.
  private static let iconInset: CGFloat = 14
  private static let grabTolerance: CGFloat = 14

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    trackLayer.fillColor = nil
    trackLayer.strokeColor = NSColor(white: 0.5, alpha: 0.55).cgColor
    trackLayer.lineWidth = 2.5
    trackLayer.lineCap = .round
    layer?.addSublayer(trackLayer)

    thumbLayer.bounds = CGRect(
      origin: .zero, size: CGSize(width: Self.thumbSize, height: Self.thumbSize))
    thumbLayer.cornerRadius = Self.thumbSize / 2
    thumbLayer.backgroundColor = NSColor(white: 0.78, alpha: 1).cgColor
    thumbLayer.shadowOpacity = 0.4
    thumbLayer.shadowRadius = 3
    thumbLayer.shadowOffset = .zero
    layer?.addSublayer(thumbLayer)

    addSubview(lowIcon)
    addSubview(highIcon)
    setAccessibilityRole(.slider)
    setAccessibilityLabel("Camera preview brightness")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func sunView(symbol: String, pointSize: CGFloat) -> NSImageView {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let view = NSImageView(
      image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) ?? NSImage())
    view.contentTintColor = NSColor(white: 0.62, alpha: 1)
    view.imageScaling = .scaleProportionallyDown
    return view
  }

  func setValue(_ newValue: Double) {
    value = min(max(newValue, 0), 1)
    placeThumb()
  }

  override func layout() {
    super.layout()
    let path = CGMutablePath()
    path.addArc(
      center: arc.center,
      radius: arc.radius,
      startAngle: arc.startAngle,
      endAngle: arc.endAngle,
      clockwise: true
    )
    trackLayer.path = path
    placeThumb()

    // Les soleils sont posés au-delà des bouts de la piste, sur le prolongement du rayon.
    place(lowIcon, atAngle: arc.startAngle, size: 16)
    place(highIcon, atAngle: arc.endAngle, size: 26)
  }

  private func place(_ icon: NSView, atAngle angle: CGFloat, size: CGFloat) {
    let distance = arc.radius + Self.iconInset
    icon.frame = NSRect(
      x: arc.center.x + distance * cos(angle) - size / 2,
      y: arc.center.y + distance * sin(angle) - size / 2,
      width: size,
      height: size
    )
  }

  private func placeThumb() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    thumbLayer.position = arc.point(for: value)
    CATransaction.commit()
  }

  // MARK: - Souris

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    return arc.isNear(local, tolerance: Self.grabTolerance) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { update(from: event) }

  override func mouseDragged(with event: NSEvent) { update(from: event) }

  private func update(from event: NSEvent) {
    let newValue = arc.value(at: convert(event.locationInWindow, from: nil))
    guard newValue != value else { return }
    setValue(newValue)
    onChange?(newValue)
  }
}
