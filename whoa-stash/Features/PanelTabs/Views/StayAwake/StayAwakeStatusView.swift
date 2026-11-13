import AppKit

final class StayAwakeStatusView: StayAwakeControl {
  var onAdjust: ((TimeInterval) -> Void)?

  private let icon = NSImageView()
  private let ringTrack = CAShapeLayer()
  private let ringFill = CAShapeLayer()
  private let headline = NSTextField(labelWithString: "")
  private let countdown = NSTextField(labelWithString: "")
  private let hint = NSTextField(labelWithString: "")
  private var palette = OverlayPalette.resolved(for: .currentDrawing())
  private var state = StayAwakeState()
  private var isPanelExpanded = false
  private var scrollIsVertical: Bool?
  private var scrollDistance: CGFloat = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    layer?.cornerRadius = 14
    layer?.borderWidth = 1

    icon.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
    icon.imageScaling = .scaleProportionallyUpOrDown
    addSubview(icon)

    for ring in [ringTrack, ringFill] {
      ring.lineWidth = 2
      ring.lineCap = .round
      ring.fillColor = nil
      layer?.addSublayer(ring)
    }
    ringFill.strokeColor = StayAwakeStyle.accent.cgColor
    ringFill.strokeEnd = 0

    headline.font = .systemFont(ofSize: 12, weight: .semibold)
    countdown.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
    countdown.wantsLayer = true
    hint.font = .systemFont(ofSize: 10, weight: .medium)
    for label in [headline, countdown, hint] { addSubview(label) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    layer?.backgroundColor = palette.tabCapsuleFill
    layer?.borderColor = palette.strokeColor
    ringTrack.strokeColor = palette.strokeColor
    updateColors()
  }

  func apply(_ state: StayAwakeState, previous: StayAwakeState) {
    self.state = state
    let toggled = previous.isActive != state.isActive
    let timed = state.remaining != nil
    let heading = state.isActive ? "Stay Awake · On" : "Stay Awake · Off"
    let detail = timed ? state.countdownText : (state.isActive ? "No timer" : "Start 15 min")
    let instruction = timed
      ? "Click to stop · Scroll to edit"
      : (state.isActive ? "Click to turn off" : "Hold for no timer")
    if headline.stringValue != heading {
      headline.stringValue = heading
      setAccessibilityLabel(heading)
    }
    if countdown.stringValue != detail {
      countdown.stringValue = detail
      setAccessibilityValue(detail)
    }
    if hint.stringValue != instruction {
      hint.stringValue = instruction
      setAccessibilityHelp(instruction)
      toolTip = state.isActive
        ? "Click to turn off · Hold for no timer"
        : "Click to start 15 min · Hold for no timer"
    }
    if toggled {
      updateColors()
      if isPanelExpanded && !isHiddenOrHasHiddenAncestor { countdown.layer?.springReveal(y: 0) }
    }
    if previous.remaining != state.remaining || previous.fraction != state.fraction {
      updateProgress(from: previous)
    }
  }

  func setPanelExpanded(_ expanded: Bool) {
    isPanelExpanded = expanded
    if !expanded {
      cancelPress()
      scrollIsVertical = nil
      scrollDistance = 0
      updateProgress(from: state)
    }
  }

  private func updateColors() {
    icon.contentTintColor = state.isActive ? StayAwakeStyle.accent : palette.tabInactiveContent
    headline.textColor = palette.tabActiveContent
    countdown.textColor = state.isActive ? StayAwakeStyle.accent : palette.tabActiveContent
    hint.textColor = palette.tabInactiveContent
  }

  /// Le calque suit la prochaine seconde du minuteur. Le texte garde les battements du modèle.
  private func updateProgress(from previous: StayAwakeState) {
    let allowsMotion = isPanelExpanded && OverlayAnimation.allowsMotion
      && !isHiddenOrHasHiddenAncestor
    let from = ringFill.presentation()?.strokeEnd ?? ringFill.strokeEnd
    let fraction = CGFloat(state.fraction)
    let remaining = state.remaining ?? 0
    let duration = min(1, remaining)
    let ticking = remaining > 0 && previous.remaining.map { $0 > remaining } == true
      && previous.duration == state.duration && previous.total == state.total
      && (previous.remaining ?? 0) - remaining <= 1.5

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ringFill.removeAnimation(forKey: "strokeEnd")
    ringFill.strokeEnd = fraction
    if allowsMotion, let total = state.total, total > 0, ticking {
      ringFill.strokeEnd = CGFloat((remaining - duration) / total)
      let animation = CABasicAnimation(keyPath: "strokeEnd")
      animation.fromValue = fraction
      animation.toValue = ringFill.strokeEnd
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .linear)
      ringFill.add(animation, forKey: "strokeEnd")
    } else if allowsMotion, from != fraction {
      ringFill.springAnimate(keyPath: "strokeEnd", to: fraction, from: from)
    }
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    let center = CGPoint(x: 27, y: bounds.midY)
    let path = CGMutablePath()
    path.addArc(center: center, radius: 15, startAngle: .pi / 2, endAngle: -.pi * 1.5, clockwise: true)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for ring in [ringTrack, ringFill] {
      ring.frame = bounds
      ring.path = path
    }
    CATransaction.commit()
    icon.frame = NSRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)
    let x: CGFloat = 50
    let width = max(0, bounds.width - x - 8)
    headline.frame = NSRect(x: x, y: center.y + 18, width: width, height: 17)
    countdown.frame = NSRect(x: x, y: center.y - 12, width: width, height: 28)
    hint.frame = NSRect(x: x, y: center.y - 27, width: width, height: 14)
  }

  override func scrollWheel(with event: NSEvent) {
    if event.phase.contains(.began) {
      scrollIsVertical = nil
      scrollDistance = 0
    }
    defer {
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        scrollDistance = 0
      }
    }
    let delta = event.scrollingDeltaY
    if scrollIsVertical == nil, delta != 0 || event.scrollingDeltaX != 0 {
      scrollIsVertical = abs(delta) > abs(event.scrollingDeltaX)
    }
    let isWheel = event.phase.isEmpty && event.momentumPhase.isEmpty
    let isVertical = isWheel ? abs(delta) > abs(event.scrollingDeltaX) : scrollIsVertical == true
    guard let remaining = state.remaining, isVertical else {
      super.scrollWheel(with: event)
      return
    }
    guard event.momentumPhase.isEmpty, !event.phase.contains(.cancelled) else { return }
    if delta < 0 && remaining <= StayAwakeViewModel.minimumRemaining { return }

    if event.hasPreciseScrollingDeltas {
      let pointsPerStep: CGFloat = 24
      scrollDistance += delta
      let steps = (scrollDistance / pointsPerStep).rounded(.towardZero)
      guard steps != 0 else { return }
      scrollDistance -= steps * pointsPerStep
      onAdjust?(TimeInterval(steps) * 5 * 60)
    } else if delta != 0 {
      onAdjust?(delta > 0 ? 5 * 60 : -5 * 60)
    }
  }
}
