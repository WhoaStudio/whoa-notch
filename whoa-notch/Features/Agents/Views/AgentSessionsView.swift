import AppKit

/// La liste des sessions d'agent de l'onglet AI : à gauche une carte par session (projet, action en
/// cours, durée) à peine teintée de la couleur de son statut, à droite la relecture de la session
/// choisie (`AgentActivityCardView`) : frise des actions et historique en texte. Quand la session attend (demande ou
/// fin de tour), Deny / Allow / Always et un champ pour la diriger apparaissent sous le code. Sans
/// session : un court message et une action.
///
/// La liste défile, se parcourt avec ↑ / ↓, et une session close s'écarte d'un balayage à deux
/// doigts vers la gauche, du bouton ✕ au survol, de la touche Suppr ou de l'action VoiceOver.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay. Les boutons sont ceux de la
/// carte de demande.
final class AgentSessionsView: NSView {

  /// Réponse à la demande d'une session (permission depuis la liste).
  var onDecision: ((AgentEvent, AgentEvent.Decision) -> Void)?
  /// Consigne pour une seule session : (identifiant de session, texte).
  var onSteer: ((String, String) -> Void)?
  var onSelect: ((String) -> Void)?
  /// Écarte une session close de la liste.
  var onDismiss: ((String) -> Void)?
  /// Ouvre la demande d'une session sur la grande carte (plan, question, formulaire).
  var onPromote: ((AgentEvent) -> Void)?
  /// L'action de l'état vide : mener l'utilisateur là où il lance un agent.
  var onStartAgent: (() -> Void)?

  private(set) var sessions: [AgentSession] = []
  private(set) var selectedID: String?
  /// La session dont la relecture est affichée.
  private var shownID: String?
  /// Le texte saisi pour chaque session, pour qu'une consigne ne parte pas vers une autre.
  private var drafts: [String: String] = [:]

  // Liste et détail.
  private let listScroll = NSScrollView()
  private let listDocument = SessionListDocument()
  private var rows: [SessionRow] = []
  private var listFocused = false
  /// La relecture de la session choisie.
  private let replay = AgentActivityCardView()
  private let denyButton = PromptButton(title: "Deny", style: .secondary)
  private let allowButton = PromptButton(title: "Allow", style: .primary)
  private let alwaysButton = PromptButton(title: "Always", style: .secondary)
  private let answerButton = PromptButton(title: "Answer…", style: .secondary)

  // Champ de consigne.
  private let steerBox = NSView()
  private let steerInput = SteerTextView(usingTextLayoutManager: false)
  private let steerPlaceholder = NSTextField(
    labelWithString: "Steer this session  ·  ↩ send, ⇧↩ new line")
  private let sendButton = PromptButton(title: "Send", style: .primary, icon: "arrow.up")

  // État vide.
  private let emptyIcon = NSImageView()
  private let emptyTitle = NSTextField(labelWithString: "No agents running")
  private let emptyMessage = NSTextField(
    wrappingLabelWithString: "Start Claude Code in a terminal and its sessions appear here.")
  private let emptyButton = PromptButton(title: "Open Terminal", style: .primary)

  private let listWidth: CGFloat = 188
  /// Pas d'une carte dans la liste, écart compris.
  private let rowPitch: CGFloat = 60
  private let rowGap: CGFloat = 8
  private let listPadding: CGFloat = 10
  private let inset: CGFloat = 18
  private let controlHeight: CGFloat = 34
  /// Une ligne de 12 pt et son interligne de 2,5 pt.
  private let inputLineHeight: CGFloat = 17
  private let inputMaxLines = 4
  private var clock: Timer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

    listScroll.documentView = listDocument
    listScroll.drawsBackground = false
    listScroll.hasVerticalScroller = true
    listScroll.hasHorizontalScroller = false
    listScroll.autohidesScrollers = true
    listScroll.scrollerStyle = .overlay
    listScroll.horizontalScrollElasticity = .none
    listScroll.verticalScrollElasticity = .allowed
    listScroll.usesPredominantAxisScrolling = true
    listDocument.setAccessibilityRole(.list)
    listDocument.setAccessibilityLabel("Agent sessions")

