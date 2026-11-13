import AppKit

/// Cible de dépôt du bac pendant un glisser : garder le fichier, l'envoyer par AirDrop, ou
/// ouvrir l'image dans la vue Transform.
enum FileTrayDropTarget: Equatable {
  case keep
  case airDrop
  case transform

  /// Cible sous un point, en coordonnées de la vue du bac : moitié gauche = garder, moitié
  /// droite = AirDrop. Hors de la vue, on garde — c'est le comportement historique du panneau,
  /// où un fichier se lâche aussi sur l'encoche.
  static func target(at point: NSPoint, in bounds: NSRect) -> FileTrayDropTarget {
    guard bounds.contains(point), point.x >= bounds.midX else { return .keep }
    return .airDrop
  }
}

/// Zone AirDrop du bac : un tunnel de grille qui fuit vers un centre bleu lumineux, l'icône
/// AirDrop et son libellé. Tout est dessiné en calques, sans image embarquée.
final class AirDropZoneView: NSView {

  private let glowLayer = CAGradientLayer()
  private let gridLayer = CAShapeLayer()
  private let outlineLayer = CAShapeLayer()
  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "AirDrop")

  private let accent = NSColor.systemBlue

  var isHighlighted = false {
    didSet {
      guard isHighlighted != oldValue else { return }
      updateAppearance()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true

    glowLayer.type = .radial
    glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
    glowLayer.endPoint = CGPoint(x: 1, y: 1)
    glowLayer.colors = [
      accent.withAlphaComponent(0.55).cgColor,
      accent.withAlphaComponent(0.12).cgColor,
      NSColor.black.withAlphaComponent(0.4).cgColor,
    ]
    layer?.addSublayer(glowLayer)

    gridLayer.fillColor = nil
    gridLayer.lineWidth = 0.5
    layer?.addSublayer(gridLayer)

    outlineLayer.fillColor = nil
    outlineLayer.lineWidth = 1
    outlineLayer.lineDashPattern = [4, 4]
    layer?.addSublayer(outlineLayer)

    iconView.image =
      NSSharingService(named: .sendViaAirDrop)?.image
      ?? NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: nil)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    label.isBezeled = false
    label.drawsBackground = false
    label.isEditable = false
    label.isSelectable = false
    label.alignment = .center
    label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
    label.textColor = .white
    addSubview(label)

    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateAppearance() {
    alphaValue = isHighlighted ? 1 : 0.6
    outlineLayer.strokeColor = (isHighlighted ? NSColor.white : NSColor.gray).cgColor
    gridLayer.strokeColor = accent.withAlphaComponent(isHighlighted ? 0.7 : 0.35).cgColor
  }

  /// Entrée de la zone : le fond glisse depuis la droite en apparaissant, puis l'icône et le
  /// libellé montent juste après. Ressort ample et posé de l'overlay (coupé avec
  /// `Enable animations`).
  func playEntrance() {
    guard let layer else { return }
    layer.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = 0
    layer.setValue(48, forKeyPath: "transform.translation.x")
    for content in [iconView, label] {
      content.wantsLayer = true
      content.layer?.opacity = 0
      content.layer?.setValue(10, forKeyPath: "transform.translation.y")
    }
    CATransaction.commit()

    layer.springAnimate(keyPath: "opacity", to: Float(1), preset: .gentle)
    layer.springAnimate(keyPath: "transform.translation.x", to: CGFloat(0), preset: .gentle)

    for (index, content) in [iconView, label].enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 + 0.05 * Double(index)) {
        content.layer?.springAnimate(keyPath: "opacity", to: Float(1), preset: .gentle)
        content.layer?.springAnimate(
          keyPath: "transform.translation.y", to: CGFloat(0), preset: .gentle)
      }
    }
  }

  override func layout() {
    super.layout()
    glowLayer.frame = bounds
    gridLayer.frame = bounds
    outlineLayer.frame = bounds
    outlineLayer.path = CGPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: 10,
      cornerHeight: 10,
      transform: nil
    )

    // Tunnel : des rayons du centre vers le bord, et des carrés concentriques de plus en
    // plus serrés vers le centre.
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let path = CGMutablePath()
    let steps = 8
    for index in 0...steps {
      let t = CGFloat(index) / CGFloat(steps)
      path.move(to: center)
      path.addLine(to: CGPoint(x: bounds.minX + t * bounds.width, y: bounds.maxY))
      path.move(to: center)
      path.addLine(to: CGPoint(x: bounds.minX + t * bounds.width, y: bounds.minY))
      path.move(to: center)
      path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + t * bounds.height))
      path.move(to: center)
      path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + t * bounds.height))
    }
    for ring in 1...4 {
      let scale = pow(CGFloat(ring) / 4, 2)
      let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      path.addRect(
        CGRect(
          x: center.x - size.width / 2, y: center.y - size.height / 2,
          width: size.width, height: size.height
        ))
    }
    gridLayer.path = path

    let icon: CGFloat = 40
    let labelHeight = label.intrinsicContentSize.height
    iconView.frame = NSRect(
      x: bounds.midX - icon / 2, y: bounds.midY - 2, width: icon, height: icon)
    label.frame = NSRect(
      x: 0, y: bounds.midY - 2 - labelHeight - 4, width: bounds.width, height: labelHeight)
  }
}
