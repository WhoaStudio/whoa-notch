import AppKit

/// Un rectangle arrondi à fond uni, avec bordure optionnelle — la brique des onglets, pastilles,
/// bannières et vignettes. Les couleurs sont posées dans `updateLayer()` pour suivre l'apparence.
final class SettingsFillView: NSView {

  var fillColor: NSColor { didSet { needsDisplay = true } }
  var borderColor: NSColor = .clear { didSet { needsDisplay = true } }
  var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
  var cornerRadius: CGFloat { didSet { needsDisplay = true } }
  var maskedCorners: CACornerMask = [
    .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
  ]
  { didSet { needsDisplay = true } }

  init(fill: NSColor = SettingsPalette.fill, cornerRadius: CGFloat = 0) {
    self.fillColor = fill
    self.cornerRadius = cornerRadius
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    guard let layer else { return }
    layer.backgroundColor = fillColor.cgColor
    layer.cornerRadius = cornerRadius
    layer.cornerCurve = .continuous
    layer.maskedCorners = maskedCorners
    layer.borderWidth = borderWidth
    layer.borderColor = borderColor.cgColor
  }
}
