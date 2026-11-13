import AppKit

/// Carte du fournisseur choisi, de haut en bas : marque, nom, fenêtre et rythme à gauche, instant
/// de réinitialisation à droite ; au milieu le chiffre principal (le reste, en grand) avec la
/// ligne secondaire, et la jauge sur toute la largeur. Dans les états de chargement et d'erreur,
/// le chiffre et la jauge cèdent la place à ce qui se passe.
///
/// Interactions : survol de la jauge (valeur exacte) et de l'heure (date complète) ; un clic sur le
/// chiffre alterne reste et consommé ; un clic ailleurs ouvre la comparaison des fournisseurs ; un
/// balayage horizontal change de fournisseur.
final class NotchUsageCardView: NSView, NSViewToolTipOwner {

  static let height: CGFloat = 124

  static let barGreen = NSColor(srgbRed: 0.62, green: 0.84, blue: 0.64, alpha: 1)

  private static let resetFormatter: DateFormatter = {
    let formatter = DateFormatter()
    // « Thu 9:00 AM » ; le gabarit laisse les locales 24 h afficher « jeu. 09:00 ».
    formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
    return formatter
  }()

  private static let fullFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  /// Marge intérieure d'un `NSTextField` : un cadre à la largeur exacte du texte le tronque.
  private static let labelPadding: CGFloat = 6

  private enum Mode { case loaded, loading, failed }

  // MARK: Interface publique

  /// Relance la lecture (bouton « Retry » de l'état d'erreur).
  var onRetry: (() -> Void)?
  /// Un clic hors du chiffre : ouvre ou ferme la comparaison.
  var onToggleCompare: (() -> Void)?
  /// Un balayage change de fournisseur : `+1` le suivant, `-1` le précédent.
  var onStep: ((Int) -> Void)?
  /// Dit si l'en-tête a un fournisseur dans ce sens.
  var canStep: (Int) -> Bool = { _ in false }

  // MARK: Vues

  /// Tout le contenu : c'est lui qui suit le doigt, le fond de la carte reste en place.
  private let body = NSView()
  private let markView = NotchUsageMarkView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let windowTag = NotchUsageTagView()
  private let paceTag = NotchUsageTagView()
  private let resetLabel = NSTextField(labelWithString: "")
  private let absoluteLabel = NSTextField(labelWithString: "")
  private let updatedLabel = NSTextField(labelWithString: "")
  private let figureLabel = NSTextField(labelWithString: "")
  private let captionLabel = NSTextField(labelWithString: "")
  private let secondaryLabel = NSTextField(labelWithString: "")
  private let gauge = NotchUsageGaugeView()
  private let errorView = NSView()
  private let errorIcon = NSImageView()
  private let reasonLabel = NSTextField(wrappingLabelWithString: "")
  private let actionButton = NSButton(title: "Retry", target: nil, action: nil)

  // MARK: État

  private let pager = NotchUsageSwipePager()
  private var mode = Mode.loading
  private var provider = NotchUsageProvider.claude
  private var reading = NotchUsageReading.loading(windowLabel: "5H")
  private var updatedAt: Date?
  private var hasApplied = false
  private var showsUsed = false
  private var displayedFigure = 0
  private var figureTone = NotchUsageTone.plenty
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  private var countLink: CADisplayLink?
  private var countFrom = 0
  private var countTo = 0
  private var countStart: CFTimeInterval = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    applyBackground()

    body.wantsLayer = true
    errorView.wantsLayer = true
    addSubview(body)

    nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
    nameLabel.textColor = .white
    resetLabel.font = .systemFont(ofSize: 13, weight: .medium)
    resetLabel.textColor = NSColor.white.withAlphaComponent(0.9)
    absoluteLabel.font = .systemFont(ofSize: 11, weight: .regular)
    updatedLabel.font = .systemFont(ofSize: 11, weight: .regular)
    for label in [absoluteLabel, updatedLabel] {
      label.textColor = NSColor.white.withAlphaComponent(0.55)
      label.alignment = .right
    }
    // Le « % » ne doit jamais passer à la ligne : le chiffre reste sur une seule ligne.
    figureLabel.lineBreakMode = .byClipping
    figureLabel.maximumNumberOfLines = 1
    captionLabel.font = .systemFont(ofSize: 13, weight: .regular)
    captionLabel.textColor = NSColor.white.withAlphaComponent(0.85)
    secondaryLabel.font = .systemFont(ofSize: 12, weight: .regular)
    secondaryLabel.textColor = NSColor.white.withAlphaComponent(0.6)
    for label in [nameLabel, captionLabel, secondaryLabel] { label.lineBreakMode = .byTruncatingTail }
    reasonLabel.font = .systemFont(ofSize: 13, weight: .regular)
    reasonLabel.textColor = NSColor.white.withAlphaComponent(0.9)
    reasonLabel.maximumNumberOfLines = 2
    reasonLabel.lineBreakMode = .byTruncatingTail
    reasonLabel.cell?.truncatesLastVisibleLine = true

    windowTag.tint = NSColor.white.withAlphaComponent(0.9)
    paceTag.isFilled = true