    replay.drawsBackground = false
    denyButton.onClick = { [weak self] in self?.decide(.deny) }
    allowButton.onClick = { [weak self] in self?.decide(.allow) }
    alwaysButton.onClick = { [weak self] in self?.decide(.allowAlways) }
    answerButton.onClick = { [weak self] in self?.promote() }
    // Les boutons et le champ sont rangés sous la relecture, qui est posée au-dessus pour que
    // l'aperçu du diff les recouvre ; elle laisse passer les clics là où elle n'a rien (`hitTest`).
    [denyButton, allowButton, alwaysButton, answerButton].forEach(addSubview)

    // Le champ reprend celui de la carte de demande : fond noir 35 %, liseré, rond d'envoi dedans.
    steerBox.wantsLayer = true
    steerBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    steerBox.layer?.borderWidth = 1
    steerBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    let inputFont = NSFont.systemFont(ofSize: 12)
    let inputParagraph = NSMutableParagraphStyle()
    inputParagraph.lineSpacing = 2.5
    steerInput.isRichText = false
    steerInput.drawsBackground = false
    steerInput.font = inputFont
    steerInput.textColor = .white
    steerInput.defaultParagraphStyle = inputParagraph
    steerInput.typingAttributes = [
      .font: inputFont, .foregroundColor: NSColor.white, .paragraphStyle: inputParagraph,
    ]
    steerInput.insertionPointColor = .white
    steerInput.textContainerInset = .zero
    steerInput.textContainer?.lineFragmentPadding = 0
    steerInput.isVerticallyResizable = false
    steerInput.isHorizontallyResizable = false
    steerInput.textContainer?.widthTracksTextView = true
    steerInput.setAccessibilityLabel("Steer this session")
    steerInput.setAccessibilityHelp("Return sends, Shift-Return adds a new line.")
    steerInput.delegate = self
    steerInput.onSubmit = { [weak self] in self?.sendSteer() }
    steerInput.onFocusChange = { [weak self] focused in self?.setInputFocused(focused) }
    steerPlaceholder.font = inputFont
    steerPlaceholder.textColor = NSColor.white.withAlphaComponent(0.45)
    steerPlaceholder.lineBreakMode = .byTruncatingTail
    sendButton.onClick = { [weak self] in self?.sendSteer() }
    sendButton.isEnabled = false
    [steerInput, steerPlaceholder, sendButton].forEach(steerBox.addSubview)

    emptyIcon.image = NSImage(
      systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
    emptyIcon.contentTintColor = NSColor.white.withAlphaComponent(0.35)
    emptyTitle.font = .systemFont(ofSize: 14, weight: .semibold)
    emptyTitle.textColor = .white
    emptyTitle.alignment = .center
    emptyMessage.font = .systemFont(ofSize: 12)
    emptyMessage.textColor = NSColor.white.withAlphaComponent(0.55)
    emptyMessage.alignment = .center
    emptyButton.onClick = { [weak self] in self?.onStartAgent?() }
    [emptyIcon, emptyTitle, emptyMessage, emptyButton].forEach(addSubview)

    // Sous la relecture : voir plus haut.
    addSubview(steerBox, positioned: .below, relativeTo: nil)
    [listScroll, replay].forEach(addSubview)
    applyEmptyVisibility()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - État

  /// Les durées avancent chaque seconde, seulement tant que la liste est à l'écran et qu'une session tourne.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateClock()
  }

  override func viewDidHide() {
    super.viewDidHide()
    updateClock()
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    updateClock()
  }

  func apply(sessions: [AgentSession], selectedID: String?) {
    let previousIDs = Set(self.sessions.map(\.id))
    let previousSelection = self.selectedID
    let countChanged = sessions.count != self.sessions.count
    self.sessions = sessions
    let known = selectedID.flatMap { id in sessions.contains { $0.id == id } ? id : nil }
    self.selectedID = known ?? sessions.first?.id
    let ids = Set(sessions.map(\.id))
    drafts = drafts.filter { ids.contains($0.key) }

    applyEmptyVisibility()
    rebuildRows()
    refreshDetail()
    updateClock()
    if countChanged, !previousIDs.isEmpty { animateLayout() } else { needsLayout = true }

    // Une session qui arrive entre en glissant ; la première vague, elle, est simplement là.
    if !previousIDs.isEmpty {
      layoutSubtreeIfNeeded()
      for row in rows where !previousIDs.contains(row.sessionID) {
        row.layer?.springReveal(x: -8, y: 0)
      }
    }
    if self.selectedID != previousSelection { revealSelectedRow() }
  }

