import AppKit

/// Tuile « batterie » : un anneau qui se remplit dans le sens horaire depuis midi, avec au centre
/// une icône (prise si le Mac est branché) au-dessus du niveau, sans signe %.
@MainActor
final class BatteryWidget: DockWidget {

  static let kind = DockWidgetKind(id: "battery", title: "Battery", symbol: "battery.100") {
    BatteryWidget(provider: MockBatteryProvider.fromLaunchArguments() ?? IOKitBatteryProvider())
  }

  private let provider: BatteryProviding
  private let tile = BatteryTileView()
  var view: NSView { tile }

  init(provider: BatteryProviding) {
    self.provider = provider
    provider.onChange = { [weak tile] in tile?.percent = $0 }
    provider.onPluggedChange = { [weak tile] plugged in
      tile?.symbolName = plugged ? "powerplug.fill" : "battery.100"
    }
  }

  func start() { provider.start() }
  func stop() { provider.stop() }
}

/// Le dessin de la tuile. Séparé du widget pour se rendre sans source de données.
final class BatteryTileView: NSView {

  /// Remplissage de l'anneau pour `percent` : 0...1, sans sortir de l'intervalle.
  static func fraction(percent: Int?) -> CGFloat {
    guard let percent else { return 0 }
    return CGFloat(min(100, max(0, percent))) / 100
  }

  /// Un cercle qui part de midi et tourne dans le sens horaire.
  static func ringPath(in rect: CGRect) -> CGPath {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    let path = CGMutablePath()
    path.addArc(
      center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi,
      clockwise: true)
    return path
  }

  var percent: Int? {
    didSet {
      guard percent != oldValue else { return }
      refresh()
    }
  }

  /// Texte du centre à la place du pourcentage (ex. l'espace libre du widget Stockage).
  var labelOverride: String? {
    didSet { refresh() }
  }

  /// Symbole SF affiché au-dessus du nombre.
  var symbolName: String = "battery.100" {
    didSet { updateIcon() }
  }

  /// Couleur de l'anneau rempli.
  var tint: NSColor = NSColor(hex: "#2FD158") {
    didSet {
      fill.strokeColor = tint.cgColor
      icon.contentTintColor = tint
    }
  }

  private let icon = NSImageView()
  private let track = CAShapeLayer()
  private let fill = CAShapeLayer()
  private let label = NSTextField(labelWithString: "–")

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
    for ring in [track, fill] {
      ring.fillColor = nil
      layer?.addSublayer(ring)
    }
    track.strokeColor = NSColor(white: 0.30, alpha: 1).cgColor
    fill.strokeColor = tint.cgColor
    fill.lineCap = .round
    label.wantsLayer = true
    label.textColor = .white
    label.alignment = .center
    addSubview(label)
    icon.contentTintColor = tint
    addSubview(icon)
    updateIcon()
    refresh()
  }

  private func updateIcon() {
    icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    needsLayout = true
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  private func refresh() {
    let fraction = Self.fraction(percent: percent)
    if fill.strokeEnd != fraction {
      fill.springAnimate(keyPath: "strokeEnd", to: fraction)
    }
    // Un arc de longueur nulle avec un bout arrondi laisse un point : on le masque.
    fill.isHidden = fraction == 0
    let value = labelOverride ?? percent.map(String.init) ?? "–"
    if label.stringValue != value {
      label.stringValue = value
      if window != nil { label.layer?.springReveal(y: -3) }
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let side = min(bounds.width, bounds.height)
    layer?.cornerRadius = side * DockContentView.iconTileCornerRatio
    let lineWidth = side * 0.09
    let ringRect = bounds.insetBy(dx: side * 0.17, dy: side * 0.17)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for ring in [track, fill] {
      ring.frame = bounds
      ring.lineWidth = lineWidth
      ring.path = Self.ringPath(in: ringRect)
    }
    CATransaction.commit()
    label.font = .systemFont(ofSize: side * 0.20, weight: .bold)
    label.sizeToFit()
    let iconSide = side * 0.22
    icon.symbolConfiguration = .init(pointSize: iconSide, weight: .semibold)
    let gap = side * 0.02
    let stack = iconSide + gap + label.frame.height
    let bottom = (bounds.height - stack) / 2
    label.frame = NSRect(
      x: (bounds.width - label.frame.width) / 2, y: bottom,
      width: label.frame.width, height: label.frame.height)
    icon.frame = NSRect(
      x: (bounds.width - iconSide * 1.4) / 2, y: label.frame.maxY + gap,
      width: iconSide * 1.4, height: iconSide)
  }
}
