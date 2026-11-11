import AppKit

/// Carte de l'onglet AI qui montre ce qu'un agent a fait : en haut une frise horizontale de ses
/// actions (Read, Edit, Bash, Done…) dans l'ordre, dessous l'historique en texte, qui défile et
/// garde tout, une couleur par type d'étape, des chemins et des erreurs qui se repèrent.
///
/// Aucun logo : chaque état est un symbole SF (coche, croix, roue). Une demande en attente passe
/// devant (voir `NotchUsageTabView`). Mise en page entièrement en frames, comme le reste de l'overlay.
final class AgentActivityCardView: NSView {

  private let nameLabel = NSTextField(labelWithString: "")
  private let sourceLabel = NSTextField(labelWithString: "Claude Code")
  private let countLabel = NSTextField(labelWithString: "")
  private let timelineScroll = NSScrollView()
  private let timelineStrip = TimelineStrip()
  private let logBox = NSView()
  private let logScroll = NSScrollView()
  private let logView = NSTextView(usingTextLayoutManager: false)
  private let captionLabel = NSTextField(labelWithString: "Waiting for the first action…")

  private var itemCount = 0
  private var project = ""
  private let inset: CGFloat = 18
  private let timelineHeight: CGFloat = 30

  /// Posé quand la carte vit dans une autre vue qui fournit déjà le fond.
  var drawsBackground = true {
    didSet {
      layer?.backgroundColor =
        drawsBackground ? NSColor.white.withAlphaComponent(0.07).cgColor : NSColor.clear.cgColor
    }
  }
  /// Bord bas de l'historique, dans le repère de la carte ; `nil` : la marge habituelle. Une vue qui
  /// range un champ ou des boutons dessous le relève.
  var bottomInset: CGFloat? { didSet { needsLayout = true } }
  /// Colonne de contenu dans le repère de la carte, pour aligner ce qu'on range dessous.
  var contentColumn: (x: CGFloat, width: CGFloat) { (inset, bounds.width - inset * 2) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

    nameLabel.font = .systemFont(ofSize: 14, weight: .bold)
    nameLabel.textColor = .white
    nameLabel.lineBreakMode = .byTruncatingTail
    sourceLabel.font = .systemFont(ofSize: 11)
    sourceLabel.textColor = NSColor.white.withAlphaComponent(0.5)
    countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    countLabel.textColor = NSColor.white.withAlphaComponent(0.5)
    countLabel.alignment = .right

    timelineScroll.documentView = timelineStrip
    timelineScroll.drawsBackground = false
    timelineScroll.hasHorizontalScroller = true
    timelineScroll.hasVerticalScroller = false
    timelineScroll.autohidesScrollers = true
    timelineScroll.horizontalScrollElasticity = .allowed
    timelineScroll.verticalScrollElasticity = .none

    logBox.wantsLayer = true
    logBox.layer?.cornerRadius = 12
    logBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    logView.isEditable = false
    logView.isSelectable = true
    logView.drawsBackground = false
    logView.textContainerInset = NSSize(width: 0, height: 0)
    logView.isVerticallyResizable = true
    logView.textContainer?.widthTracksTextView = true
    logScroll.documentView = logView
    logScroll.drawsBackground = false
    logScroll.hasVerticalScroller = true
    logScroll.autohidesScrollers = true
    captionLabel.font = .systemFont(ofSize: 12)
    captionLabel.textColor = NSColor.white.withAlphaComponent(0.45)
    captionLabel.alignment = .center

    [nameLabel, sourceLabel, countLabel, timelineScroll, logBox].forEach(addSubview)
    [logScroll, captionLabel].forEach(logBox.addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - État

  /// L'historique d'une session : la frise et le texte, du plus ancien au plus récent.
  func apply(project: String, source: String, items: [AgentReplay.Item]) {
    let sameSession = self.project == project
    self.project = project
    nameLabel.stringValue = project
    sourceLabel.stringValue = source
    countLabel.stringValue = items.isEmpty ? "" : (items.count == 1 ? "1 step" : "\(items.count) steps")

    let grew = items.count > itemCount || !sameSession
    let followsEnd = !sameSession || itemCount == 0 || isLogAtEnd
    itemCount = items.count

    timelineStrip.apply(items)
    logView.textStorage?.setAttributedString(Self.historyText(items))
    captionLabel.isHidden = !items.isEmpty
    logScroll.isHidden = items.isEmpty
    needsLayout = true
    layoutSubtreeIfNeeded()

    if grew { scrollTimelineToEnd() }
    if followsEnd { scrollLogToEnd() }
  }

  /// L'activité d'un agent sans journal (une seule étape connue) : sa frise réduite.
  func apply(_ activity: AgentActivity) {
    apply(
      project: activity.project, source: "Claude Code", items: AgentReplay.items(for: activity))
  }

  private var isLogAtEnd: Bool {
    let clip = logScroll.contentView
    return clip.bounds.maxY >= logView.frame.height - 8
  }

  private func scrollLogToEnd() {
    guard let container = logView.textContainer, let layoutManager = logView.layoutManager else { return }
    layoutManager.ensureLayout(for: container)
    let used = ceil(layoutManager.usedRect(for: container).height)
    logView.frame.size.height = max(used, logScroll.contentSize.height)
    let clip = logScroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: max(0, logView.frame.height - clip.bounds.height)))
    logScroll.reflectScrolledClipView(clip)
  }

