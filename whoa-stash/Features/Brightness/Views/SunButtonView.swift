import AppKit

/// Bulle circulaire posée **hors** de la bande, à côté d'elle, sur le même fond plein que la
/// pilule et que le panneau de l'encoche (`OverlayPalette.panelBackground`). Elle porte l'icône
/// soleil au repos, et bascule vers le pourcentage de luminosité (crossfade + léger scale)
/// pendant le réglage, avant de revenir automatiquement à l'icône après une courte pause : la
/// bande elle-même n'affiche donc jamais de chiffre, et la valeur se lit au même endroit que
/// le soleil, détachée de la surface.
final class SunButtonView: NSView {

  var onTap: (() -> Void)?

  private let backgroundLayer = CALayer()
  private let strokeLayer = CAShapeLayer()
  private let iconLayer = CALayer()
  private let percentLayer = CATextLayer()

  private var palette: OverlayPalette
  private var isShowingPercent = false
  private var revertWorkItem: DispatchWorkItem?

  private let percentRevertDelay: TimeInterval = 0.9
  /// Rect partagé par l'icône et le pourcentage : même centre, aucun saut à la transition.
  private let contentSize = CGSize(width: 30, height: 18)

  init(palette: OverlayPalette) {
    self.palette = palette
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // zPosition explicite pour tout : l'ordre d'insertion des sous-calques suffirait
  // aujourd'hui, mais le stacking de cette vue a déjà été cassé une fois par un calque
  // qu'AppKit resynchronisait à sa guise. zPosition le fige, quoi qu'il arrive ensuite.
  private enum Depth {
    static let background: CGFloat = 0
    static let stroke: CGFloat = 1
    static let icon: CGFloat = 2
    static let percent: CGFloat = 3
  }

  private func setUp() {
    backgroundLayer.zPosition = Depth.background
    layer?.addSublayer(backgroundLayer)

    strokeLayer.fillColor = nil
    strokeLayer.lineWidth = 1
    strokeLayer.zPosition = Depth.stroke
    layer?.addSublayer(strokeLayer)

    iconLayer.contentsGravity = .resizeAspect
    iconLayer.shadowOffset = .zero
    iconLayer.zPosition = Depth.icon
    layer?.addSublayer(iconLayer)

    percentLayer.alignmentMode = .center
    percentLayer.isWrapped = false
    percentLayer.truncationMode = .none
    percentLayer.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    percentLayer.fontSize = 13
    percentLayer.opacity = 0
    percentLayer.transform = CATransform3DMakeScale(0.8, 0.8, 1)
    percentLayer.contentsScale = window?.backingScaleFactor ?? 2
    percentLayer.zPosition = Depth.percent
    layer?.addSublayer(percentLayer)

    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)

    apply(palette: palette)
  }

  override func layout() {
    super.layout()

    let radius = bounds.width / 2

    backgroundLayer.frame = bounds
    backgroundLayer.cornerRadius = radius

    strokeLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)

    // Icône et pourcentage partagent exactement le même rect : le crossfade ne doit
    // jamais déplacer le contenu, seulement le fondre/scaler autour du même centre.
    let contentFrame = CGRect(
      x: (bounds.width - contentSize.width) / 2,
      y: (bounds.height - contentSize.height) / 2,
      width: contentSize.width,
      height: contentSize.height
    )
    iconLayer.frame = contentFrame
    percentLayer.frame = contentFrame
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    percentLayer.contentsScale = window?.backingScaleFactor ?? 2
  }

  func apply(palette: OverlayPalette) {
    self.palette = palette
    backgroundLayer.backgroundColor = palette.panelBackground
    strokeLayer.strokeColor = palette.strokeColor
    percentLayer.foregroundColor = palette.buttonSymbolColor.cgColor
    iconLayer.contents = symbolImage(tint: palette.buttonSymbolColor)
  }

  private func symbolImage(tint: NSColor) -> CGImage? {
    let sizeConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    let colorConfig = NSImage.SymbolConfiguration(paletteColors: [tint])
    let config = sizeConfig.applying(colorConfig)

    guard
      let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else { return nil }

    // Les images de symboles système sont marquées "template" par défaut : converties
    // telles quelles en CGImage, on récupère un masque monochrome qui ignore la couleur
    // de palette qu'on vient de configurer. On désactive explicitement le template pour
    // que la couleur choisie soit bien celle qui se retrouve dans le bitmap.
    image.isTemplate = false

    var rect = NSRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  func showPercent(_ value: Int) {
    percentLayer.string = "\(value)"

    if !isShowingPercent {
      isShowingPercent = true
      crossfade(showingPercent: true)
    }
    scheduleRevert()
  }

  private func scheduleRevert() {
    revertWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.isShowingPercent = false
      self?.crossfade(showingPercent: false)
    }
    revertWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + percentRevertDelay, execute: item)
  }

  private func crossfade(showingPercent: Bool) {
    iconLayer.springAnimate(keyPath: "opacity", to: showingPercent ? 0 : 1)
    iconLayer.springAnimate(
      keyPath: "transform",
      to: NSValue(
        caTransform3D: showingPercent
          ? CATransform3DMakeScale(0.8, 0.8, 1)
          : CATransform3DIdentity))

    percentLayer.springAnimate(keyPath: "opacity", to: showingPercent ? 1 : 0)
    percentLayer.springAnimate(
      keyPath: "transform",
      to: NSValue(
        caTransform3D: showingPercent
          ? CATransform3DIdentity
          : CATransform3DMakeScale(0.8, 0.8, 1)))
  }

  override func mouseEntered(with event: NSEvent) {
    layer?.springAnimate(keyPath: "transform.scale", to: 1.08)
    layer?.springAnimate(keyPath: "shadowColor", to: palette.buttonGlowColor)
    layer?.springAnimate(keyPath: "shadowRadius", to: 6)
    layer?.springAnimate(keyPath: "shadowOpacity", to: 1)
  }

  override func mouseExited(with event: NSEvent) {
    layer?.springAnimate(keyPath: "transform.scale", to: 1.0)
    layer?.springAnimate(keyPath: "shadowOpacity", to: 0)
  }

  override func mouseDown(with event: NSEvent) {
    onTap?()
  }
}
