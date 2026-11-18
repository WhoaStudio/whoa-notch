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
  private let timelineScroll = TimelineScrollView()
  private let timelineStrip = TimelineStrip()
  private let logBox = NSView()
  private let logScroll = NSScrollView()
  private let logView = HistoryTextView(usingTextLayoutManager: false)
  /// L'aperçu du diff d'un fichier modifié, posé au-dessus de l'historique.
  private let diffPopover = AgentDiffPopoverView()
  private var pendingDiffTarget: DiffTarget?
  private var openTask: Task<Void, Never>?
  private var closeTask: Task<Void, Never>?
  private var visibilityToken = 0
  private let captionLabel = NSTextField(labelWithString: "Waiting for the first action…")

  private var itemCount = 0
  private var project = ""
  /// Plage de chaque action dans l'historique, pour qu'un jeton de la frise y mène.
  private var itemRanges: [NSRange] = []
  private var highlightToken = 0
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
    timelineStrip.onSelect = { [weak self] index in self?.revealItem(at: index) }
    timelineStrip.onHover = { [weak self] target in self?.hoverDiff(target) }
    timelineStrip.onShowDiff = { [weak self] target in self?.showDiff(target, focus: true) }
    logView.onHoverTarget = { [weak self] target in self?.hoverDiff(target) }
    logView.onActivateTarget = { [weak self] target in self?.showDiff(target, focus: true) }
    diffPopover.onClose = { [weak self] in self?.hideDiff() }
    diffPopover.onPointerEnter = { [weak self] in self?.closeTask?.cancel() }
    diffPopover.onPointerExit = { [weak self] in self?.scheduleDiffClose() }

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

    [nameLabel, sourceLabel, countLabel, timelineScroll, logBox, diffPopover].forEach(addSubview)
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
    if !sameSession { hideDiff(animated: false) }
    self.project = project
    nameLabel.stringValue = project
    sourceLabel.stringValue = source
    countLabel.stringValue = items.isEmpty ? "" : (items.count == 1 ? "1 step" : "\(items.count) steps")

    let grew = items.count > itemCount || !sameSession
    let followsEnd = !sameSession || itemCount == 0 || isLogAtEnd
    // Sur la même session, le journal glisse vers la nouvelle ligne au lieu d'y sauter.
    let smoothFollow = sameSession && itemCount > 0 && items.count > itemCount
    itemCount = items.count

    timelineStrip.apply(items)
    let history = Self.history(items)
    itemRanges = history.ranges
    // Un nouveau texte efface la ligne éclairée.
    highlightToken += 1
    logView.layoutManager?.removeTemporaryAttribute(
      .backgroundColor,
      forCharacterRange: NSRange(location: 0, length: logView.textStorage?.length ?? 0))
    logView.textStorage?.setAttributedString(history.text)
    logView.window?.invalidateCursorRects(for: logView)
    captionLabel.isHidden = !items.isEmpty
    logScroll.isHidden = items.isEmpty
    needsLayout = true
    layoutSubtreeIfNeeded()

    openDiffFromLaunchArgument(items)
    if grew { scrollTimelineToEnd() }
    if followsEnd { scrollLogToEnd(animated: smoothFollow) }
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

  private func scrollLogToEnd(animated: Bool = false) {
    guard let container = logView.textContainer, let layoutManager = logView.layoutManager else { return }
    layoutManager.ensureLayout(for: container)
    let used = ceil(layoutManager.usedRect(for: container).height)
    logView.frame.size.height = max(used, logScroll.contentSize.height)
    let clip = logScroll.contentView
    scrollLog(to: max(0, logView.frame.height - clip.bounds.height), animated: animated)
  }

  /// Fait défiler le journal ; en douceur seulement si le mouvement est permis.
  private func scrollLog(to y: CGFloat, animated: Bool) {
    let clip = logScroll.contentView
    let point = NSPoint(x: 0, y: y)
    if animated, OverlayAnimation.allowsMotion, window != nil {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        clip.animator().setBoundsOrigin(point)
      }
    } else {
      clip.scroll(to: point)
    }
    logScroll.reflectScrolledClipView(clip)
  }

  /// Un jeton de la frise a été choisi : sa ligne vient en haut du journal et s'éclaire un instant.
  private func revealItem(at index: Int) {
    guard itemRanges.indices.contains(index), let layoutManager = logView.layoutManager,
      let container = logView.textContainer
    else { return }
    let range = itemRanges[index]
    layoutManager.ensureLayout(for: container)
    let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
    let clip = logScroll.contentView
    let maxY = max(0, logView.frame.height - clip.bounds.height)
    let target = min(max(0, rect.minY + logView.textContainerOrigin.y - 10), maxY)
    scrollLog(to: target, animated: true)
    highlight(range)
  }

  private func highlight(_ range: NSRange) {
    guard let layoutManager = logView.layoutManager else { return }
    let length = logView.textStorage?.length ?? 0
    layoutManager.removeTemporaryAttribute(
      .backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
    // Sans le saut de ligne final, pour que le fond s'arrête au texte.
    let line = NSRange(location: range.location, length: max(0, range.length - 1))
    guard NSMaxRange(line) <= length else { return }
    layoutManager.addTemporaryAttribute(
      .backgroundColor, value: NSColor.white.withAlphaComponent(0.14), forCharacterRange: line)
    highlightToken += 1
    let token = highlightToken
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1.4))
      guard let self, self.highlightToken == token, let manager = self.logView.layoutManager
      else { return }
      manager.removeTemporaryAttribute(
        .backgroundColor,
        forCharacterRange: NSRange(location: 0, length: self.logView.textStorage?.length ?? 0))
    }
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
    // La source et le compte partagent la ligne de base du nom, pas le haut de son cadre.
    sourceLabel.sizeToFit()
    alignBaseline(sourceLabel, x: nameLabel.frame.maxX + 8, width: sourceLabel.frame.width)
    alignBaseline(countLabel, x: bounds.maxX - inset - 90, width: 90)

    timelineScroll.frame = NSRect(
      x: inset, y: top - 18 - 10 - timelineHeight, width: width, height: timelineHeight)
    timelineStrip.frame.size.height = timelineHeight
    timelineStrip.layoutChips(minimumWidth: width)

    // Un journal lu jusqu'au bout le reste quand son cadre change (champ ou boutons dessous).
    let keepsEnd = itemCount > 0 && isLogAtEnd
    let logBottom = bottomInset ?? 16
    let logTop = timelineScroll.frame.minY - 10
    logBox.frame = NSRect(x: inset, y: logBottom, width: width, height: max(0, logTop - logBottom))
    logScroll.frame = logBox.bounds.insetBy(dx: 14, dy: 10)
    logView.frame.size.width = logScroll.contentSize.width
    captionLabel.frame = NSRect(x: 0, y: logBox.bounds.midY - 8, width: logBox.bounds.width, height: 16)
    if keepsEnd { scrollLogToEnd() }

    // L'aperçu du diff prend la place de l'historique, sous la frise qui reste visible.
    let popoverTop = timelineScroll.frame.minY - 6
    let popoverHeight = min(AgentDiffPopoverView.maximumHeight, max(0, popoverTop - 8))
    diffPopover.frame = NSRect(x: inset, y: popoverTop - popoverHeight, width: width, height: popoverHeight)
  }

  /// Là où la carte n'a rien (son fond), le clic traverse vers ce qui est rangé dessous : les boutons
  /// et le champ de consigne de la liste des sessions.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return hit === self ? nil : hit
  }

  // MARK: - Aperçu du diff

  private var opensDiffFromLaunch = true

  /// `--diff-popover=<fichier>` : ouvre l'aperçu de ce fichier dès qu'une édition le concerne.
  private func openDiffFromLaunchArgument(_ items: [AgentReplay.Item]) {
    guard opensDiffFromLaunch,
      let name = CommandLine.arguments.first(where: { $0.hasPrefix("--diff-popover=") })?
        .dropFirst("--diff-popover=".count),
      let target = items.compactMap(\.diffTarget).first(where: { $0.path.hasSuffix("/" + name) })
    else { return }
    opensDiffFromLaunch = false
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(1200))
      self?.showDiff(target, focus: false)
    }
  }

  /// Le curseur est sur un fichier modifié (`nil` : il l'a quitté). L'aperçu s'ouvre après 0,4 s de
  /// survol, ou tout de suite s'il est déjà ouvert pour un autre fichier.
  private func hoverDiff(_ target: DiffTarget?) {
    guard let target else {
      openTask?.cancel()
      pendingDiffTarget = nil
      if !diffPopover.isHidden { scheduleDiffClose() }
      return
    }
    closeTask?.cancel()
    if !diffPopover.isHidden {
      if diffPopover.target != target { showDiff(target, focus: false) }
      return
    }
    guard pendingDiffTarget != target else { return }
    openTask?.cancel()
    pendingDiffTarget = target
    openTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self?.showDiff(target, focus: false)
    }
  }

  /// Ouvre l'aperçu. `focus` : un clic l'a demandé, il prend le clavier (Échap le ferme).
  private func showDiff(_ target: DiffTarget, focus: Bool) {
    openTask?.cancel()
    closeTask?.cancel()
    pendingDiffTarget = nil
    visibilityToken += 1
    let wasHidden = diffPopover.isHidden
    diffPopover.layer?.removeAllAnimations()
    diffPopover.alphaValue = 1
    diffPopover.present(target)
    if wasHidden {
      diffPopover.isHidden = false
      needsLayout = true
      layoutSubtreeIfNeeded()
      diffPopover.layer?.crossfadeIn(delay: 0, duration: 0.16)
    }
    if focus { window?.makeFirstResponder(diffPopover) }
  }

  private func hideDiff(animated: Bool = true) {
    openTask?.cancel()
    closeTask?.cancel()
    pendingDiffTarget = nil
    guard !diffPopover.isHidden else { return }
    visibilityToken += 1
    let token = visibilityToken
    if window?.firstResponder === diffPopover { window?.makeFirstResponder(nil) }
    diffPopover.reset()
    guard animated, OverlayAnimation.allowsMotion, window != nil else {
      diffPopover.isHidden = true
      return
    }
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.12
        diffPopover.animator().alphaValue = 0
      },
      completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          guard let self, self.visibilityToken == token else { return }
          self.diffPopover.isHidden = true
          self.diffPopover.alphaValue = 1
        }
      })
  }

  /// Ferme l'aperçu après 0,25 s, sauf si le curseur est entre-temps sur lui : on peut passer du
  /// fichier à l'aperçu sans qu'il disparaisse.
  private func scheduleDiffClose() {
    closeTask?.cancel()
    closeTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, let self, !self.pointerIsInDiffPopover else { return }
      self.hideDiff()
    }
  }

  private var pointerIsInDiffPopover: Bool {
    guard let window, !diffPopover.isHidden else { return false }
    let point = diffPopover.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    return diffPopover.bounds.contains(point)
  }

  override func viewDidHide() {
    super.viewDidHide()
    hideDiff(animated: false)
  }

  private func alignBaseline(_ label: NSTextField, x: CGFloat, width: CGFloat) {
    let height = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(x: x, y: 0, width: width, height: height)
    let baseline = nameLabel.frame.maxY - nameLabel.firstBaselineOffsetFromTop
    label.frame.origin.y = baseline - (height - label.firstBaselineOffsetFromTop)
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
    let description: String
    switch state {
    case .done: (name, description) = ("checkmark.circle.fill", "Done")
    case .failed: (name, description) = ("xmark.circle.fill", "Failed")
    case .active: (name, description) = ("progress.indicator", "In progress")
    }
    let tint = state == .failed ? errorColor : color
    // Coche et croix se lisent sur le disque teinté : le signe est sombre, le disque de la couleur.
    let palette: [NSColor] =
      state == .active ? [tint] : [NSColor(white: 0.07, alpha: 1), tint]
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
      .applying(.init(paletteColors: palette))
    return (NSImage(systemSymbolName: name, accessibilityDescription: description)
      ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: description))?
      .withSymbolConfiguration(configuration)
  }

  // MARK: - Texte

  /// L'historique en texte : une ligne par action (symbole d'état, nom coloré, fichier ou détail),
  /// puis les lignes retirées et ajoutées d'une édition.
  static func historyText(_ items: [AgentReplay.Item]) -> NSAttributedString {
    history(items).text
  }

  /// L'historique et la plage de chaque action dans le texte.
  private static func history(_ items: [AgentReplay.Item]) -> (
    text: NSAttributedString, ranges: [NSRange]
  ) {
    let result = NSMutableAttributedString()
    var ranges: [NSRange] = []
    let labelFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    let mono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 84)]
    paragraph.defaultTabInterval = 84
    paragraph.headIndent = 84
    // Un peu d'air : entre les lignes d'une édition et entre deux actions.
    paragraph.lineSpacing = 3.5
    paragraph.paragraphSpacing = 9

    for item in items {
      let start = result.length
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
        var attributes: [NSAttributedString.Key: Any] = [
          .font: mono, .foregroundColor: pathColor, .paragraphStyle: paragraph,
        ]
        if let target = item.diffTarget {
          // Un fichier modifié : sa trace en pointillés dit qu'on peut en voir le diff.
          attributes[.gitDiffTarget] = target
          attributes[.underlineStyle] = NSUnderlineStyle.patternDot.union(.single).rawValue
          attributes[.underlineColor] = pathColor.withAlphaComponent(0.55)
        }
        result.append(NSAttributedString(string: path, attributes: attributes))
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
      ranges.append(NSRange(location: start, length: result.length - start))
    }
    return (result, ranges)
  }
}

