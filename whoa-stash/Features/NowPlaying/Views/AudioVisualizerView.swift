import AppKit

/// Quelques barres qui montent et descendent tant que `isAnimating` : un visualiseur de
/// contenance, pas une mesure du son. À l'arrêt elles retombent au plancher.
final class AudioVisualizerView: NSView {

  private static let barCount = 4
  private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47]
  private static let restingScale: CGFloat = 0.18

  private let barWidth: CGFloat = 2
  private let barGap: CGFloat = 2
  private var bars: [CALayer] = []

  var tint: NSColor = .white {
    didSet { bars.forEach { $0.backgroundColor = tint.cgColor } }
  }

  private(set) var isAnimating = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for _ in 0..<Self.barCount {
      let bar = CALayer()
      bar.backgroundColor = tint.cgColor
      bar.cornerRadius = barWidth / 2
      bar.anchorPoint = CGPoint(x: 0.5, y: 0)
      layer?.addSublayer(bar)
      bars.append(bar)
    }
    applyScale(Self.restingScale)
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(motionPreferenceChanged),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
  }

  @objc private func motionPreferenceChanged() {
    setAnimating(isAnimating)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    NSSize(
      width: CGFloat(Self.barCount) * barWidth + CGFloat(Self.barCount - 1) * barGap,
      height: 12)
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, bar) in bars.enumerated() {
      bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
      bar.position = CGPoint(x: barWidth / 2 + CGFloat(index) * (barWidth + barGap), y: 0)
    }
    CATransaction.commit()
  }

  private var wasMotionAllowed = true

  func setAnimating(_ animating: Bool) {
    let allowsMotion = OverlayAnimation.allowsMotion
    guard animating != isAnimating || allowsMotion != wasMotionAllowed else { return }
    wasMotionAllowed = allowsMotion
    isAnimating = animating

    if !animating, allowsMotion {
      for bar in bars {
        bar.springAnimate(keyPath: "transform.scale.y", to: Self.restingScale)
        bar.removeAnimation(forKey: "bounce")
      }
      return
    }

    for (index, bar) in bars.enumerated() {
      bar.removeAnimation(forKey: "transform.scale.y")
      bar.removeAnimation(forKey: "bounce")
      guard animating, allowsMotion else { continue }
      let animation = CABasicAnimation(keyPath: "transform.scale.y")
      animation.fromValue = Self.restingScale
      animation.toValue = 1
      animation.duration = Self.durations[index % Self.durations.count]
      animation.autoreverses = true
      animation.repeatCount = .infinity
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      // Les barres ne démarrent pas ensemble, sinon le motif se lit comme un seul bloc.
      animation.timeOffset = Double(index) * 0.17
      bar.add(animation, forKey: "bounce")
    }
    applyScale(animating && !allowsMotion ? 0.7 : Self.restingScale)
  }

  private func applyScale(_ scale: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bars.forEach { $0.transform = CATransform3DMakeScale(1, scale, 1) }
    CATransaction.commit()
  }
}