    errorIcon.image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))
    errorIcon.contentTintColor = NotchUsageTone.amber

    actionButton.bezelStyle = .rounded
    actionButton.controlSize = .small
    actionButton.target = self
    actionButton.action = #selector(actionPressed)

    [errorIcon, reasonLabel, actionButton].forEach(errorView.addSubview)
    [
      markView, nameLabel, windowTag, paceTag, resetLabel, absoluteLabel, updatedLabel,
      figureLabel, captionLabel, secondaryLabel, gauge, errorView,
    ].forEach(body.addSubview)

    configurePager()
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configurePager() {
    pager.width = { [weak self] in self?.bounds.width ?? 1 }
    // Le doigt vers la droite ramène le fournisseur d'avant (`-1`), vers la gauche le suivant.
    pager.allows = { [weak self] page in self?.canStep(-page) ?? false }
    pager.presentedOffset = { [weak self] in self?.body.layer?.presentedTranslationX ?? 0 }
    pager.onTrack = { [weak self] x in
      self?.gauge.hideTip()
      self?.body.layer?.trackSwipe(to: x)
    }
    pager.onCancel = { [weak self] from, velocity in
      self?.body.layer?.settleSwipe(from: from, velocity: velocity)
    }
    pager.onCommit = { [weak self] page, from, _ in
      guard let self else { return }
      body.layer?.commitSwipe(page: page, from: from) { [weak self] in
        self?.onStep?(-page)
      }
    }
  }

  private func applyBackground() {
    layer?.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.10 : 0.07).cgColor
  }

  // MARK: - État

  /// Montre `reading`. `enter` : décalage d'où le contenu arrive (changement de fournisseur par
  /// l'en-tête) ; `nil` quand rien n'entre ou que le balayage s'en est chargé.
  func apply(
    _ reading: NotchUsageReading, provider: NotchUsageProvider, updatedAt: Date?,
    enter: CGFloat? = nil, now: Date = Date()
  ) {
    let previousProvider = hasApplied ? self.provider : nil
    let previousMode = mode
    if previousProvider != provider { gauge.hideTip() }
    self.reading = reading
    self.provider = provider
    self.updatedAt = updatedAt
    hasApplied = true

    markView.mark = provider.mark
    markView.color = .white
    nameLabel.stringValue = provider.name
    windowTag.text = reading.windowLabel
    let tone = NotchUsageTone(remaining: reading.remaining)
    figureTone = tone

    switch reading.status {
    case .loaded:
      mode = .loaded
      let remaining = reading.remainingPercentage ?? 0
      let target = showsUsed ? NotchUsageFormatting.usedPercentage(remainingPercentage: remaining) : remaining
      if previousProvider == provider, previousMode == .loaded {
        startCount(to: target)
      } else if previousProvider == provider, previousMode == .loading {
        displayedFigure = 0
        startCount(to: target)
      } else {
        stopCount()
        setFigure(target)
      }
      captionLabel.stringValue = showsUsed ? "used" : "remaining"
      secondaryLabel.stringValue = reading.secondaryLine ?? ""
      resetLabel.stringValue = reading.resetsAt.map { NotchUsageFormatting.resetsIn($0, now: now) } ?? ""
      absoluteLabel.stringValue = reading.resetsAt.map(Self.resetFormatter.string(from:)) ?? ""
      updatedLabel.stringValue = updatedAt.map { NotchUsageFormatting.updatedAgo($0, now: now) } ?? ""
      gauge.isLoading = false
      gauge.remaining = reading.remaining
      applyPace(reading, now: now)

    case .loading:
      mode = .loading
      stopCount()
      figureLabel.attributedStringValue = figureString(nil, tone: .plenty)
      displayedFigure = 0
      captionLabel.stringValue = "Loading…"
      secondaryLabel.stringValue = ""
      resetLabel.stringValue = ""
      absoluteLabel.stringValue = ""
      updatedLabel.stringValue = ""
      gauge.remaining = nil
      gauge.paceMarker = nil
      gauge.isLoading = true
      paceTag.isHidden = true

    case .unavailable(let reason):
      mode = .failed
      stopCount()
      gauge.isLoading = false
      gauge.remaining = nil
      gauge.paceMarker = nil
      paceTag.isHidden = true
      resetLabel.stringValue = ""
      let expired = reading.needsReauth
      reasonLabel.stringValue = expired ? "Session expired. Sign in again to \(provider.name)." : reason
      errorIcon.contentTintColor = expired ? NotchUsageTone.amber : NotchUsageTone.red
      actionButton.title = expired ? "Reconnect" : "Retry"
      if previousMode != .failed { errorView.layer?.crossfadeIn() }
    }

    figureLabel.isHidden = mode == .failed
    captionLabel.isHidden = mode == .failed
    secondaryLabel.isHidden = mode == .failed
    absoluteLabel.isHidden = mode != .loaded
    updatedLabel.isHidden = mode != .loaded
    gauge.isHidden = mode == .failed
    errorView.isHidden = mode != .failed

    setAccessibilityLabel(accessibilitySummary(now: now))
    needsLayout = true

    if let enter { body.layer?.springReveal(x: enter, y: 0) }
  }

  /// Relit les textes relatifs (« Resets in … », « Updated … ») sans rien changer d'autre.
  func refreshClock(now: Date = Date()) {
    apply(reading, provider: provider, updatedAt: updatedAt, now: now)
  }

  private func applyPace(_ reading: NotchUsageReading, now: Date) {
    guard let resetsAt = reading.resetsAt, let remaining = reading.remaining,
      let length = NotchUsagePace.windowLength(forLabel: reading.windowLabel),
      let expected = NotchUsagePace.expectedRemaining(
        resetsAt: resetsAt, windowLength: length, now: now)
    else {
      gauge.paceMarker = nil
      paceTag.isHidden = true
      return
    }
    gauge.paceMarker = expected
    paceTag.isHidden = false
    switch NotchUsagePace.evaluate(remaining: remaining, expected: expected) {
    case .over:
      paceTag.text = "Over pace"
      paceTag.tint = NotchUsageTone.amber
    case .on:
      paceTag.text = "On pace"
      paceTag.tint = NSColor.white.withAlphaComponent(0.85)
    case .under:
      paceTag.text = "Under pace"
      paceTag.tint = Self.barGreen
    }
  }

  private func accessibilitySummary(now: Date) -> String {
    switch mode {
    case .loading: return "\(provider.name), loading"
    case .failed: return "\(provider.name), unavailable. \(reasonLabel.stringValue)"
    case .loaded:
      let percent = reading.remainingPercentage.map { "\($0) percent remaining" } ?? ""
      let reset = reading.resetsAt.map { NotchUsageFormatting.resetsIn($0, now: now) } ?? ""
      return "\(provider.name), \(reading.windowLabel), \(percent). \(reset)"
    }
  }

  @objc private func actionPressed() {
    if reading.needsReauth {
      AgentLoginLauncher.open(command: provider.loginCommand)
    } else {
      onRetry?()
    }
  }

  // MARK: - Chiffre principal

  private func figureString(_ number: Int?, tone: NotchUsageTone) -> NSAttributedString {
    let color = number == nil ? NSColor.white.withAlphaComponent(0.45) : tone.textColor
    let text = NSMutableAttributedString(
      string: number.map(String.init) ?? "—",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .light),
        .foregroundColor: color,
      ])
    if number != nil {
      text.append(
        NSAttributedString(
          string: "%",
          attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: color.withAlphaComponent(0.8),
          ]))
    }
    return text
  }

  private func setFigure(_ value: Int) {
    displayedFigure = value
    figureLabel.attributedStringValue = figureString(value, tone: figureTone)
    needsLayout = true
  }

  /// Le chiffre monte (ou descend) jusqu'à sa nouvelle valeur plutôt que de changer d'un coup.
  private func startCount(to target: Int) {
    stopCount()
    guard displayedFigure != target else {
      setFigure(target)
      return
    }
    guard OverlayAnimation.allowsMotion, window != nil else {
      setFigure(target)
      return
    }
    countFrom = displayedFigure
    countTo = target
    countStart = CACurrentMediaTime()
    let link = displayLink(target: self, selector: #selector(countTick(_:)))
    link.add(to: .main, forMode: .common)
    countLink = link
  }

  @objc private func countTick(_ link: CADisplayLink) {
    let t = min(1, (CACurrentMediaTime() - countStart) / 0.4)
    let eased = 1 - pow(1 - t, 3)
    setFigure(Int((Double(countFrom) + Double(countTo - countFrom) * eased).rounded()))
    if t >= 1 {
      setFigure(countTo)
      stopCount()
    }
  }

  private func stopCount() {
    countLink?.invalidate()
    countLink = nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Le lien d'affichage retient sa cible : on le lâche quand la carte quitte l'écran.
    if window == nil {
      if countLink != nil { setFigure(countTo) }
      stopCount()
      pager.cancel()
    }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    body.frame = bounds
    errorView.frame = bounds
    registerToolTips()

    let inset: CGFloat = 20
    let right = bounds.width - inset
    let rowMid = bounds.height - 14 - 11

    let markSize: CGFloat = 22
    markView.frame = NSRect(x: inset, y: rowMid - markSize / 2, width: markSize, height: markSize)

    resetLabel.sizeToFit()
    let resetWidth = ceil(resetLabel.frame.width)
    resetLabel.frame = NSRect(
      x: right - resetWidth, y: rowMid - resetLabel.frame.height / 2, width: resetWidth,
      height: resetLabel.frame.height)

    // Nom, fenêtre et rythme se partagent la place qui reste avant l'heure de réinitialisation.
    let nameX = markView.frame.maxX + 10
    let limit = (resetWidth > 0 ? resetLabel.frame.minX : right) - 12
    let nameSize = nameLabel.intrinsicContentSize
    let tagWidth = windowTag.fittingWidth
    let nameWidth = min(
      ceil(nameSize.width) + Self.labelPadding, max(0, limit - nameX - tagWidth - 8))
    nameLabel.frame = NSRect(
      x: nameX, y: rowMid - nameSize.height / 2, width: nameWidth, height: nameSize.height)
    windowTag.frame = NSRect(
      x: nameLabel.frame.maxX + 8, y: rowMid - NotchUsageTagView.height / 2, width: tagWidth,
      height: NotchUsageTagView.height)
    let paceWidth = paceTag.fittingWidth
    let paceX = windowTag.frame.maxX + 6
    let paceFits = paceX + paceWidth <= limit
    paceTag.frame = NSRect(
      x: paceX, y: rowMid - NotchUsageTagView.height / 2, width: paceWidth,
      height: NotchUsageTagView.height)
    paceTag.alphaValue = paceFits ? 1 : 0

    // Chiffre principal et sa ligne de légende.
    let figureSize = figureLabel.intrinsicContentSize
    figureLabel.frame = NSRect(
      x: inset, y: 32, width: ceil(figureSize.width) + Self.labelPadding,
      height: figureSize.height)

    let absoluteSize = absoluteLabel.intrinsicContentSize
    let updatedSize = updatedLabel.intrinsicContentSize
    let columnWidth = min(ceil(max(absoluteSize.width, updatedSize.width)), 150)
    let columnX = right - columnWidth
    absoluteLabel.frame = NSRect(
      x: columnX, y: 32 + 25, width: columnWidth, height: absoluteSize.height)
    updatedLabel.frame = NSRect(x: columnX, y: 32 + 8, width: columnWidth, height: updatedSize.height)

    let captionX = figureLabel.frame.maxX + 10
    let captionWidth = max(0, (columnWidth > 0 ? columnX : right) - captionX - 12)
    let captionSize = captionLabel.intrinsicContentSize
    let secondarySize = secondaryLabel.intrinsicContentSize
    captionLabel.frame = NSRect(
      x: captionX, y: 32 + 25, width: captionWidth, height: captionSize.height)
    secondaryLabel.frame = NSRect(
      x: captionX, y: 32 + 8, width: captionWidth, height: secondarySize.height)

    gauge.frame = NSRect(x: inset, y: 14, width: right - inset, height: 14)

    // État d'erreur : icône, raison sur deux lignes au plus, action à droite.
    actionButton.sizeToFit()
    let buttonWidth = max(actionButton.frame.width, 84)
    let areaMid: CGFloat = 32 + 23
    actionButton.frame = NSRect(
      x: right - buttonWidth, y: areaMid - actionButton.frame.height / 2, width: buttonWidth,
      height: actionButton.frame.height)
    errorIcon.frame = NSRect(x: inset, y: areaMid - 11, width: 22, height: 22)
    reasonLabel.frame = NSRect(
      x: errorIcon.frame.maxX + 12, y: areaMid - 20,
      width: max(0, actionButton.frame.minX - errorIcon.frame.maxX - 28), height: 40)
  }

  // MARK: - Info-bulles

  /// Les enfants ne reçoivent pas la souris (la carte la garde) : les info-bulles se choisissent
  /// ici selon l'endroit survolé.
  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    switch mode {
    case .failed:
      return reading.status.reasonText ?? ""
    case .loading:
      return ""
    case .loaded:
      if let resetsAt = reading.resetsAt,
        resetLabel.frame.union(absoluteLabel.frame).insetBy(dx: -6, dy: -4).contains(point)
      {
        return Self.fullFormatter.string(from: resetsAt)
      }
      if !paceTag.isHidden, paceTag.alphaValue > 0, paceTag.frame.contains(point) {
        return "The tick on the gauge is where an even pace would leave you."
      }
      return "Click to compare providers · click the figure to flip remaining and used"
    }
  }

  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()
    registerToolTips()
  }

  private func registerToolTips() {
    removeAllToolTips()
    addToolTip(bounds, owner: self, userData: nil)
  }

  // MARK: - Souris

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// VoiceOver et le clavier d'accessibilité « pressent » la carte : comme un clic.
  override func accessibilityPerformPress() -> Bool {
    guard mode != .failed else { return false }
    onToggleCompare?()
    return true
  }

  /// Les clics appartiennent à la carte, sauf ceux du bouton de l'état d'erreur.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard bounds.contains(local) else { return nil }
    if !errorView.isHidden, actionButton.frame.contains(local) { return actionButton }
    return self
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

  override func mouseDown(with event: NSEvent) { pager.mouseDown(event) }

  override func mouseDragged(with event: NSEvent) { pager.mouseDragged(event) }

  override func mouseUp(with event: NSEvent) {
    let swiped = pager.mouseUp(event)
    let point = convert(event.locationInWindow, from: nil)
    guard !swiped, bounds.contains(point) else { return }
    // Le chiffre alterne reste et consommé ; le reste de la carte ouvre la comparaison.
    let figureArea = figureLabel.frame.union(captionLabel.frame).insetBy(dx: -6, dy: -4)
    if mode == .loaded, figureArea.contains(point) {
      toggleUsed()
    } else if mode != .failed {
      onToggleCompare?()
    }
  }

  override func scrollWheel(with event: NSEvent) {
    if !pager.scrollWheel(event) { super.scrollWheel(with: event) }
  }

  private func toggleUsed() {
    showsUsed.toggle()
    let remaining = reading.remainingPercentage ?? 0
    let target = showsUsed ? NotchUsageFormatting.usedPercentage(remainingPercentage: remaining) : remaining
    captionLabel.stringValue = showsUsed ? "used" : "remaining"
    // Le chiffre se renverse : il part de l'autre valeur vers la nouvelle.
    startCount(to: target)
    needsLayout = true
  }
}

extension NotchUsageReading.Status {
  /// Raison complète d'un état d'erreur, pour l'info-bulle.
  fileprivate var reasonText: String? {
    if case .unavailable(let reason) = self { return reason }
    return nil
  }
}
