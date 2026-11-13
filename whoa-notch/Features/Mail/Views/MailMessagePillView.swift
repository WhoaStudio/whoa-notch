import AppKit

/// Contenu des deux ailes que l'encoche ouvre quand un courrier arrive : l'enveloppe et l'expéditeur
/// à gauche, l'objet et le début du texte (deux lignes) à droite. Le centre reste à l'encoche
/// matérielle.
///
/// Comme `AgentEventPillView`, pas de fond : la silhouette de l'encoche élargie est le fond.
final class MailMessagePillView: NSView {

  /// Largeur de chaque aile, de part et d'autre de l'encoche.
  static let wingWidth: CGFloat = 170

  private let iconView = NSImageView()
  private let senderLabel = NSTextField(labelWithString: "")
  private let subjectLabel = NSTextField(labelWithString: "")
  private let previewLabel = NSTextField(labelWithString: "")

  private let inset: CGFloat = NotchPanelGeometry.wingEdgeInset
  private let iconSize: CGFloat = 18
  private var notchWidth: CGFloat = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    iconView.image = NSImage(
      systemSymbolName: "envelope.fill", accessibilityDescription: "New mail")?
      .withSymbolConfiguration(configuration)
    iconView.contentTintColor = .systemBlue
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)

    senderLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    senderLabel.textColor = .white
    subjectLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    subjectLabel.textColor = .white
    previewLabel.font = .systemFont(ofSize: 10, weight: .regular)
    previewLabel.textColor = NSColor.white.withAlphaComponent(0.6)
    for label in [senderLabel, subjectLabel, previewLabel] {
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ message: MailMessage, notchWidth: CGFloat) {
    senderLabel.stringValue = message.sender
    subjectLabel.stringValue = message.subject
    previewLabel.stringValue = message.preview
    self.notchWidth = notchWidth
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let wing = Self.wingWidth
    iconView.frame = NSRect(
      x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

    let senderHeight = senderLabel.intrinsicContentSize.height
    let senderX = inset + iconSize + 7
    senderLabel.frame = NSRect(
      x: senderX, y: (bounds.height - senderHeight) / 2, width: max(0, wing - senderX - 6),
      height: senderHeight)

    let rightX = wing + notchWidth + 6
    let rightWidth = max(0, bounds.width - rightX - inset)
    let subjectHeight = subjectLabel.intrinsicContentSize.height
    let previewHeight = previewLabel.intrinsicContentSize.height
    let blockY = (bounds.height - subjectHeight - previewHeight) / 2
    previewLabel.frame = NSRect(x: rightX, y: blockY, width: rightWidth, height: previewHeight)
    subjectLabel.frame = NSRect(
      x: rightX, y: blockY + previewHeight, width: rightWidth, height: subjectHeight)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
