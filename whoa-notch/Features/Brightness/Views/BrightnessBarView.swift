import AppKit

/// Barre verticale en forme de pilule : fond plein et liseré adaptés au thème, contenant les
/// graduations indépendantes de `BrightnessTicksView`. Le fond est celui du panneau de
/// l'encoche (`OverlayPalette.panelBackground`) — les deux surfaces de l'overlay sont la même
/// matière opaque, et non plus un matériau translucide ici et une silhouette pleine là-bas.
final class BrightnessBarView: NSView {

  let ticksView: BrightnessTicksView

  private let backgroundLayer = CALayer()
  private let strokeLayer = CAShapeLayer()

  private let tickInset = NSEdgeInsets(top: 16, left: 7, bottom: 16, right: 7)

  init(tickCount: Int, palette: OverlayPalette) {
    ticksView = BrightnessTicksView(tickCount: tickCount, palette: palette)
    super.init(frame: .zero)
    wantsLayer = true
    setUp(palette: palette)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // Même remarque que dans SunButtonView : NSView (addSubview) et CALayer (addSublayer)
  // mélangés comme frères n'ont pas d'ordre garanti. zPosition fige le stacking.
  private enum Depth {
    static let background: CGFloat = 0
    static let stroke: CGFloat = 1
    static let ticks: CGFloat = 2
  }

  private func setUp(palette: OverlayPalette) {
    backgroundLayer.zPosition = Depth.background
    layer?.addSublayer(backgroundLayer)

    strokeLayer.fillColor = nil
    strokeLayer.lineWidth = 1
    strokeLayer.zPosition = Depth.stroke
    layer?.addSublayer(strokeLayer)

    addSubview(ticksView)
    ticksView.layer?.zPosition = Depth.ticks

    apply(palette: palette)
  }

  override func layout() {
    super.layout()

    let radius = bounds.width / 2

    backgroundLayer.frame = bounds
    backgroundLayer.cornerRadius = radius

    strokeLayer.path = CGPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: radius,
      cornerHeight: radius,
      transform: nil
    )

    ticksView.frame = NSRect(
      x: tickInset.left,
      y: tickInset.bottom,
      width: bounds.width - tickInset.left - tickInset.right,
      height: bounds.height - tickInset.top - tickInset.bottom
    )
  }

  func apply(palette: OverlayPalette) {
    backgroundLayer.backgroundColor = palette.panelBackground
    strokeLayer.strokeColor = palette.strokeColor
    ticksView.apply(palette: palette)
  }

  func setActiveTickCount(_ count: Int, animated: Bool) {
    ticksView.setActiveCount(count, animated: animated)
  }
}