  private var isEmpty: Bool { sessions.isEmpty }
  private var selected: AgentSession? { sessions.first { $0.id == selectedID } }

  private func applyEmptyVisibility() {
    [emptyIcon, emptyTitle, emptyMessage, emptyButton].forEach { $0.isHidden = !isEmpty }
    [listScroll, replay].forEach { $0.isHidden = isEmpty }
    if isEmpty {
      steerBox.isHidden = true
      [denyButton, allowButton, alwaysButton, answerButton].forEach { $0.isHidden = true }
    }
  }

  /// Une carte par session, gardée d'une mise à jour à l'autre : quand une session part, les
  /// suivantes remontent au lieu de changer de contenu sur place.
  private func rebuildRows() {
    var byID = Dictionary(rows.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
    var ordered: [SessionRow] = []
    var added: [Int] = []
    for (index, session) in sessions.enumerated() {
      if let row = byID.removeValue(forKey: session.id) {
        ordered.append(row)
      } else {
        let row = SessionRow()
        row.onClick = { [weak self] id in self?.rowClicked(id) }
        row.onDismiss = { [weak self] id in self?.onDismiss?(id) }
        listDocument.addSubview(row)
        ordered.append(row)
        added.append(index)
      }
    }
    byID.values.forEach { $0.removeFromSuperview() }
    rows = ordered
    let now = Date()
    for (row, session) in zip(rows, sessions) {
      row.apply(session, selected: session.id == selectedID, focused: listFocused, now: now)
    }
    // Une nouvelle carte se pose à sa place avant toute animation, sans partir d'un cadre vide.
    for index in added { rows[index].frame = rowFrame(at: index) }
  }

  private func rowFrame(at index: Int) -> CGRect {
    CGRect(
      x: listPadding, y: listPadding + CGFloat(index) * rowPitch,
      width: listWidth - listPadding * 2, height: rowPitch - rowGap)
  }

  private func updateClock() {
    let needed =
      window != nil && !isHiddenOrHasHiddenAncestor && sessions.contains { $0.endedAt == nil }
    if needed, clock == nil {
      let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshClock() }
      }
      timer.tolerance = 0.25
      RunLoop.main.add(timer, forMode: .common)
      clock = timer
    } else if !needed {
      clock?.invalidate()
      clock = nil
    }
  }

  /// Seules les durées changent : rien d'autre n'est redessiné.
  private func refreshClock() {
    guard window?.occlusionState.contains(.visible) == true else { return }
    let now = Date()
    for (row, session) in zip(rows, sessions) { row.updateTime(session, now: now) }
  }

  /// Ce que la session choisie attend de l'utilisateur.
  private enum Wait { case none, steer, approval(AgentEvent) }
  private var wait: Wait = .none

  private func refreshDetail() {
    guard let session = selected else {
      wait = .none
      steerBox.isHidden = true
      [denyButton, allowButton, alwaysButton, answerButton].forEach { $0.isHidden = true }
      return
    }
    let switched = session.id != shownID
    let hadSession = shownID != nil
    if switched {
      if let old = shownID, sessions.contains(where: { $0.id == old }) {
        let text = steerInput.string
        drafts[old] = text.isEmpty ? nil : text
      }
      steerInput.string = drafts[session.id] ?? ""
      lastInputHeight = 0
      inputChanged()
      shownID = session.id
    }
    replay.apply(
      project: session.project, source: session.source.label,
      items: AgentReplay.items(for: session))
    if switched, hadSession { fadeInReplay() }

    // Le champ et les boutons n'apparaissent que si l'agent attend : une approbation, ou une suite.
    let previousWait = wait
    if session.status == .blocked, let pending = session.pending, pending.replyID != nil {
      wait = .approval(pending)
    } else if session.status == .waiting {
      wait = .steer
    } else {
      wait = .none
    }
    var tool = false
    var asks = false
    if case .approval(let pending) = wait {
      asks = true
      if case .tool = pending.prompt { tool = true }
      alwaysButton.isHidden = !(tool && pending.offersAlways)
    }
    let controls = [denyButton, allowButton, alwaysButton, answerButton, steerBox]
    let wasVisible = controls.map { !$0.isHidden }
    denyButton.isHidden = !(asks && tool)
    allowButton.isHidden = !(asks && tool)
    if !(asks && tool) { alwaysButton.isHidden = true }
    answerButton.isHidden = !(asks && !tool)
    if case .none = wait { steerBox.isHidden = true } else { steerBox.isHidden = false }

    // Sur la même session, ce qui apparaît monte de 6 pt et la relecture lui fait place en douceur.
    if !switched, Self.kind(of: wait) != Self.kind(of: previousWait) {
      animateLayout()
      for (view, was) in zip(controls, wasVisible) where !was && !view.isHidden {
        view.layer?.springReveal(y: -6)
      }
    } else {
      needsLayout = true
    }
  }

  private static func kind(of wait: Wait) -> Int {
    switch wait {
    case .none: 0
    case .steer: 1
    case .approval: 2
    }
  }

  // MARK: - Mouvement

  /// Rejoue la mise en page en animant les cadres ; sans mouvement autorisé, elle se fait d'un coup.
  private func animateLayout() {
    needsLayout = true
    guard OverlayAnimation.allowsMotion, window != nil, !isHiddenOrHasHiddenAncestor else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
      context.allowsImplicitAnimation = true
      layoutSubtreeIfNeeded()
    }
  }

  /// Changer de session fond la relecture plutôt que de la remplacer d'un coup.
  private func fadeInReplay() {
    guard OverlayAnimation.allowsMotion, let layer = replay.layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.18
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(fade, forKey: "sessionSwitch")
  }

  private func revealSelectedRow() {
    guard let row = rows.first(where: { $0.sessionID == selectedID }) else { return }
    layoutSubtreeIfNeeded()
    listDocument.scrollToVisible(row.frame.insetBy(dx: 0, dy: -listPadding))
  }

  // MARK: - Clavier

  override var acceptsFirstResponder: Bool { !isEmpty }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { setListFocused(true) }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { setListFocused(false) }
    return resigned
  }

  /// ↑ / ↓ changent de session, Suppr écarte une session close.
  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 126: moveSelection(by: -1)
    case 125: moveSelection(by: 1)
    case 51, 117:
      if let row = rows.first(where: { $0.sessionID == selectedID }), row.isDismissible {
        row.dismiss()
      } else {
        super.keyDown(with: event)
      }
    default: super.keyDown(with: event)
    }
  }

  private func setListFocused(_ focused: Bool) {
    guard listFocused != focused else { return }
    listFocused = focused
    rebuildRows()
  }

  private func moveSelection(by delta: Int) {
    guard !sessions.isEmpty else { return }
    let current = sessions.firstIndex { $0.id == selectedID } ?? 0
    let next = min(max(current + delta, 0), sessions.count - 1)
    guard next != current else { return }
    onSelect?(sessions[next].id)
  }

  /// Un clic choisit la session ; il ne prend le clavier que si le champ de consigne ne l'a pas.
  private func rowClicked(_ id: String) {
    if window?.firstResponder !== steerInput { window?.makeFirstResponder(self) }
    onSelect?(id)
  }

  // MARK: - Actions

  private func decide(_ decision: AgentEvent.Decision) {
    guard let pending = selected?.pending else { return }
    onDecision?(pending, decision)
  }

  private func promote() {
    guard let pending = selected?.pending else { return }
    onPromote?(pending)
  }

  private func sendSteer() {
    let text = steerInput.string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let id = selectedID else { return }
    steerInput.string = ""
    drafts[id] = nil
    inputChanged()
    onSteer?(id, text)
  }

  /// Le liseré s'éclaircit quand le champ a le clavier, comme le focus des choix de la carte.
  private func setInputFocused(_ focused: Bool) {
    steerBox.layer?.borderColor =
      NSColor.white.withAlphaComponent(focused ? 0.45 : 0.12).cgColor
  }

  private var lastInputHeight: CGFloat = 0

  private func inputChanged() {
    let hasText = !steerInput.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    sendButton.isEnabled = hasText
    steerPlaceholder.isHidden = !steerInput.string.isEmpty
    // Le champ grandit ligne à ligne en douceur ; une frappe sur la même ligne ne bouge rien.
    let height = inputTextHeight
    if height != lastInputHeight, lastInputHeight > 0, !steerBox.isHidden {
      lastInputHeight = height
      animateLayout()
    } else {
      lastInputHeight = height
      needsLayout = true
    }
  }

  // MARK: - Mise en page

  /// Hauteur du texte saisi, de une à `inputMaxLines` lignes.
  private var inputTextHeight: CGFloat {
    guard let layoutManager = steerInput.layoutManager, let container = steerInput.textContainer
    else { return inputLineHeight }
    layoutManager.ensureLayout(for: container)
    let used = ceil(layoutManager.usedRect(for: container).height)
    return min(max(used, inputLineHeight), inputLineHeight * CGFloat(inputMaxLines))
  }

  override func layout() {
    super.layout()
    let height = bounds.height
    if isEmpty {
      layoutEmptyState()
      return
    }
    listScroll.frame = CGRect(x: 0, y: 0, width: listWidth, height: height)
    let contentHeight = listPadding * 2 + CGFloat(rows.count) * rowPitch - rowGap
    listDocument.frame = CGRect(
      x: 0, y: 0, width: listScroll.contentSize.width, height: max(height, contentHeight))
    // La liste est retournée : les cartes descendent du haut et défilent au-delà.
    for (index, row) in rows.enumerated() { row.frame = rowFrame(at: index) }

    // La relecture prend tout le reste ; ce qui attend la main se range sous son code.
    replay.frame = CGRect(x: listWidth, y: 0, width: bounds.width - listWidth, height: height)
    let column = replay.contentColumn
    let x = replay.frame.minX + column.x
    let width = column.width
    var bottom: CGFloat = 14
    if !steerBox.isHidden {
      let textHeight = inputTextHeight
      let boxHeight = max(controlHeight, ceil(textHeight) + 18)
      steerBox.frame = CGRect(x: x, y: bottom, width: width, height: boxHeight)
      steerBox.layer?.cornerRadius = boxHeight > controlHeight ? 14 : boxHeight / 2
      let icon: CGFloat = 26
      sendButton.frame = CGRect(x: width - 4 - icon, y: 4, width: icon, height: icon)
      let textWidth = width - 16 - icon - 12
      steerInput.frame = CGRect(
        x: 16, y: (boxHeight - textHeight) / 2, width: textWidth, height: textHeight)
      let placeholderHeight = ceil(steerPlaceholder.intrinsicContentSize.height)
      steerPlaceholder.frame = CGRect(
        x: 16, y: (boxHeight - placeholderHeight) / 2, width: textWidth, height: placeholderHeight)
      bottom += boxHeight + 10
    }
    let buttons = [alwaysButton, allowButton, denyButton, answerButton].filter { !$0.isHidden }
    if !buttons.isEmpty {
      var buttonX = x + width
      for button in buttons {
        let size = max(button.fittingWidth, 56)
        buttonX -= size
        button.frame = CGRect(x: buttonX, y: bottom, width: size, height: 28)
        buttonX -= 8
      }
      bottom += 28 + 10
    }
    replay.bottomInset = bottom > 14 ? bottom : nil
  }

  private func layoutEmptyState() {
    let centerX = bounds.midX
    let messageWidth: CGFloat = min(280, bounds.width - 48)
    let messageHeight = ceil(
      emptyMessage.sizeThatFits(NSSize(width: messageWidth, height: .greatestFiniteMagnitude))
        .height)
    let buttonWidth = emptyButton.fittingWidth
    let total: CGFloat = 28 + 14 + 18 + 10 + messageHeight + 24 + controlHeight
    var y = (bounds.height + total) / 2
    y -= 28
    emptyIcon.frame = CGRect(x: centerX - 14, y: y, width: 28, height: 28)
    y -= 14 + 18
    emptyTitle.frame = CGRect(x: centerX - messageWidth / 2, y: y, width: messageWidth, height: 18)
    y -= 10 + messageHeight
    emptyMessage.frame = CGRect(
      x: centerX - messageWidth / 2, y: y, width: messageWidth, height: messageHeight)
    y -= 24 + controlHeight
    emptyButton.frame = CGRect(
      x: centerX - buttonWidth / 2, y: y, width: buttonWidth, height: controlHeight)
  }
}

