import AppKit

/// Piste fine avec remplissage blanc, et une poignée si elle est interactive : la progression du
/// morceau et le volume (au glisser) en sont deux instances.
///
/// La progression peut aussi se « scrubber » (`isScrubbable`) : au repos elle reste une piste
/// fine sans poignée ; au survol elle s'épaissit et montre un point, et en glissant elle prévient
/// de la position visée (`onScrub`) avant de la valider au relâchement (`onScrubEnd`).
final class NowPlayingSliderView: NSView {

  var onChange: ((Double) -> Void)?
  /// Position visée pendant le glissé, de 0 à 1.
  var onScrub: ((Double) -> Void)?
  /// Position choisie au relâchement, de 0 à 1.
  var onScrubEnd: ((Double) -> Void)?

  private(set) var value: Double = 0
  /// Vrai tant que le bouton est enfoncé sur une piste scrubbable : l'appelant cesse alors de
  /// réécrire la valeur, sous peine de disputer le curseur au doigt.
  private(set) var isDragging = false

  private let isInteractive: Bool
  private let isScrubbable: Bool
  private let trackLayer = CALayer()
  private let fillLayer = CALayer()
  private let thumbLayer = CALayer()
  private let scrubDot = CALayer()
  private var trackingArea: NSTrackingArea?
  private var isHovered = false

  private let restTrackHeight: CGFloat = 4
  private let activeTrackHeight: CGFloat = 6
  private let thumbSize = CGSize(width: 18, height: 12)
  private let scrubDotSize: CGFloat = 10

  private var trackHeight: CGFloat {
    isScrubbable && (isHovered || isDragging) ? activeTrackHeight : restTrackHeight
  }

  init(isInteractive: Bool, isScrubbable: Bool = false) {
    self.isInteractive = isInteractive
    self.isScrubbable = isScrubbable
    super.init(frame: .zero)
    wantsLayer = true

    trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
    fillLayer.backgroundColor = NSColor.white.cgColor
    layer?.addSublayer(trackLayer)
    layer?.addSublayer(fillLayer)

    if isInteractive {
      thumbLayer.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
      thumbLayer.cornerRadius = thumbSize.height / 2
      thumbLayer.bounds = CGRect(origin: .zero, size: thumbSize)
      layer?.addSublayer(thumbLayer)
      setAccessibilityRole(.slider)
    }
    if isScrubbable {
      scrubDot.backgroundColor = NSColor.white.cgColor
      scrubDot.bounds = CGRect(x: 0, y: 0, width: scrubDotSize, height: scrubDotSize)
      scrubDot.cornerRadius = scrubDotSize / 2
      scrubDot.opacity = 0
      layer?.addSublayer(scrubDot)
      setAccessibilityRole(.slider)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setValue(_ newValue: Double) {
    value = min(1, max(0, newValue))
    needsLayout = true
  }

  override func layout() {
    super.layout()
    applyGeometry(animated: false)
  }

  /// Pose les calques. `animated` sert au survol, où la piste s'épaissit en 150 ms ; une mise en
  /// page ordinaire reste sèche, pour que le remplissage suive la valeur sans retard.
  private func applyGeometry(animated: Bool) {
    CATransaction.begin()
    if animated, OverlayAnimation.allowsMotion {
      CATransaction.setAnimationDuration(0.15)
    } else {
      CATransaction.setDisableActions(true)
    }
    let height = trackHeight
    let track = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    trackLayer.frame = track
    for layer in [trackLayer, fillLayer] { layer.cornerRadius = height / 2 }
    // La poignée reste dans le cadre : sa course est réduite d'autant.
    let travel = isInteractive ? bounds.width - thumbSize.width : bounds.width
    let x = CGFloat(value) * travel + (isInteractive ? thumbSize.width / 2 : 0)
    fillLayer.frame = CGRect(
      x: 0, y: track.minY, width: isInteractive ? x : CGFloat(value) * bounds.width,
      height: height)
    thumbLayer.position = CGPoint(x: x, y: bounds.midY)
    scrubDot.position = CGPoint(x: CGFloat(value) * bounds.width, y: bounds.midY)
    scrubDot.opacity = isScrubbable && (isHovered || isDragging) ? 1 : 0
    CATransaction.commit()
  }

  // MARK: - Souris

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    guard isScrubbable else { return }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    applyGeometry(animated: true)
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    applyGeometry(animated: true)
  }

  override func mouseDown(with event: NSEvent) {
    if isScrubbable {
      isDragging = true
      scrub(to: event)
      applyGeometry(animated: true)
    } else {
      drag(to: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    if isScrubbable {
      scrub(to: event)
    } else {
      drag(to: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard isScrubbable, isDragging else { return }
    scrub(to: event, notify: false)
    isDragging = false
    applyGeometry(animated: true)
    onScrubEnd?(value)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isInteractive || isScrubbable }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isInteractive || isScrubbable ? super.hitTest(point) : nil
  }

  private func drag(to event: NSEvent) {
    guard isInteractive, bounds.width > thumbSize.width else { return }
    let x = convert(event.locationInWindow, from: nil).x
    let newValue = (x - thumbSize.width / 2) / (bounds.width - thumbSize.width)
    setValue(newValue)
    onChange?(value)
  }

  private func scrub(to event: NSEvent, notify: Bool = true) {
    guard bounds.width > 0 else { return }
    let x = convert(event.locationInWindow, from: nil).x
    setValue(Double(x / bounds.width))
    applyGeometry(animated: false)
    if notify { onScrub?(value) }
  }
}
