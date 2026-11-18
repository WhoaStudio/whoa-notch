import AppKit

/// En-tête de section « Running now » : un libellé discret.
final class NotchDetectedSectionRowView: NotchDevRowView {

  private let label = NSTextField(labelWithString: "")

  init(title: String) {
    super.init(frame: .zero)
    preferredHeight = 34
    showsSeparator = false
    label.stringValue = title.uppercased()
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = NSColor.white.withAlphaComponent(0.45)
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    let size = label.intrinsicContentSize
    label.frame = NSRect(x: 0, y: 4, width: ceil(size.width), height: size.height)
  }
}

/// En-tête d'un projet : son dossier, son chemin raccourci, et le nombre de serveurs.
final class NotchDetectedGroupRowView: NotchDevRowView {

  private let nameLabel = NSTextField(labelWithString: "")
  private let pathLabel = NSTextField(labelWithString: "")
  private let iconView = NSImageView()

  convenience init(group: DetectedServerGroup) {
    self.init(name: group.name, path: group.path, isSystem: group.path == nil)
  }

  /// `path` et `name` d'un dossier de projet, ou le groupe « système » (engrenages, sans chemin).
  init(name: String, path: String?, isSystem: Bool) {
    super.init(frame: .zero)
    preferredHeight = 30
    showsSeparator = false
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    iconView.image = NSImage(
      systemSymbolName: isSystem ? "gearshape.2" : "folder.fill", accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    iconView.contentTintColor = NSColor.white.withAlphaComponent(0.7)
    nameLabel.stringValue = name
    nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    nameLabel.textColor = .white
    nameLabel.lineBreakMode = .byTruncatingTail
    pathLabel.stringValue = path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
    pathLabel.font = .systemFont(ofSize: 11.5)
    pathLabel.textColor = NSColor.white.withAlphaComponent(0.4)
    pathLabel.lineBreakMode = .byTruncatingHead
    pathLabel.alignment = .right
    [iconView, nameLabel, pathLabel].forEach(addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    iconView.frame = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 16, height: 16)
    let name = nameLabel.intrinsicContentSize
    // Un `NSTextField` rogne un cadre à la largeur exacte de son texte : 4 pt de marge.
    let nameWidth = min(ceil(name.width) + 4, bounds.width * 0.5)
    nameLabel.frame = NSRect(
      x: 24, y: (bounds.height - name.height) / 2, width: nameWidth, height: name.height)
    let path = pathLabel.intrinsicContentSize
    let pathX = nameLabel.frame.maxX + 12
    pathLabel.frame = NSRect(
      x: pathX, y: (bounds.height - path.height) / 2, width: max(0, bounds.width - pathX),
      height: path.height)
  }
}

/// Un serveur détecté : framework, processus, ports (cliquables sauf pour un service), pid.
final class NotchDetectedServerRowView: NotchDevRowView {

  private let pill = NSTextField(labelWithString: "")
  private let pillBackground = CALayer()
  private let nameLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private var portChips: [PortChip] = []

  init(server: DetectedServer) {
    super.init(frame: .zero)
    preferredHeight = 38
    layer?.addSublayer(pillBackground)
    pillBackground.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    pillBackground.cornerRadius = 9
    pill.stringValue = server.framework.displayName
    pill.font = .systemFont(ofSize: 11.5, weight: .semibold)
    pill.textColor = .white
    nameLabel.stringValue = server.actionName ?? server.processName
    nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
    nameLabel.textColor = NSColor.white.withAlphaComponent(0.9)
    nameLabel.lineBreakMode = .byTruncatingTail
    detailLabel.stringValue =
      server.actionName == nil ? "pid \(server.pid)" : "\(server.processName) · pid \(server.pid)"
    detailLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
    detailLabel.textColor = NSColor.white.withAlphaComponent(0.4)
    [pill, nameLabel, detailLabel].forEach(addSubview)
    for port in server.ports.prefix(3) {
      let chip = PortChip(port: port, opensBrowser: !server.framework.isService)
      addSubview(chip)
      portChips.append(chip)
    }
    if server.ports.count > 3 {
      let more = PortChip(text: "+\(server.ports.count - 3)")
      addSubview(more)
      portChips.append(more)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    let pillSize = pill.intrinsicContentSize
    let pillFrame = NSRect(
      x: 24, y: (bounds.height - 20) / 2, width: ceil(pillSize.width) + 20, height: 20)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    pillBackground.frame = pillFrame
    CATransaction.commit()
    pill.frame = NSRect(
      x: pillFrame.minX + 8, y: pillFrame.midY - pillSize.height / 2,
      width: ceil(pillSize.width) + 4, height: pillSize.height)

    var right = bounds.maxX
    for chip in portChips.reversed() {
      let width = chip.fittingWidth
      chip.frame = NSRect(x: right - width, y: (bounds.height - 22) / 2, width: width, height: 22)
      right = chip.frame.minX - 6
    }
    let textX = pillFrame.maxX + 12
    let textWidth = max(0, right - 8 - textX)
    let name = nameLabel.intrinsicContentSize.height
    let detail = detailLabel.intrinsicContentSize.height
    let top = (bounds.height + name + detail) / 2
    nameLabel.frame = NSRect(x: textX, y: top - name, width: textWidth, height: name)
    detailLabel.frame = NSRect(x: textX, y: top - name - detail, width: textWidth, height: detail)
  }

  /// `:3000`. Un clic ouvre `http://localhost:3000`, sauf pour un service (Postgres, Redis…).
  private final class PortChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private let port: Int?
    private let opensBrowser: Bool

    convenience init(text: String) {
      self.init(port: nil, text: text, opensBrowser: false)
    }

    convenience init(port: Int, opensBrowser: Bool) {
      self.init(port: port, text: ":\(port)", opensBrowser: opensBrowser)
    }

    private init(port: Int?, text: String, opensBrowser: Bool) {
      self.port = port
      self.opensBrowser = opensBrowser
      super.init(frame: .zero)
      wantsLayer = true
      layer?.cornerRadius = 11
      layer?.borderWidth = 1
      layer?.borderColor = NSColor.white.withAlphaComponent(opensBrowser ? 0.28 : 0.14).cgColor
      label.stringValue = text
      label.font = .monospacedSystemFont(ofSize: 11.5, weight: .medium)
      label.textColor = NSColor.white.withAlphaComponent(opensBrowser ? 0.95 : 0.6)
      addSubview(label)
      if opensBrowser, let port { toolTip = "Open http://localhost:\(port)" }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    var fittingWidth: CGFloat { ceil(label.intrinsicContentSize.width) + 20 }

    override func layout() {
      super.layout()
      let size = label.intrinsicContentSize
      label.frame = NSRect(
        x: 8, y: (bounds.height - size.height) / 2, width: ceil(size.width) + 4, height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      guard opensBrowser, let port, let url = URL(string: "http://localhost:\(port)") else { return }
      NSWorkspace.shared.open(url)
    }
  }
}
