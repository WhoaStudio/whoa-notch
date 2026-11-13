import AppKit

/// Témoin passif au centre de l'île repliée ou sous l'encoche matérielle.
final class StayAwakeIdleIndicator: NSImageView {
  static let size: CGFloat = 16
  static let notchExtension: CGFloat = size + 4

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    image = NSImage(
      systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    imageScaling = .scaleProportionallyUpOrDown
    contentTintColor = StayAwakeStyle.accent
    layer?.opacity = 0
    setAccessibilityElement(false)
    setAccessibilityLabel("Stay Awake is on")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(active: Bool, expanded: Bool, animated: Bool) {
    guard let layer else { return }
    let visible = active && !expanded
    setAccessibilityElement(visible)
    if animated {
      PanelFold.fade(layer, to: visible ? 1 : 0)
    } else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.removeAnimation(forKey: "opacity")
      layer.opacity = visible ? 1 : 0
      CATransaction.commit()
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
