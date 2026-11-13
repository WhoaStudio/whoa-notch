import AppKit

/// Surface cliquable commune à la carte et aux pastilles.
class StayAwakeControl: NSView {
  var onClick: (() -> Void)?
  var onHold: (() -> Void)?

  private var holdTimer: Timer?
  private var didHold = false
  private var isPressed = false {
    didSet {
      guard oldValue != isPressed, let layer else { return }
      layer.springScale(to: isPressed ? 0.97 : 1)
      PanelFold.fade(layer, to: isPressed ? 0.78 : 1)
    }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerCurve = .continuous
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    !isHidden && bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    guard let onClick else { return false }
    ButtonSound.shared.playClick()
    onClick()
    return true
  }

  override func mouseDown(with event: NSEvent) {
    cancelPress()
    didHold = false
    isPressed = true
    guard onHold != nil else { return }

    let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.holdTimer = nil
        guard self.isPressed,
          let window = self.window, window.isVisible,
          self.isHit(at: window.convertPoint(fromScreen: NSEvent.mouseLocation)) else { return }
        self.didHold = true
        self.onHold?()
      }
    }
    holdTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  override func mouseDragged(with event: NSEvent) {
    if !bounds.contains(convert(event.locationInWindow, from: nil)) {
      holdTimer?.invalidate()
      holdTimer = nil
      isPressed = false
    } else {
      isPressed = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    let activate = isPressed && !didHold && isHit(at: event.locationInWindow)
    cancelPress()
    if activate { _ = accessibilityPerformPress() }
  }

  func cancelPress() {
    holdTimer?.invalidate()
    holdTimer = nil
    isPressed = false
  }

  private func isHit(at windowPoint: NSPoint) -> Bool {
    guard let frameView = window?.contentView?.superview else { return false }
    return frameView.hitTest(frameView.convert(windowPoint, from: nil)) === self
  }
}

final class StayAwakeButton: StayAwakeControl {
  private let label: NSTextField
  private var palette = OverlayPalette.resolved(for: .currentDrawing())

  var fittingWidth: CGFloat { ceil(label.intrinsicContentSize.width) + 16 }

  var isSelected = false {
    didSet {
      guard oldValue != isSelected else { return }
      updateStyle()
      setAccessibilityValue(isSelected ? 1 : 0)
    }
  }

  init(title: String) {
    label = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.alignment = .center
    addSubview(label)
    setAccessibilityLabel(title)
    setAccessibilityValue(0)
    updateStyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func applyPalette(_ palette: OverlayPalette) {
    self.palette = palette
    updateStyle()
  }

  private func updateStyle() {
    layer?.backgroundColor = isSelected ? StayAwakeStyle.accent.cgColor : palette.tabCapsuleFill
    label.textColor = isSelected ? .black : palette.tabActiveContent
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    let height = label.intrinsicContentSize.height
    label.frame = NSRect(x: 6, y: bounds.midY - height / 2, width: bounds.width - 12, height: height)
  }
}
