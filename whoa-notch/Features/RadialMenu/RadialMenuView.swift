import AppKit

/// Disque de verre dépoli, cercle central et anneau d'éléments. Il ne décide de rien : le
/// contrôleur lui donne les éléments et le secteur en surbrillance.
///
/// Le verre est une sous-vue, donc dessinée *après* le `draw(_:)` de son parent : le dessin vit
/// dans `RadialRingView`, posée au-dessus du verre.
final class RadialMenuView: NSView {

  var onClick: (() -> Void)? {
    get { ring.onClick }
    set { ring.onClick = newValue }
  }

  private let backdrop = NSVisualEffectView()
  private let ring: RadialRingView

  override init(frame: NSRect) {
    ring = RadialRingView(frame: NSRect(origin: .zero, size: frame.size))
    super.init(frame: frame)
    backdrop.material = .hudWindow
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    backdrop.maskImage = NSImage(size: frame.size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(ovalIn: rect).fill()
      return true
    }
    backdrop.frame = bounds
    backdrop.autoresizingMask = [.width, .height]
    addSubview(backdrop)
    ring.autoresizingMask = [.width, .height]
    addSubview(ring)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(items: [RadialMenuItem], highlighted: Int?) {
    ring.apply(items: items, highlighted: highlighted)
  }
}

private final class RadialRingView: NSView {

  var onClick: (() -> Void)?

  private var items: [RadialMenuItem] = []
  private var icons: [NSImage] = []
  private var highlighted: Int?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick?() }

  func apply(items: [RadialMenuItem], highlighted: Int?) {
    if items != self.items {
      self.items = items
      icons = items.map(Self.icon(for:))
    }
    self.highlighted = highlighted
    needsDisplay = true
  }

  private static func icon(for item: RadialMenuItem) -> NSImage {
    switch item.kind {
    case .app:
      let path = AppLauncher.resolveURL(item.pinnedApp)?.path ?? item.path
      return NSWorkspace.shared.icon(forFile: path)
    case .shortcut:
      let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
      return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: item.name)?
        .withSymbolConfiguration(config) ?? NSImage()
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let outer = bounds.width / 2
    let inner = RadialMenuGeometry.centerDiameter / 2

    // Contour du disque.
    NSColor.white.withAlphaComponent(0.18).setStroke()
    let rim = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
    rim.lineWidth = 1
    rim.stroke()

    if let highlighted, !items.isEmpty {
      let step = 360 / CGFloat(items.count)
      let mid = RadialMenuGeometry.angle(ofItem: highlighted, count: items.count) * 180 / .pi
      let wedge = NSBezierPath()
      wedge.appendArc(
        withCenter: center, radius: outer - 2, startAngle: mid - step / 2, endAngle: mid + step / 2)
      wedge.appendArc(
        withCenter: center, radius: inner + 4, startAngle: mid + step / 2, endAngle: mid - step / 2,
        clockwise: true)
      wedge.close()
      NSColor.white.withAlphaComponent(0.22).setFill()
      wedge.fill()
    }

    // Cercle central : blanc comme dans la maquette, avec le nom de l'élément visé.
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(
      ovalIn: NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)
    ).fill()
    let title = highlighted.map { items[$0].name } ?? (items.isEmpty ? "No items" : "Radial")
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 15, weight: .medium),
      .foregroundColor: NSColor.black.withAlphaComponent(0.45),
      .paragraphStyle: paragraph,
    ]
    let size = (title as NSString).size(withAttributes: attributes)
    (title as NSString).draw(
      in: NSRect(
        x: center.x - inner + 12, y: center.y - size.height / 2, width: inner * 2 - 24,
        height: size.height),
      withAttributes: attributes)

    // Anneau d'éléments, au milieu de la couronne.
    let ringRadius = (inner + outer) / 2 + 2
    let iconSize: CGFloat = 38
    for (index, icon) in icons.enumerated() {
      let angle = RadialMenuGeometry.angle(ofItem: index, count: items.count)
      let point = NSPoint(
        x: center.x + cos(angle) * ringRadius, y: center.y + sin(angle) * ringRadius)
      let scale: CGFloat = index == highlighted ? 1.15 : 1
      let side = iconSize * scale
      icon.draw(
        in: NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
        from: .zero, operation: .sourceOver, fraction: 1)
    }
  }
}
