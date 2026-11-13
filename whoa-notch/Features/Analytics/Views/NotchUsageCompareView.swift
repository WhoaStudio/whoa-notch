import AppKit

/// Un fournisseur sur une ligne : marque, nom, jauge réduite, reste et réinitialisation. Un clic
/// choisit ce fournisseur.
final class NotchUsageCompareRowView: NSView {

  static let height: CGFloat = 46

  let provider: NotchUsageProvider
  var onSelect: (() -> Void)?

  private let markView = NotchUsageMarkView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let windowTag = NotchUsageTagView()
  private let gauge = NotchUsageGaugeView()
  private let percentLabel = NSTextField(labelWithString: "")
  private let resetLabel = NSTextField(labelWithString: "")
  private var isHovered = false
  private var isCurrent = false
  private var trackingArea: NSTrackingArea?

  init(provider: NotchUsageProvider) {
    self.provider = provider
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 16
    markView.mark = provider.mark
    nameLabel.stringValue = provider.name
    nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
    nameLabel.textColor = .white
    nameLabel.lineBreakMode = .byTruncatingTail
    windowTag.tint = NSColor.white.withAlphaComponent(0.9)
    percentLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .light)
    percentLabel.alignment = .right
    resetLabel.font = .systemFont(ofSize: 11, weight: .regular)
    resetLabel.textColor = NSColor.white.withAlphaComponent(0.6)
    resetLabel.alignment = .right
    resetLabel.lineBreakMode = .byTruncatingTail
    [markView, nameLabel, windowTag, gauge, percentLabel, resetLabel].forEach(addSubview)
    applyBackground()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(
    _ reading: NotchUsageReading, isCurrent: Bool, updatedAt: Date?, now: Date = Date()
  ) {
    self.isCurrent = isCurrent
    windowTag.text = reading.windowLabel
    let tone = NotchUsageTone(remaining: reading.remaining)
    switch reading.status {
    case .loaded:
      gauge.isLoading = false
      gauge.remaining = reading.remaining
      percentLabel.stringValue = reading.remainingPercentage.map { "\($0)%" } ?? "—"
      percentLabel.textColor = tone.textColor
      resetLabel.stringValue = reading.resetsAt.map { NotchUsageFormatting.resetsIn($0, now: now) } ?? ""
      toolTip = nil
    case .loading:
      gauge.remaining = nil
      gauge.isLoading = true
      percentLabel.stringValue = "—"
      percentLabel.textColor = NSColor.white.withAlphaComponent(0.45)
      resetLabel.stringValue = "Loading…"
      toolTip = nil
    case .unavailable(let reason):
      gauge.isLoading = false
      gauge.remaining = nil
      percentLabel.stringValue = "—"
      percentLabel.textColor = NSColor.white.withAlphaComponent(0.45)
      resetLabel.stringValue = reading.needsReauth ? "Session expired" : "Unavailable"
      toolTip = reason
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(
      "\(provider.name), \(reading.windowLabel), \(percentLabel.stringValue) remaining")
    applyBackground()
    needsLayout = true
  }

  private func applyBackground() {
    let alpha: CGFloat = isHovered ? 0.12 : (isCurrent ? 0.10 : 0.06)
    layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
  }

  override func layout() {
    super.layout()
    let inset: CGFloat = 16
    let right = bounds.width - inset
    let mid = bounds.height / 2

    markView.frame = NSRect(x: inset, y: mid - 9, width: 18, height: 18)

    let nameSize = nameLabel.intrinsicContentSize
    let tagWidth = windowTag.fittingWidth
    // Colonne droite : reste en grand, réinitialisation dessous.
    let rightWidth: CGFloat = 130
    let rightX = right - rightWidth
    let gaugeWidth: CGFloat = min(220, max(80, bounds.width * 0.28))
    let gaugeX = rightX - 16 - gaugeWidth
    let nameX = markView.frame.maxX + 10
    let nameWidth = min(ceil(nameSize.width) + 6, max(0, gaugeX - nameX - tagWidth - 20))
    nameLabel.frame = NSRect(
      x: nameX, y: mid - nameSize.height / 2, width: nameWidth, height: nameSize.height)
    windowTag.frame = NSRect(
      x: nameLabel.frame.maxX + 8, y: mid - NotchUsageTagView.height / 2, width: tagWidth,
      height: NotchUsageTagView.height)

    gauge.frame = NSRect(x: gaugeX, y: mid - 5, width: gaugeWidth, height: 10)

    let percent = percentLabel.intrinsicContentSize
    let reset = resetLabel.intrinsicContentSize
    percentLabel.frame = NSRect(
      x: rightX, y: mid + 1, width: rightWidth, height: percent.height)
    resetLabel.frame = NSRect(
      x: rightX, y: mid - 1 - reset.height, width: rightWidth, height: reset.height)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    onSelect?()
    return true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    applyBackground()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    applyBackground()
  }

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onSelect?()
  }
}

/// Les trois fournisseurs côte à côte, à la place des filtres et de l'activité tant que la
/// comparaison est ouverte.
final class NotchUsageCompareView: NSView {

  static let rowGap: CGFloat = 6

  var onSelect: ((NotchUsageProvider) -> Void)?

  private let rows: [NotchUsageCompareRowView]

  override init(frame frameRect: NSRect) {
    rows = NotchUsageProvider.allCases.map { NotchUsageCompareRowView(provider: $0) }
    super.init(frame: frameRect)
    for row in rows {
      row.onSelect = { [weak self] in self?.onSelect?(row.provider) }
      addSubview(row)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(
    readings: [NotchUsageProvider: NotchUsageReading], current: NotchUsageProvider,
    updatedAt: [NotchUsageProvider: Date], now: Date = Date()
  ) {
    for row in rows {
      guard let reading = readings[row.provider] else { continue }
      row.apply(
        reading, isCurrent: row.provider == current, updatedAt: updatedAt[row.provider], now: now)
    }
  }

  override func layout() {
    super.layout()
    var top = bounds.maxY
    for row in rows {
      row.frame = NSRect(
        x: 0, y: top - NotchUsageCompareRowView.height, width: bounds.width,
        height: NotchUsageCompareRowView.height)
      top = row.frame.minY - Self.rowGap
    }
  }
}
