import AppKit

/// Contenu des deux ailes que l'encoche ouvre quand un appareil Bluetooth se connecte : le glyphe
/// de l'appareil à gauche, la batterie à droite — bague verte pour des écouteurs, barre verte et
/// pourcentage pour un niveau unique, rien quand le niveau est inconnu. Le centre reste à
/// l'encoche matérielle.
///
/// Pas de fond : la silhouette de l'encoche, élargie par `NotchPanelContentView`, est le fond.
/// Mise en page en frames ; la vue ne reçoit aucun événement.
final class DeviceStatusPillView: NSView {

  /// Largeur de chaque aile, de part et d'autre de l'encoche.
  static let wingWidth: CGFloat = 96

  private let iconView = NSImageView()
  private let percentLabel = NSTextField(labelWithString: "")
  private let ringTrack = CAShapeLayer()
  private let ringProgress = CAShapeLayer()
  private let barTrack = CALayer()
  private let barFill = CALayer()

  private var symbolName: String?
  private var indicator: DeviceBattery.Indicator?

  private let inset: CGFloat = 18
  private let iconSize: CGFloat = 20
  private let ringDiameter: CGFloat = 20
  private let barSize = NSSize(width: 44, height: 7)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    iconView.contentTintColor = .white
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    percentLabel.textColor = .white
    percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    percentLabel.alignment = .right
    addSubview(percentLabel)

    for shape in [ringTrack, ringProgress] {
      shape.fillColor = nil
      shape.lineWidth = 3
      shape.lineCap = .round
      layer?.addSublayer(shape)
    }
    ringTrack.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
    ringProgress.strokeEnd = 0

    barTrack.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    layer?.addSublayer(barTrack)
    layer?.addSublayer(barFill)
    barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ status: DeviceStatus) {
    let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    if let image = NSImage(
      systemSymbolName: status.kind.symbolName, accessibilityDescription: status.name)?
      .withSymbolConfiguration(configuration)
    {
      if let symbolName, symbolName != status.kind.symbolName, layer?.opacity == 1,
        OverlayAnimation.allowsMotion
      {
        iconView.setSymbolImage(image, contentTransition: .replace)
      } else {
        iconView.image = image
      }
      symbolName = status.kind.symbolName
    }
    indicator = status.battery?.indicator
    needsLayout = true
  }

  override func layout() {
    super.layout()

    iconView.frame = NSRect(
      x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

    let trailing = bounds.width - inset
    let tint = Self.tint(for: indicator)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let previousStroke = ringProgress.strokeEnd
    let previousFill = barFill.bounds
    let displayedStroke = ringProgress.presentation()?.strokeEnd ?? previousStroke
    let displayedFill = barFill.presentation()?.bounds ?? previousFill
    let previousPercent = percentLabel.stringValue
    let hadRing = !ringProgress.isHidden
    let hadBar = !barFill.isHidden
    ringTrack.isHidden = true
    ringProgress.isHidden = true
    barTrack.isHidden = true
    barFill.isHidden = true
    percentLabel.isHidden = true

    switch indicator {
    case .ring(let percent):
      let rect = NSRect(
        x: trailing - ringDiameter, y: (bounds.height - ringDiameter) / 2,
        width: ringDiameter, height: ringDiameter)
      // Part de midi, sens horaire.
      let path = CGMutablePath()
      path.addArc(
        center: CGPoint(x: rect.midX, y: rect.midY), radius: (ringDiameter - 3) / 2,
        startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
      for shape in [ringTrack, ringProgress] {
        shape.frame = bounds
        shape.path = path
        shape.isHidden = false
      }
      ringProgress.strokeColor = tint
      ringProgress.strokeEnd = CGFloat(percent) / 100
    case .bar(let percent):
      percentLabel.stringValue = "\(percent)"
      percentLabel.sizeToFit()
      let labelWidth: CGFloat = 24
      percentLabel.frame = NSRect(
        x: trailing - labelWidth, y: (bounds.height - percentLabel.frame.height) / 2,
        width: labelWidth, height: percentLabel.frame.height)
      percentLabel.isHidden = false
      let barFrame = CGRect(
        x: percentLabel.frame.minX - 6 - barSize.width,
        y: (bounds.height - barSize.height) / 2,
        width: barSize.width, height: barSize.height)
      barTrack.frame = barFrame
      barTrack.cornerRadius = barSize.height / 2
      barFill.bounds = CGRect(
        x: 0, y: 0, width: barSize.width * CGFloat(percent) / 100, height: barSize.height)
      barFill.position = CGPoint(x: barFrame.minX, y: barFrame.midY)
      barFill.cornerRadius = barSize.height / 2
      barFill.backgroundColor = tint
      barTrack.isHidden = false
      barFill.isHidden = false
    case nil:
      break
    }
    CATransaction.commit()

    guard layer?.opacity == 1 else { return }
    if !ringProgress.isHidden, hadRing, previousStroke != ringProgress.strokeEnd {
      ringProgress.springAnimate(
        keyPath: "strokeEnd", to: ringProgress.strokeEnd, from: displayedStroke)
    }
    if !barFill.isHidden, hadBar, previousFill != barFill.bounds {
      barFill.springAnimate(keyPath: "bounds", to: barFill.bounds, from: displayedFill)
    }
    if !percentLabel.isHidden, previousPercent != percentLabel.stringValue {
      percentLabel.wantsLayer = true
      percentLabel.layer?.springReveal(y: -3)
    }
  }

  /// Vert, ou orange sous 20 % pour signaler une batterie faible.
  private static func tint(for indicator: DeviceBattery.Indicator?) -> CGColor {
    let percent: Int
    switch indicator {
    case .ring(let value), .bar(let value): percent = value
    case nil: percent = 100
    }
    return (percent < 20 ? NSColor.systemOrange : NSColor.systemGreen).cgColor
  }
}
