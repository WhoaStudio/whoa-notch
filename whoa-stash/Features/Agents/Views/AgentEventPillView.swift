import AppKit

/// Contenu des deux ailes que l'encoche ouvre quand un agent IA termine ou attend : le glyphe et le
/// nom du projet à gauche, l'état à droite. Le centre reste à l'encoche matérielle.
///
/// Comme `DeviceStatusPillView`, pas de fond : la silhouette de l'encoche élargie est le fond.
final class AgentEventPillView: NSView {

  /// Largeur de chaque aile, de part et d'autre de l'encoche.
  static let wingWidth: CGFloat = 150

  private let iconView = NSImageView()
  private let projectLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  /// Pastille orange sur le logo tant qu'une demande attend une réponse.
  private let dotView = NSView()

  private static let dotSize: CGFloat = 8
  private let inset: CGFloat = 16
  private let iconSize: CGFloat = 18
  private var notchWidth: CGFloat = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    dotView.wantsLayer = true
    dotView.layer?.backgroundColor = NSColor.systemOrange.cgColor
    dotView.layer?.cornerRadius = Self.dotSize / 2
    dotView.layer?.borderWidth = 1.5
    dotView.layer?.borderColor = NSColor.black.cgColor
    addSubview(dotView)

    projectLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    projectLabel.textColor = .white
    projectLabel.lineBreakMode = .byTruncatingTail
    addSubview(projectLabel)

    statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
    statusLabel.alignment = .right
    addSubview(statusLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ event: AgentEvent, notchWidth: CGFloat) {
    let tint: NSColor = event.kind == .needsInput ? .systemOrange : .systemGreen
    let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    if event.prompt != nil, let logo = NSImage(named: "ClaudeLogo") {
      // Le logo garde ses couleurs : seule la pastille dit l'état.
      iconView.image = logo
      iconView.contentTintColor = nil
    } else {
      let symbol = event.prompt != nil ? "sparkle" : event.kind.symbolName
      iconView.image = NSImage(
        systemSymbolName: symbol, accessibilityDescription: event.kind.statusText)?
        .withSymbolConfiguration(configuration)
      iconView.contentTintColor = tint
    }
    dotView.isHidden = event.prompt == nil
    projectLabel.stringValue = event.project
    statusLabel.stringValue = event.kind.statusText
    statusLabel.textColor = tint
    self.notchWidth = notchWidth
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let wing = Self.wingWidth
    iconView.frame = NSRect(
      x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

    dotView.frame = NSRect(
      x: iconView.frame.maxX - Self.dotSize + 3, y: iconView.frame.maxY - Self.dotSize + 3,
      width: Self.dotSize, height: Self.dotSize)

    let labelHeight = projectLabel.intrinsicContentSize.height
    let labelX = inset + iconSize + 7
    projectLabel.frame = NSRect(
      x: labelX, y: (bounds.height - labelHeight) / 2, width: max(0, wing - labelX - 6),
      height: labelHeight)

    let rightX = wing + notchWidth + 6
    statusLabel.frame = NSRect(
      x: rightX, y: (bounds.height - labelHeight) / 2,
      width: max(0, bounds.width - rightX - inset), height: labelHeight)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