// MARK: - Liste

/// Le document de la liste, retourné pour que les cartes partent du haut.
private final class SessionListDocument: NSView {
  override var isFlipped: Bool { true }
}

// MARK: - Carte de session

/// Une session dans la liste : un dégradé qui part du transparent vers la couleur de son statut,
/// le projet, l'action et la durée. Une session close se balaie vers la gauche pour l'écarter ;
/// un ✕ au survol, Suppr et l'action VoiceOver « Dismiss » font de même.
private final class SessionRow: NSView {
  var onClick: ((String) -> Void)?
  var onDismiss: ((String) -> Void)?
  private(set) var sessionID = ""
  private(set) var isDismissible = false
  private var session: AgentSession?
  private var isSelected = false
  private var isFocused = false
  private var isHovered = false
  private var isPressed = false

  /// Ce qui glisse sous le doigt ; la marque d'effacement reste derrière.
  private let content = NSView()
  private let dismissMark = NSImageView()
  private let gradient = CAGradientLayer()
  private let dot = NSView()
  private let taskLabel = NSTextField(labelWithString: "")
  private let actionLabel = NSTextField(labelWithString: "")
  private let timeLabel = NSTextField(labelWithString: "")
  private let closeButton = NSButton()

  // Balayage.
  private enum Swipe { case idle, undecided(dx: CGFloat, dy: CGFloat), horizontal, vertical }
  private var swipe: Swipe = .idle
  private var rawOffset: CGFloat = 0
  private var offset: CGFloat = 0
  private var lastFingerDelta: CGFloat = 0
  /// Chaque glissement a son numéro : seule la fin du dernier lancé compte.
  private var slideGeneration = 0
  private var isLeaving = false

