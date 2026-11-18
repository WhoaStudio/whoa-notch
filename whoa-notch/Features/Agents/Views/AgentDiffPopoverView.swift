import AppKit
import os

/// L'aperçu du diff d'un fichier modifié par un agent : le chemin, les compteurs +/−, puis le diff
/// unifié avec ses numéros de ligne, les lignes ajoutées en vert et retirées en rouge.
///
/// Ce n'est pas une fenêtre à part mais une carte posée dans le panneau : le panneau de l'encoche se
/// replie dès que le curseur sort de son cadre, et une fenêtre qui en déborderait le ferait se
/// replier sous l'aperçu. Mise en page entièrement en frames, comme le reste de l'overlay.
final class AgentDiffPopoverView: NSView {

  /// Hauteur au plus ; la carte qui l'accueille peut la réduire.
  static let maximumHeight: CGFloat = 320

  var onClose: (() -> Void)?
  var onPointerEnter: (() -> Void)?
  var onPointerExit: (() -> Void)?

  /// Le fichier montré (ou en cours de chargement).
  private(set) var target: DiffTarget?

  private enum Content {
    case loading
    case message(String)
    case diff(GitDiff)
  }

  private var content: Content = .loading
  private var loadTask: Task<Void, Never>?
  private let store: GitDiffStore

  private let pathLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  private let countsLabel = NSTextField(labelWithString: "")
  private let closeButton = NSButton()
  private let scroll = NSScrollView()
  private let canvas = DiffCanvasView()
  private let messageLabel = NSTextField(wrappingLabelWithString: "")
  private let fullDiffButton = PromptButton(title: "Open full diff", style: .link)

  private let headerHeight: CGFloat = 46
  private let padding: CGFloat = 14

