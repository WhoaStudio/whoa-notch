import AppKit

/// Teinte partagée avec la tasse de l'en-tête.
enum StayAwakeStyle {
  static let accent = NSColor(srgbRed: 1, green: 0.73, blue: 0.24, alpha: 1)
}

final class StayAwakeTabView: NSView {

  var onAction: ((StayAwakeAction) -> Void)?

  private var state = StayAwakeState()
  private let status = StayAwakeStatusView()
  private let durationLabel = NSTextField(labelWithString: "Duration")
  private let scopeLabel = NSTextField(labelWithString: "Stays awake")
  private let presets: [(StayAwakeDuration, StayAwakeButton)]
  private let scopes: [(StayAwakeScope, StayAwakeButton)]

  override init(frame: NSRect) {
    presets = StayAwakeDuration.allCases.map { duration in
      (duration, StayAwakeButton(title: duration == .forever ? "Until turned off" : duration.label))
    }
    scopes = StayAwakeScope.allCases.map { ($0, StayAwakeButton(title: $0.title)) }
    super.init(frame: frame)
    wantsLayer = true

    addSubview(status)
    status.onClick = { [weak self] in
      guard let self else { return }
      self.onAction?(self.state.isActive ? .turnOff : .start(.minutes15))
    }
    status.onHold = { [weak self] in
      guard let self, self.state.duration != .forever else { return }
      self.onAction?(.start(.forever))
      if self.state.duration == .forever {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
      }
    }
    status.onAdjust = { [weak self] in self?.onAction?(.adjust($0)) }

    for (preset, button) in presets {
      button.onClick = { [weak self] in self?.onAction?(.start(preset)) }
      addSubview(button)
    }
    for (scope, button) in scopes {
      button.onClick = { [weak self] in self?.onAction?(.setScope(scope)) }
      addSubview(button)
    }
    for label in [durationLabel, scopeLabel] {
      label.font = .systemFont(ofSize: 11, weight: .medium)
      addSubview(label)
    }
    applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
    apply(state)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func applyPalette(_ palette: OverlayPalette) {
    durationLabel.textColor = palette.tabInactiveContent
    scopeLabel.textColor = palette.tabInactiveContent
    status.applyPalette(palette)
    for (_, button) in presets { button.applyPalette(palette) }
    for (_, button) in scopes { button.applyPalette(palette) }
  }

  func apply(_ newState: StayAwakeState) {
    let previous = state
    state = newState
    status.apply(newState, previous: previous)
    if previous.duration != newState.duration || previous.isAdjusted != newState.isAdjusted {
      for (preset, button) in presets {
        button.isSelected = !newState.isAdjusted && newState.duration == preset
      }
    }
    for (scope, button) in scopes { button.isSelected = newState.scope == scope }
  }

  override func viewDidHide() {
    super.viewDidHide()
    status.cancelPress()
  }

  func setPanelExpanded(_ expanded: Bool) {
    status.setPanelExpanded(expanded)
    if !expanded {
      for (_, button) in presets { button.cancelPress() }
      for (_, button) in scopes { button.cancelPress() }
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
  }

  override func layout() {
    super.layout()
    let height: CGFloat = 112
    let gap: CGFloat = 12
    let durationButtons = presets.map(\.1)
    let scopeButtons = scopes.map(\.1)
    let controlsWidth = max(rowWidth(durationButtons), rowWidth(scopeButtons))
    let statusWidth = max(0, bounds.width - gap - controlsWidth)
    let bottom = (bounds.height - height) / 2
    status.frame = NSRect(x: 0, y: bottom, width: statusWidth, height: height)

    let controls = NSRect(x: statusWidth + gap, y: bottom, width: controlsWidth, height: height)
    layoutRow(durationButtons, label: durationLabel, in: controls, top: controls.maxY)
    layoutRow(scopeButtons, label: scopeLabel, in: controls, top: controls.minY + 48)
  }

  private func rowWidth(_ buttons: [StayAwakeButton]) -> CGFloat {
    buttons.reduce(0) { $0 + $1.fittingWidth } + 6 * CGFloat(buttons.count - 1)
  }

  private func layoutRow(
    _ buttons: [StayAwakeButton], label: NSTextField, in frame: NSRect, top: CGFloat
  ) {
    label.frame = NSRect(x: frame.minX, y: top - 15, width: frame.width, height: 15)
    let extra = (frame.width - rowWidth(buttons)) / CGFloat(buttons.count)
    var x = frame.minX
    for button in buttons {
      let width = button.fittingWidth + extra
      button.frame = NSRect(x: x, y: top - 48, width: width, height: 28)
      x += width + 6
    }
  }
}