  /// Part de la largeur au-delà de laquelle un balayage lâché écarte la session.
  private let dismissFraction: CGFloat = 0.35

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.masksToBounds = true

    dismissMark.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
    dismissMark.contentTintColor = NSColor.white.withAlphaComponent(0.7)
    dismissMark.alphaValue = 0
    addSubview(dismissMark)

    content.wantsLayer = true
    content.layer?.cornerRadius = 12
    content.layer?.masksToBounds = true
    content.layer?.borderWidth = 1
    gradient.startPoint = CGPoint(x: 0, y: 0.5)
    gradient.endPoint = CGPoint(x: 1, y: 0.5)
    gradient.locations = [0.62, 1]
    content.layer?.insertSublayer(gradient, at: 0)
    addSubview(content)

    dot.wantsLayer = true
    dot.layer?.cornerRadius = 4
    taskLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    taskLabel.textColor = .white
    taskLabel.lineBreakMode = .byTruncatingTail
    actionLabel.font = .systemFont(ofSize: 10.5)
    actionLabel.textColor = NSColor.white.withAlphaComponent(0.6)
    actionLabel.lineBreakMode = .byTruncatingTail
    timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    timeLabel.textColor = NSColor.white.withAlphaComponent(0.7)
    timeLabel.alignment = .right