  private func scrollTimelineToEnd() {
    let clip = timelineScroll.contentView
    let target = max(0, timelineStrip.frame.width - clip.bounds.width)
    clip.scroll(to: NSPoint(x: target, y: 0))
    timelineScroll.reflectScrolledClipView(clip)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let width = bounds.width - inset * 2
    let top = bounds.maxY - 16

    nameLabel.sizeToFit()
    let nameWidth = min(nameLabel.frame.width, width * 0.5)
    nameLabel.frame = NSRect(x: inset, y: top - 18, width: nameWidth, height: 18)
    sourceLabel.sizeToFit()
    sourceLabel.frame = NSRect(
      x: nameLabel.frame.maxX + 8, y: top - 17, width: sourceLabel.frame.width, height: 15)
    countLabel.frame = NSRect(x: bounds.maxX - inset - 90, y: top - 17, width: 90, height: 15)

    timelineScroll.frame = NSRect(
      x: inset, y: top - 18 - 10 - timelineHeight, width: width, height: timelineHeight)
    timelineStrip.frame.size.height = timelineHeight
    timelineStrip.layoutChips(minimumWidth: width)

    let logBottom = bottomInset ?? 16
    let logTop = timelineScroll.frame.minY - 10
    logBox.frame = NSRect(x: inset, y: logBottom, width: width, height: max(0, logTop - logBottom))
    logScroll.frame = logBox.bounds.insetBy(dx: 14, dy: 10)
    logView.frame.size.width = logScroll.contentSize.width
    captionLabel.frame = NSRect(x: 0, y: logBox.bounds.midY - 8, width: logBox.bounds.width, height: 16)
  }

  // MARK: - Couleurs

  /// Une couleur par type d'étape, prise parmi les couleurs système du dépôt.
  static func color(for kind: AgentReplay.Item.Kind) -> NSColor {
    switch kind {
    case .tool(let step):
      switch step {
      case .read: return .systemBlue
      case .edit: return .systemOrange
      case .bash: return .systemPurple
      case .done, nil: return .systemGray
      }
    case .approval: return .systemYellow
    case .allowed, .done: return .systemGreen
    case .denied: return .systemRed
    case .steer: return .systemPink
    case .ended: return .systemGray
    }
  }

  /// Fichiers : un turquoise propre aux chemins. Erreurs : rouge.
  static let pathColor = NSColor.systemTeal
  static let errorColor = NSColor.systemRed

  /// Le symbole SF de l'état d'une action : coche, croix ou roue. Aucune image maison.
  static func statusImage(_ state: AgentReplay.Item.State, color: NSColor, size: CGFloat) -> NSImage? {
    let name: String
    switch state {
    case .done: name = "checkmark.circle.fill"
    case .failed: name = "xmark.circle.fill"
    case .active: name = "progress.indicator"
    }
    let tint = state == .failed ? errorColor : color
    // Coche et croix se lisent sur le disque teinté : le signe est sombre, le disque de la couleur.
    let palette: [NSColor] =
      state == .active ? [tint] : [NSColor(white: 0.07, alpha: 1), tint]
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
      .applying(.init(paletteColors: palette))
    return (NSImage(systemSymbolName: name, accessibilityDescription: nil)
      ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: nil))?
      .withSymbolConfiguration(configuration)
  }

  // MARK: - Texte

  /// L'historique en texte : une ligne par action (symbole d'état, nom coloré, fichier ou détail),
  /// puis les lignes retirées et ajoutées d'une édition.
  static func historyText(_ items: [AgentReplay.Item]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let labelFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    let mono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 84)]
    paragraph.defaultTabInterval = 84
    paragraph.headIndent = 84
    paragraph.lineSpacing = 2
    paragraph.paragraphSpacing = 6

    for item in items {
      let color = color(for: item.kind)
      let failed = item.state == .failed
      let attachment = NSTextAttachment()
      attachment.image = statusImage(item.state, color: color, size: 11)
      attachment.bounds = CGRect(x: 0, y: -2.5, width: 12, height: 12)
      result.append(NSAttributedString(attachment: attachment))
      result.append(
        NSAttributedString(
          string: "  " + item.label + "\t",
          attributes: [
            .font: labelFont,
            .foregroundColor: failed ? errorColor : color.blended(withFraction: 0.3, of: .white) ?? color,
            .paragraphStyle: paragraph,
          ]))
      if let path = item.path {
        result.append(
          NSAttributedString(
            string: path,
            attributes: [.font: mono, .foregroundColor: pathColor, .paragraphStyle: paragraph]))
      } else if let summary = item.summary {
        result.append(
          NSAttributedString(
            string: summary,
            attributes: [
              .font: mono,
              .foregroundColor: failed ? errorColor : NSColor.white.withAlphaComponent(0.85),
              .paragraphStyle: paragraph,
            ]))
      }
      for line in item.detail {
        let removed = line.kind == .removed
        let tint: NSColor = removed ? .systemRed : .systemGreen
        // Un séparateur de ligne, pas de paragraphe : l'espace n'est qu'entre les actions.
        result.append(
          NSAttributedString(string: "\u{2028}\t", attributes: [.paragraphStyle: paragraph]))
        result.append(
          NSAttributedString(
            string: (removed ? "− " : "+ "),
            attributes: [
              .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .bold),
              .foregroundColor: tint, .paragraphStyle: paragraph,
            ]))
        let text = NSMutableAttributedString(
          string: line.text,
          attributes: [
            .font: mono, .foregroundColor: tint.blended(withFraction: 0.45, of: .white) ?? tint,
            .paragraphStyle: paragraph,
          ])
        result.append(text)
      }
      result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
    }
    return result
  }
}