// MARK: - Frise

/// La frise : un jeton par action, relié au suivant par un fil, du plus ancien au plus récent.
private final class TimelineStrip: NSView {

  /// Un jeton a été choisi (index de l'action).
  var onSelect: ((Int) -> Void)?
  /// Le curseur est sur le jeton d'un fichier modifié, ou l'a quitté (`nil`).
  var onHover: ((DiffTarget?) -> Void)?
  /// Option-clic ou action VoiceOver : montrer le diff tout de suite.
  var onShowDiff: ((DiffTarget) -> Void)?
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
    for (index, (chip, item)) in zip(chips, items).enumerated() {
      chip.apply(item)
      chip.onClick = { [weak self] in self?.onSelect?(index) }
      chip.onHover = { [weak self] target in self?.onHover?(target) }
      chip.onShowDiff = { [weak self] target in self?.onShowDiff?(target) }
    }
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

  var onClick: (() -> Void)?
  var onHover: ((DiffTarget?) -> Void)?
  var onShowDiff: ((DiffTarget) -> Void)?
  /// Le fichier d'une édition : son diff s'ouvre au survol.
  private(set) var diffTarget: DiffTarget?
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var isActive = false
  private var isHovered = false
  private var tint: NSColor = .systemGray
  private var itemState: AgentReplay.Item.State = .done

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
    self.tint = tint
    diffTarget = item.diffTarget
    itemState = item.state
    label.stringValue = item.label
    label.textColor = tint.blended(withFraction: 0.3, of: .white) ?? tint
    icon.image = AgentActivityCardView.statusImage(item.state, color: color, size: 12)
    refreshBackground()
    // La roue tourne tant que l'action est en cours, sauf si le mouvement est réduit ; une coche ou
    // une croix ne bouge pas.
    if item.state == .active, !isActive, OverlayAnimation.allowsMotion {
      icon.addSymbolEffect(.variableColor.iterative.reversing)
    } else if item.state != .active, isActive {
      icon.removeAllSymbolEffects()
    }
    isActive = item.state == .active
    toolTip = [item.label, item.path ?? item.summary].compactMap { $0 }.joined(separator: " — ")
    setAccessibilityLabel(
      [item.label, item.path ?? item.summary, Self.stateTitle(item.state)].compactMap { $0 }
        .joined(separator: ", "))
    needsLayout = true
  }

  private static func stateTitle(_ state: AgentReplay.Item.State) -> String {
    switch state {
    case .done: "done"
    case .failed: "failed"
    case .active: "in progress"
    }
  }

  private func refreshBackground() {
    let active = itemState == .active
    let fill: CGFloat = (active ? 0.24 : 0.12) + (isHovered ? 0.08 : 0)
    layer?.backgroundColor = tint.withAlphaComponent(fill).cgColor
    layer?.borderColor = tint.withAlphaComponent(active ? 0.6 : 0.25).cgColor
  }

  // Un jeton se clique (au relâché) pour mener à sa ligne du journal.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    refreshBackground()
    if diffTarget != nil { onHover?(diffTarget) }
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    refreshBackground()
    if diffTarget != nil { onHover?(nil) }
  }

  override func mouseDown(with event: NSEvent) {}

  /// Un clic mène à la ligne du journal ; Option-clic ouvre le diff du fichier.
  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    if event.modifierFlags.contains(.option), let diffTarget {
      onShowDiff?(diffTarget)
    } else {
      onClick?()
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .button }
  override func accessibilityHelp() -> String? { "Shows this step in the history." }

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    guard diffTarget != nil else { return nil }
    return [
      NSAccessibilityCustomAction(
        name: "Show diff", target: self, selector: #selector(accessibilityShowDiff))
    ]
  }

  @objc private func accessibilityShowDiff() -> Bool {
    guard let diffTarget else { return false }
    onShowDiff?(diffTarget)
    return true
  }

  override func layout() {
    super.layout()
    icon.frame = NSRect(x: 10, y: (bounds.height - 14) / 2, width: 14, height: 14)
    let height = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(
      x: 30, y: (bounds.height - height) / 2, width: max(0, bounds.width - 30 - 8), height: height)
  }
}