    closeButton.image = NSImage(
      systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Dismiss session")?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.6)
    closeButton.toolTip = "Dismiss"
    closeButton.target = self
    closeButton.action = #selector(closeClicked)
    closeButton.isHidden = true
    [dot, taskLabel, actionLabel, timeLabel, closeButton].forEach(content.addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ session: AgentSession, selected: Bool, focused: Bool, now: Date) {
    let newSession = session.id != sessionID
    if newSession {
      // La carte est réutilisée pour une autre session : rien du balayage précédent ne reste.
      swipe = .idle
      rawOffset = 0
      offset = 0
      isLeaving = false
      slideGeneration += 1
      content.layer?.removeAllAnimations()
    }
    let styleChanged = !newSession && (selected != isSelected || focused != isFocused)
    sessionID = session.id
    self.session = session
    isSelected = selected
    isFocused = focused
    isDismissible = session.status == .done
    // La session est repartie pendant qu'elle sortait : la carte revient à sa place.
    if !newSession, !isDismissible, isLeaving || offset != 0 {
      isLeaving = false
      swipe = .idle
      slide(to: 0)
    }
    taskLabel.stringValue = session.project
    actionLabel.stringValue = session.action
    timeLabel.stringValue = Self.format(session.elapsed(now: now))
    refreshChrome(animated: styleChanged)
    needsLayout = true
  }

  func updateTime(_ session: AgentSession, now: Date) {
    guard session.id == sessionID else { return }
    let text = Self.format(session.elapsed(now: now))
    guard text != timeLabel.stringValue else { return }
    let widthChanged = text.count != timeLabel.stringValue.count
    timeLabel.stringValue = text
    if widthChanged { needsLayout = true }
  }

  /// Teinte, liseré, ✕ : sélection et survol. La sélection se fond en 0,18 s quand le mouvement est permis.
  private func refreshChrome(animated: Bool) {
    guard let session else { return }
    let color = Self.color(for: session.status)
    let tint: CGFloat = isSelected ? 0.16 : (isHovered ? 0.12 : 0.09)
    let borderAlpha: CGFloat =
      isSelected ? (isFocused ? 0.4 : 0.22) : (isHovered ? 0.14 : 0.07)
    let border = NSColor.white.withAlphaComponent(borderAlpha).cgColor
    let animate = animated && OverlayAnimation.allowsMotion && window != nil

    CATransaction.begin()
    CATransaction.setDisableActions(!animate)
    CATransaction.setAnimationDuration(0.18)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
    dot.layer?.backgroundColor = color.cgColor
    // Une teinte à peine perceptible, sur le dernier tiers de la carte seulement.
    gradient.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(tint).cgColor]
    if animate, let layer = content.layer {
      let fade = CABasicAnimation(keyPath: "borderColor")
      fade.fromValue = layer.presentation()?.borderColor ?? layer.borderColor
      fade.toValue = border
      layer.add(fade, forKey: "borderColor")
    }
    content.layer?.borderColor = border
    CATransaction.commit()

    closeButton.isHidden = !(isDismissible && isHovered)
    timeLabel.isHidden = !closeButton.isHidden
    content.alphaValue = isPressed ? 0.8 : 1
  }