// MARK: - Frise

/// La frise : un jeton par action, relié au suivant par un fil, du plus ancien au plus récent.
private final class TimelineStrip: NSView {

  private var chips: [TimelineChip] = []
  private let connector: CGFloat = 12
  private let chipGap: CGFloat = 0

  override var isFlipped: Bool { false }

  func apply(_ items: [AgentReplay.Item]) {
    while chips.count < items.count {
      let chip = TimelineChip()
      addSubview(chip)
      chips.append(chip)
    }
    while chips.count > items.count { chips.removeLast().removeFromSuperview() }
    for (chip, item) in zip(chips, items) { chip.apply(item) }
    needsDisplay = true
  }

  func layoutChips(minimumWidth: CGFloat) {
    var x: CGFloat = 0
    for (index, chip) in chips.enumerated() {
      let width = chip.preferredWidth
      chip.frame = NSRect(x: x, y: (bounds.height - 24) / 2, width: width, height: 24)
      x += width + (index < chips.count - 1 ? connector : 0)
    }
    frame.size.width = max(x, minimumWidth)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.withAlphaComponent(0.18).setFill()
    for index in 0..<max(chips.count - 1, 0) {
      let left = chips[index].frame
      let right = chips[index + 1].frame
      NSRect(x: left.maxX + 2, y: bounds.midY - 0.5, width: right.minX - left.maxX - 4, height: 1)
        .fill()
    }
  }
}

/// Un jeton de la frise : le symbole d'état et le nom de l'action, teintés de la couleur de l'étape.
private final class TimelineChip: NSView {

  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var isActive = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.borderWidth = 1
    icon.imageScaling = .scaleProportionallyDown
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.lineBreakMode = .byTruncatingTail
    addSubview(icon)
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var preferredWidth: CGFloat {
    let font = label.font ?? .systemFont(ofSize: 11, weight: .semibold)
    let text = ceil((label.stringValue as NSString).size(withAttributes: [.font: font]).width)
    return 10 + 14 + 6 + min(text, 110) + 18
  }

  func apply(_ item: AgentReplay.Item) {
    let color = AgentActivityCardView.color(for: item.kind)
    let tint = item.state == .failed ? AgentActivityCardView.errorColor : color
    label.stringValue = item.label
    label.textColor = tint.blended(withFraction: 0.3, of: .white) ?? tint
    icon.image = AgentActivityCardView.statusImage(item.state, color: color, size: 12)
    layer?.backgroundColor = tint.withAlphaComponent(item.state == .active ? 0.24 : 0.12).cgColor
    layer?.borderColor = tint.withAlphaComponent(item.state == .active ? 0.6 : 0.25).cgColor
    // La roue tourne tant que l'action est en cours ; une coche ou une croix ne bouge pas.
    if item.state == .active, !isActive {
      icon.addSymbolEffect(.variableColor.iterative.reversing)
    } else if item.state != .active, isActive {
      icon.removeAllSymbolEffects()
    }
    isActive = item.state == .active
    toolTip = [item.label, item.path ?? item.summary].compactMap { $0 }.joined(separator: " — ")
    needsLayout = true
  }

  override func layout() {
    super.layout()
    icon.frame = NSRect(x: 10, y: (bounds.height - 14) / 2, width: 14, height: 14)
    let height = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(
      x: 30, y: (bounds.height - height) / 2, width: max(0, bounds.width - 30 - 8), height: height)
  }
}
