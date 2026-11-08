import AppKit

/// Piste fine avec remplissage blanc, et une poignée si elle est interactive : la progression du
/// morceau (lecture seule) et le volume (au glisser) en sont deux instances.
final class NowPlayingSliderView: NSView {

  var onChange: ((Double) -> Void)?

  private(set) var value: Double = 0

  private let isInteractive: Bool
  private let trackLayer = CALayer()
  private let fillLayer = CALayer()
  private let thumbLayer = CALayer()

  private let trackHeight: CGFloat = 4
  private let thumbSize = CGSize(width: 18, height: 12)

  init(isInteractive: Bool) {
    self.isInteractive = isInteractive
    super.init(frame: .zero)
    wantsLayer = true

    trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
    fillLayer.backgroundColor = NSColor.white.cgColor
    for layer in [trackLayer, fillLayer] { layer.cornerRadius = trackHeight / 2 }
    layer?.addSublayer(trackLayer)
    layer?.addSublayer(fillLayer)

    if isInteractive {
      thumbLayer.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
      thumbLayer.cornerRadius = thumbSize.height / 2
      thumbLayer.bounds = CGRect(origin: .zero, size: thumbSize)
      layer?.addSublayer(thumbLayer)
      setAccessibilityRole(.slider)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setValue(_ newValue: Double) {
    value = min(1, max(0, newValue))
    needsLayout = true
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let track = CGRect(
      x: 0, y: (bounds.height - trackHeight) / 2, width: bounds.width, height: trackHeight)
    trackLayer.frame = track
    // La poignée reste dans le cadre : sa course est réduite d'autant.
    let travel = isInteractive ? bounds.width - thumbSize.width : bounds.width
    let x = CGFloat(value) * travel + (isInteractive ? thumbSize.width / 2 : 0)
    fillLayer.frame = CGRect(
      x: 0, y: track.minY, width: isInteractive ? x : CGFloat(value) * bounds.width,
      height: trackHeight)
    thumbLayer.position = CGPoint(x: x, y: bounds.midY)
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) { drag(to: event) }
  override func mouseDragged(with event: NSEvent) { drag(to: event) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isInteractive }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isInteractive ? super.hitTest(point) : nil
  }

  private func drag(to event: NSEvent) {
    guard isInteractive, bounds.width > thumbSize.width else { return }
    let x = convert(event.locationInWindow, from: nil).x
    let newValue = (x - thumbSize.width / 2) / (bounds.width - thumbSize.width)
    setValue(newValue)
    onChange?(value)
  }
}