  static func color(for status: AgentSessionStatus) -> NSColor {
    switch status {
    case .working: .systemGreen
    case .blocked: .systemOrange
    case .waiting: .systemYellow
    case .done: .systemGray
    }
  }

  static func format(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    return total >= 3600
      ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
      : String(format: "%d:%02d", total / 60, total % 60)
  }

  // MARK: Mise en page

  override func layout() {
    super.layout()
    layoutContent()
    let bounds = content.bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradient.frame = bounds
    CATransaction.commit()

    // Deux lignes : le projet en haut (marge 12), l'action en bas (marge 9), sans se chevaucher.
    let taskHeight: CGFloat = 16
    let taskY = bounds.height - 12 - taskHeight
    taskLabel.frame = CGRect(x: 30, y: taskY, width: 0, height: taskHeight)
    dot.frame = CGRect(x: 14, y: taskY + (taskHeight - 8) / 2, width: 8, height: 8)
    timeLabel.sizeToFit()
    let timeWidth = ceil(timeLabel.frame.width)
    let timeHeight = ceil(timeLabel.frame.height)
    // La durée partage la ligne de base du projet.
    let baseline = taskY + taskHeight - taskLabel.firstBaselineOffsetFromTop
    timeLabel.frame = CGRect(
      x: bounds.width - 12 - timeWidth,
      y: baseline - (timeHeight - timeLabel.firstBaselineOffsetFromTop),
      width: timeWidth, height: timeHeight)
    taskLabel.frame.size.width = max(0, timeLabel.frame.minX - 8 - 30)
    closeButton.frame = CGRect(
      x: bounds.width - 10 - 18, y: taskY + (taskHeight - 18) / 2, width: 18, height: 18)
    actionLabel.frame = CGRect(x: 30, y: 9, width: bounds.width - 30 - 12, height: 14)
  }

  private func layoutContent() {
    content.frame = bounds.offsetBy(dx: offset, dy: 0)
    let progress = min(1, max(0, -offset / (bounds.width * dismissFraction)))
    dismissMark.alphaValue = progress
    dismissMark.frame = CGRect(x: bounds.width - 30, y: (bounds.height - 16) / 2, width: 16, height: 16)
  }