  init(store: GitDiffStore = .shared) {
    self.store = store
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

    pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
    pathLabel.textColor = AgentActivityCardView.pathColor
    pathLabel.lineBreakMode = .byTruncatingMiddle
    detailLabel.font = .systemFont(ofSize: 10.5)
    detailLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    detailLabel.lineBreakMode = .byTruncatingMiddle
    countsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    countsLabel.alignment = .right

    closeButton.image = NSImage(
      systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close diff")?
      .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
    closeButton.toolTip = "Close (Esc)"
    closeButton.target = self
    closeButton.action = #selector(closeClicked)

    scroll.documentView = canvas
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.verticalScrollElasticity = .allowed
    scroll.horizontalScrollElasticity = .allowed

    messageLabel.font = .systemFont(ofSize: 12)
    messageLabel.textColor = NSColor.white.withAlphaComponent(0.6)
    messageLabel.alignment = .center
    fullDiffButton.onClick = { [weak self] in self?.openFullDiff() }

    [pathLabel, detailLabel, countsLabel, closeButton, scroll, messageLabel, fullDiffButton]
      .forEach(addSubview)
    setAccessibilityRole(.group)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Contenu

  /// Montre le diff de ce fichier : celui qu'on a déjà s'affiche aussitôt, sinon « Loading… » le temps de git.
  func present(_ target: DiffTarget) {
    guard self.target != target || isHidden else { return }
    self.target = target
    loadTask?.cancel()
    pathLabel.stringValue = Self.display(target)
    detailLabel.stringValue = ""
    countsLabel.stringValue = ""
    setAccessibilityLabel("Diff of \(URL(fileURLWithPath: target.path).lastPathComponent)")

    if let cached = store.cached(for: target) {
      apply(cached)
      return
    }
    content = .loading
    refresh()
    let store = store
    loadTask = Task { [weak self] in
      let result = await store.diff(for: target)
      guard !Task.isCancelled, let self, self.target == target else { return }
      self.apply(result)
    }
  }

  func reset() {
    loadTask?.cancel()
    loadTask = nil
    target = nil
  }

  private func apply(_ result: GitDiffResult) {
    switch result {
    case .diff(let diff): content = .diff(diff)
    case .unchanged: content = .message("No changes since the last commit.")
    case .unavailable(let reason): content = .message(reason + ".")
    }
    refresh()
  }

  /// Le chemin relatif au dossier de la session quand c'est possible.
  private static func display(_ target: DiffTarget) -> String {
    AgentReplay.relative(target.path, to: target.cwd) ?? target.path
  }

  private func refresh() {
    var showsDiff = false
    var text: String?
    switch content {
    case .loading:
      text = "Loading diff…"
    case .message(let message):
      text = message
    case .diff(let diff):
      if diff.isBinary {
        text = "Binary file: the contents are not shown."
      } else if diff.lines.isEmpty {
        text = "No textual changes."
      } else {
        showsDiff = true
      }
    }
    messageLabel.stringValue = text ?? ""
    messageLabel.isHidden = text == nil
    scroll.isHidden = !showsDiff

    if case .diff(let diff) = content {
      detailLabel.stringValue = Self.detail(for: diff)
      if diff.isTruncated {
        // Le diff est coupé : on le dit sur la seconde ligne, avec le moyen de le lire en entier.
        let note = "first \(diff.lines.count) lines of a longer diff"
        detailLabel.stringValue =
          detailLabel.stringValue.isEmpty ? "Showing the " + note : detailLabel.stringValue + "  ·  " + note
      }
      countsLabel.attributedStringValue = diff.isBinary ? NSAttributedString() : Self.counts(diff)
      canvas.set(lines: diff.isBinary ? [] : diff.lines)
      scroll.contentView.scroll(to: .zero)
      scroll.reflectScrolledClipView(scroll.contentView)
      setAccessibilityValue(Self.summary(diff))
      canvas.setAccessibilityValue(Self.plainText(diff))
      fullDiffButton.isHidden = !diff.isTruncated
    } else {
      detailLabel.stringValue = ""
      countsLabel.stringValue = ""
      canvas.set(lines: [])
      fullDiffButton.isHidden = true
    }
    needsLayout = true
  }

  private static func detail(for diff: GitDiff) -> String {
    switch diff.change {
    case .added: return diff.isBinary ? "New binary file" : "New file"
    case .deleted: return diff.isBinary ? "Deleted binary file" : "Deleted file"
    case .renamed(let from): return "Renamed from \(from)"
    case .modified: return diff.isBinary ? "Binary file" : ""
    }
  }

  private static func counts(_ diff: GitDiff) -> NSAttributedString {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    let result = NSMutableAttributedString(
      string: "+\(diff.additions)",
      attributes: [.font: font, .foregroundColor: NSColor.systemGreen])
    result.append(
      NSAttributedString(
        string: "  \u{2212}\(diff.deletions)",
        attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
    return result
  }

  private static func summary(_ diff: GitDiff) -> String {
    diff.isBinary
      ? "Binary file" : "\(diff.additions) lines added, \(diff.deletions) lines removed"
  }

  private static func plainText(_ diff: GitDiff) -> String {
    diff.lines.prefix(200).map { line in
      switch line.kind {
      case .added: "+ " + line.text
      case .removed: "- " + line.text
      case .context: "  " + line.text
      case .hunk, .note: line.text
      }
    }.joined(separator: "\n")
  }

  // MARK: - Actions

  @objc private func closeClicked() { onClose?() }

  /// Écrit le diff complet dans un fichier temporaire et l'ouvre avec l'app par défaut des `.diff`.
  private func openFullDiff() {
    guard case .diff(let diff) = content, let text = diff.fullText else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whoa-notch-diffs", isDirectory: true)
    let name = URL(fileURLWithPath: diff.path).lastPathComponent
    let file = directory.appendingPathComponent(name + ".diff")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try text.write(to: file, atomically: true, encoding: .utf8)
      NSWorkspace.shared.open(file)
    } catch {
      Log.agents.error("diff complet impossible à écrire : \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Clavier et souris

  override var acceptsFirstResponder: Bool { true }

  /// Échap ferme l'aperçu ; les autres touches (flèches, page) font défiler le diff.
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onClose?()
    } else {
      scroll.keyDown(with: event)
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { onPointerEnter?() }
  override func mouseExited(with event: NSEvent) { onPointerExit?() }

  /// Les clics dans l'aperçu ne traversent pas vers la carte dessous.
  override func mouseDown(with event: NSEvent) {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let width = bounds.width
    let height = bounds.height
    closeButton.frame = CGRect(x: width - padding - 18, y: height - 14 - 18, width: 18, height: 18)
    countsLabel.sizeToFit()
    let countsWidth = ceil(countsLabel.frame.width)
    countsLabel.frame = CGRect(
      x: closeButton.frame.minX - 10 - countsWidth, y: height - 14 - 15, width: countsWidth,
      height: 15)
    pathLabel.frame = CGRect(
      x: padding, y: height - 14 - 15, width: max(0, countsLabel.frame.minX - 10 - padding),
      height: 15)
    // « Open full diff » est à droite de la seconde ligne.
    let detailY = height - 14 - 15 - 3 - 14
    var detailWidth = width - padding * 2
    if !fullDiffButton.isHidden {
      let buttonWidth = max(fullDiffButton.fittingWidth, 56)
      fullDiffButton.frame = CGRect(
        x: width - padding - buttonWidth, y: detailY + 1, width: buttonWidth, height: 16)
      detailWidth = fullDiffButton.frame.minX - 8 - padding
    }
    detailLabel.frame = CGRect(x: padding, y: detailY, width: detailWidth, height: 14)

    let bottom: CGFloat = 6
    // Sans seconde ligne (fichier simplement modifié), l'en-tête est plus court.
    let header = detailLabel.stringValue.isEmpty ? headerHeight - 14 : headerHeight
    let body = CGRect(
      x: 0, y: bottom, width: width, height: max(0, height - header - 6 - bottom))
    scroll.frame = body
    canvas.fitWidth(to: scroll.contentSize.width)
    messageLabel.frame = CGRect(
      x: padding, y: body.midY - 18, width: width - padding * 2, height: 36)
  }
}

// MARK: - Le diff

/// Les lignes du diff, dessinées à la main : seules les lignes visibles le sont, et chaque ligne
/// ajoutée ou retirée a un fond sur toute la largeur.
private final class DiffCanvasView: NSView {

  private var lines: [DiffLine] = []
  private let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
  private let rowHeight: CGFloat = 17
  private let charWidth: CGFloat
  private var gutterWidth: CGFloat = 0
  private var oldColumn: CGFloat = 0
  private var newColumn: CGFloat = 0
  private var contentWidth: CGFloat = 0

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
    super.init(frame: frameRect)
    setAccessibilityRole(.staticText)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func set(lines: [DiffLine]) {
    self.lines = lines
    let maxOld = lines.compactMap(\.oldNumber).max() ?? 0
    let maxNew = lines.compactMap(\.newNumber).max() ?? 0
    oldColumn = CGFloat(max(String(maxOld).count, 2)) * charWidth + 10
    newColumn = CGFloat(max(String(maxNew).count, 2)) * charWidth + 10
    // Deux colonnes de numéros, puis le signe (+ / −), puis le texte.
    gutterWidth = oldColumn + newColumn + charWidth * 2
    let longest = min(lines.map { $0.text.count }.max() ?? 0, 300)
    contentWidth = gutterWidth + CGFloat(longest) * charWidth + 16
    needsDisplay = true
  }

  /// La toile est au moins aussi large que la zone visible, pour que les fonds la remplissent.
  func fitWidth(to visible: CGFloat) {
    frame.size = CGSize(
      width: max(visible, contentWidth), height: max(CGFloat(lines.count) * rowHeight, 1))
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !lines.isEmpty else { return }
    let first = max(0, Int(dirtyRect.minY / rowHeight))
    let last = min(lines.count - 1, Int(dirtyRect.maxY / rowHeight))
    guard first <= last else { return }
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    let textY = (rowHeight - lineHeight) / 2
    let numberAttributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.32),
    ]

    for index in first...last {
      let line = lines[index]
      let y = CGFloat(index) * rowHeight
      let row = CGRect(x: 0, y: y, width: bounds.width, height: rowHeight)
      let color: NSColor
      switch line.kind {
      case .added:
        NSColor.systemGreen.withAlphaComponent(0.16).setFill()
        color = NSColor.systemGreen.blended(withFraction: 0.5, of: .white) ?? .systemGreen
      case .removed:
        NSColor.systemRed.withAlphaComponent(0.16).setFill()
        color = NSColor.systemRed.blended(withFraction: 0.5, of: .white) ?? .systemRed
      case .hunk:
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        color = NSColor.systemBlue.blended(withFraction: 0.4, of: .white) ?? .systemBlue
      case .context:
        NSColor.clear.setFill()
        color = NSColor.white.withAlphaComponent(0.78)
      case .note:
        NSColor.clear.setFill()
        color = NSColor.white.withAlphaComponent(0.4)
      }
      row.fill()

      if line.kind == .hunk {
        (line.text as NSString).draw(
          at: CGPoint(x: 10, y: y + textY), withAttributes: [.font: font, .foregroundColor: color])
        continue
      }
      draw(number: line.oldNumber, right: oldColumn - 6, y: y + textY, attributes: numberAttributes)
      draw(
        number: line.newNumber, right: oldColumn + newColumn - 6, y: y + textY,
        attributes: numberAttributes)
      let marker: String
      switch line.kind {
      case .added: marker = "+"
      case .removed: marker = "\u{2212}"
      default: marker = ""
      }
      let textX = oldColumn + newColumn + charWidth * 2
      if !marker.isEmpty {
        (marker as NSString).draw(
          at: CGPoint(x: oldColumn + newColumn + charWidth * 0.5, y: y + textY),
          withAttributes: [.font: font, .foregroundColor: color])
      }
      (line.text as NSString).draw(
        at: CGPoint(x: textX, y: y + textY), withAttributes: [.font: font, .foregroundColor: color])
    }
  }

  private func draw(
    number: Int?, right: CGFloat, y: CGFloat, attributes: [NSAttributedString.Key: Any]
  ) {
    guard let number else { return }
    let text = String(number) as NSString
    let width = text.size(withAttributes: attributes).width
    text.draw(at: CGPoint(x: right - width, y: y), withAttributes: attributes)
  }
}