// MARK: - Défilement de la frise

/// La frise défile aussi à la molette d'une souris : un cran vertical la fait avancer de côté. Le
/// trackpad garde son geste horizontal.
private final class TimelineScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0
    else { return super.scrollWheel(with: event) }
    let clip = contentView
    let maxX = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
    guard maxX > 0 else { return super.scrollWheel(with: event) }
    let x = min(max(0, clip.bounds.origin.x - event.scrollingDeltaY * 10), maxX)
    clip.scroll(to: NSPoint(x: x, y: 0))
    reflectScrolledClipView(clip)
  }
}

// MARK: - Historique

extension NSAttributedString.Key {
  /// Le `DiffTarget` d'un chemin de fichier modifié dans l'historique.
  fileprivate static let gitDiffTarget = NSAttributedString.Key("whoa-notch.gitDiffTarget")
}

/// Le texte de l'historique. Un chemin de fichier modifié se survole (l'aperçu du diff s'ouvre) et
/// se clique (il s'ouvre tout de suite) ; le reste du texte se sélectionne comme d'habitude.
private final class HistoryTextView: NSTextView {
  var onHoverTarget: ((DiffTarget?) -> Void)?
  var onActivateTarget: ((DiffTarget) -> Void)?
  private var hovered: DiffTarget?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self))
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    let target = target(at: convert(event.locationInWindow, from: nil))
    if target != hovered {
      hovered = target
      onHoverTarget?(target)
    }
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    if hovered != nil {
      hovered = nil
      onHoverTarget?(nil)
    }
  }

  override func mouseDown(with event: NSEvent) {
    if let target = target(at: convert(event.locationInWindow, from: nil)) {
      onActivateTarget?(target)
    } else {
      super.mouseDown(with: event)
    }
  }

  /// La main sur les chemins cliquables.
  override func resetCursorRects() {
    super.resetCursorRects()
    guard let storage = textStorage, let layoutManager, let textContainer else { return }
    let origin = textContainerOrigin
    storage.enumerateAttribute(
      .gitDiffTarget, in: NSRange(location: 0, length: storage.length)
    ) { value, range, _ in
      guard value != nil else { return }
      let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      layoutManager.enumerateEnclosingRects(
        forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
        in: textContainer
      ) { rect, _ in
        self.addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
      }
    }
  }

  /// Le fichier modifié sous le point, s'il y en a un.
  private func target(at point: NSPoint) -> DiffTarget? {
    guard let storage = textStorage, let layoutManager, let textContainer, storage.length > 0
    else { return nil }
    let origin = textContainerOrigin
    let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    var fraction: CGFloat = 0
    let glyph = layoutManager.glyphIndex(
      for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
    let box = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
    guard box.contains(local) else { return nil }
    let index = layoutManager.characterIndexForGlyph(at: glyph)
    guard index < storage.length else { return nil }
    return storage.attribute(.gitDiffTarget, at: index, effectiveRange: nil) as? DiffTarget
  }
}