  // MARK: Souris

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    refreshChrome(animated: false)
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    refreshChrome(animated: false)
  }

  /// La carte s'assombrit à l'appui ; la session n'est choisie qu'au relâché, dans la carte.
  override func mouseDown(with event: NSEvent) {
    isPressed = true
    refreshChrome(animated: false)
  }

  override func mouseUp(with event: NSEvent) {
    isPressed = false
    refreshChrome(animated: false)
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?(sessionID) }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  @objc private func closeClicked() { dismiss() }

  // MARK: Balayage

  /// Le défilement vertical continue vers la liste ; un balayage horizontal sur une session close
  /// fait suivre la carte au doigt, avec une résistance vers la droite.
  override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)
    guard isDismissible, !isLeaving, event.hasPreciseScrollingDeltas,
      event.momentumPhase.isEmpty
    else { return }
    let fingerDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    let dy = abs(event.scrollingDeltaY)

    if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
      swipe = .undecided(dx: 0, dy: 0)
      rawOffset = offset
    }
    if event.phase.contains(.began) || event.phase.contains(.changed) {
      switch swipe {
      case .undecided(let totalX, let totalY):
        let sumX = totalX + fingerDX
        let sumY = totalY + dy
        if abs(sumX) + sumY < 6 {
          swipe = .undecided(dx: sumX, dy: sumY)
        } else if abs(sumX) > sumY * 1.5 {
          swipe = .horizontal
          track(sumX)
        } else {
          swipe = .vertical
        }
      case .horizontal:
        track(fingerDX)
      case .idle, .vertical:
        break
      }
    }
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      if case .horizontal = swipe { settle(cancelled: event.phase.contains(.cancelled)) }
      swipe = .idle
    }
  }

  private func track(_ fingerDX: CGFloat) {
    rawOffset += fingerDX
    lastFingerDelta = fingerDX
    offset = rawOffset < 0 ? max(rawOffset, -bounds.width) : rawOffset * 0.25
    layoutContent()
  }

  private func settle(cancelled: Bool) {
    let flick = lastFingerDelta < -8 && offset < -20
    if !cancelled, offset < -bounds.width * dismissFraction || flick {
      dismiss()
    } else {
      slide(to: 0)
    }
  }

  /// La carte sort par la gauche, puis la session est écartée.
  func dismiss() {
    guard isDismissible, !isLeaving else { return }
    isLeaving = true
    let id = sessionID
    slide(to: -bounds.width - 8) { [weak self] in
      guard let self else { return }
      self.onDismiss?(id)
      // Écartée, la carte a quitté la liste ; refusée (session repartie), elle revient.
      if self.superview != nil, self.sessionID == id, self.isLeaving {
        self.isLeaving = false
        self.slide(to: 0)
      }
    }
  }

  private func slide(to target: CGFloat, completion: (() -> Void)? = nil) {
    offset = target
    rawOffset = target
    slideGeneration += 1
    let generation = slideGeneration
    guard OverlayAnimation.allowsMotion, window != nil else {
      layoutContent()
      completion?()
      return
    }
    nonisolated(unsafe) let completion = completion
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.24
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        context.allowsImplicitAnimation = true
        layoutContent()
      },
      completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          guard let self, self.slideGeneration == generation else { return }
          completion?()
        }
      })
  }

  // MARK: Accessibilité

  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .button }

  override func accessibilityLabel() -> String? {
    guard let session else { return nil }
    return [session.project, session.status.title, session.action, timeLabel.stringValue]
      .joined(separator: ", ")
  }

  override func accessibilityValue() -> Any? { isSelected ? "selected" : nil }

  override func accessibilityPerformPress() -> Bool {
    onClick?(sessionID)
    return true
  }

  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    guard isDismissible else { return nil }
    return [
      NSAccessibilityCustomAction(
        name: "Dismiss", target: self, selector: #selector(accessibilityDismiss))
    ]
  }

  @objc private func accessibilityDismiss() -> Bool {
    dismiss()
    return true
  }
}

// MARK: - Champ de consigne

/// Le champ multiligne : Entrée envoie, Maj+Entrée passe à la ligne.
private final class SteerTextView: NSTextView {
  var onSubmit: (() -> Void)?
  var onFocusChange: ((Bool) -> Void)?

  override func insertNewline(_ sender: Any?) {
    if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
      insertText("\n", replacementRange: selectedRange())
    } else {
      onSubmit?()
    }
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { onFocusChange?(true) }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onFocusChange?(false) }
    return resigned
  }
}

extension AgentSessionsView: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) { inputChanged() }
}
