import AppKit

/// La liste des sessions d'agent de l'onglet AI : à gauche une carte par session (projet, action en
/// cours, durée) à peine teintée de la couleur de son statut, à droite la relecture de la session
/// choisie (`AgentActivityCardView`) : frise des actions et historique en texte. Quand la session attend (demande ou
/// fin de tour), Deny / Allow / Always et un champ pour la diriger apparaissent sous le code. Sans
/// session : un court message et une action.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay. Les boutons sont ceux de la
/// carte de demande.
final class AgentSessionsView: NSView {

  /// Réponse à la demande d'une session (permission depuis la liste).
  var onDecision: ((AgentEvent, AgentEvent.Decision) -> Void)?
  /// Consigne pour une seule session : (identifiant de session, texte).
  var onSteer: ((String, String) -> Void)?
  var onSelect: ((String) -> Void)?
  /// Ouvre la demande d'une session sur la grande carte (plan, question, formulaire).
  var onPromote: ((AgentEvent) -> Void)?
  /// L'action de l'état vide : mener l'utilisateur là où il lance un agent.
  var onStartAgent: (() -> Void)?

  private(set) var sessions: [AgentSession] = []
  private(set) var selectedID: String?

  // Liste et détail.
  private let listBox = NSView()
  private var rows: [SessionRow] = []
  /// La relecture de la session choisie.
  private let replay = AgentActivityCardView()
  private let denyButton = PromptButton(title: "Deny", style: .secondary)
  private let allowButton = PromptButton(title: "Allow", style: .primary)
  private let alwaysButton = PromptButton(title: "Always", style: .secondary)
  private let answerButton = PromptButton(title: "Answer…", style: .secondary)

  // Champ de consigne.
  private let steerBox = NSView()
  private let steerInput = SteerTextView(usingTextLayoutManager: false)
  private let steerPlaceholder = NSTextField(labelWithString: "Steer this session…")
  private let sendButton = PromptButton(title: "Send", style: .primary, icon: "arrow.up")

  // État vide.
  private let emptyIcon = NSImageView()
  private let emptyTitle = NSTextField(labelWithString: "No agents running")
  private let emptyMessage = NSTextField(
    wrappingLabelWithString: "Start Claude Code in a terminal and its sessions appear here.")
  private let emptyButton = PromptButton(title: "Open Terminal", style: .primary)

  private let listWidth: CGFloat = 188
  private let rowHeight: CGFloat = 54
  private let inset: CGFloat = 18
  private let controlHeight: CGFloat = 34
  private let inputLineHeight: CGFloat = 15
  private let inputMaxLines = 4
  private var clock: Timer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

    replay.drawsBackground = false
    denyButton.onClick = { [weak self] in self?.decide(.deny) }
    allowButton.onClick = { [weak self] in self?.decide(.allow) }
    alwaysButton.onClick = { [weak self] in self?.decide(.allowAlways) }
    answerButton.onClick = { [weak self] in self?.promote() }
    [denyButton, allowButton, alwaysButton, answerButton].forEach(addSubview)

    // Le champ reprend celui de la carte de demande : fond noir 35 %, liseré, rond d'envoi dedans.
    steerBox.wantsLayer = true
    steerBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    steerBox.layer?.borderWidth = 1
    steerBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    steerInput.isRichText = false
    steerInput.drawsBackground = false
    steerInput.font = .systemFont(ofSize: 12)
    steerInput.textColor = .white
    steerInput.insertionPointColor = .white
    steerInput.textContainerInset = .zero
    steerInput.textContainer?.lineFragmentPadding = 0
    steerInput.isVerticallyResizable = false
    steerInput.isHorizontallyResizable = false
    steerInput.textContainer?.widthTracksTextView = true
    steerInput.delegate = self
    steerInput.onSubmit = { [weak self] in self?.sendSteer() }
    steerInput.onFocusChange = { [weak self] focused in self?.setInputFocused(focused) }
    steerPlaceholder.font = .systemFont(ofSize: 12)
    steerPlaceholder.textColor = NSColor.white.withAlphaComponent(0.45)
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

    [listBox, replay, steerBox].forEach(addSubview)
    applyEmptyVisibility()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - État

  /// Les durées avancent chaque seconde tant que la liste est visible.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    clock?.invalidate()
    guard window != nil else { return }
    clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshClock() }
    }
  }

  func apply(sessions: [AgentSession], selectedID: String?) {
    self.sessions = sessions
    self.selectedID = selectedID ?? sessions.first?.id
    applyEmptyVisibility()
    rebuildRows()
    refreshDetail()
    needsLayout = true
  }

  private var isEmpty: Bool { sessions.isEmpty }
  private var selected: AgentSession? { sessions.first { $0.id == selectedID } }

  private func applyEmptyVisibility() {
    [emptyIcon, emptyTitle, emptyMessage, emptyButton].forEach { $0.isHidden = !isEmpty }
    [listBox, replay].forEach { $0.isHidden = isEmpty }
    if isEmpty {
      steerBox.isHidden = true
      [denyButton, allowButton, alwaysButton, answerButton].forEach { $0.isHidden = true }
    }
  }

  private func rebuildRows() {
    while rows.count < sessions.count {
      let row = SessionRow()
      row.onClick = { [weak self] id in self?.onSelect?(id) }
      listBox.addSubview(row)
      rows.append(row)
    }
    while rows.count > sessions.count { rows.removeLast().removeFromSuperview() }
    for (row, session) in zip(rows, sessions) {
      row.apply(session, selected: session.id == selectedID, now: Date())
    }
  }

  private func refreshClock() {
    for (row, session) in zip(rows, sessions) {
      row.apply(session, selected: session.id == selectedID, now: Date())
    }
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
    replay.apply(
      project: session.project, source: session.source.label,
      items: AgentReplay.items(for: session))

    // Le champ et les boutons n'apparaissent que si l'agent attend : une approbation, ou une suite.
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
    denyButton.isHidden = !(asks && tool)
    allowButton.isHidden = !(asks && tool)
    if !(asks && tool) { alwaysButton.isHidden = true }
    answerButton.isHidden = !(asks && !tool)
    if case .none = wait { steerBox.isHidden = true } else { steerBox.isHidden = false }
    needsLayout = true
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
    inputChanged()
    onSteer?(id, text)
  }

  /// Le liseré s'éclaircit quand le champ a le clavier, comme le focus des choix de la carte.
  private func setInputFocused(_ focused: Bool) {
    steerBox.layer?.borderColor =
      NSColor.white.withAlphaComponent(focused ? 0.45 : 0.12).cgColor
  }

  private func inputChanged() {
    let hasText = !steerInput.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    sendButton.isEnabled = hasText
    steerPlaceholder.isHidden = !steerInput.string.isEmpty
    needsLayout = true
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
    listBox.frame = CGRect(x: 0, y: 0, width: listWidth, height: height)
    // Les cartes descendent du haut ; celles qui dépassent restent hors du cadre.
    for (index, row) in rows.enumerated() {
      row.frame = CGRect(
        x: 10, y: height - 10 - CGFloat(index + 1) * rowHeight + 6, width: listWidth - 20,
        height: rowHeight - 8)
    }

    // La relecture prend tout le reste ; ce qui attend la main se range sous son code.
    replay.frame = CGRect(x: listWidth, y: 0, width: bounds.width - listWidth, height: height)
    let column = replay.contentColumn
    let x = replay.frame.minX + column.x
    let width = column.width
    var bottom: CGFloat = 14
    if !steerBox.isHidden {
      let boxHeight = max(controlHeight, ceil(inputTextHeight) + 18)
      steerBox.frame = CGRect(x: x, y: bottom, width: width, height: boxHeight)
      steerBox.layer?.cornerRadius = boxHeight > controlHeight ? 14 : boxHeight / 2
      let icon: CGFloat = 26
      sendButton.frame = CGRect(x: width - 4 - icon, y: 4, width: icon, height: icon)
      let textWidth = width - 16 - icon - 12
      steerInput.frame = CGRect(
        x: 16, y: (boxHeight - inputTextHeight) / 2, width: textWidth, height: inputTextHeight)
      steerPlaceholder.sizeToFit()
      steerPlaceholder.frame.origin = CGPoint(
        x: 16, y: (boxHeight - steerPlaceholder.frame.height) / 2)
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

  // MARK: - Carte de session

  /// Une session dans la liste : un dégradé qui part du transparent vers la couleur de son statut,
  /// le projet, l'action et la durée.
  private final class SessionRow: NSView {
    var onClick: ((String) -> Void)?
    private var sessionID = ""
    private let gradient = CAGradientLayer()
    private let dot = NSView()
    private let taskLabel = NSTextField(labelWithString: "")
    private let actionLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.cornerRadius = 12
      layer?.masksToBounds = true
      layer?.borderWidth = 1
      gradient.startPoint = CGPoint(x: 0, y: 0.5)
      gradient.endPoint = CGPoint(x: 1, y: 0.5)
      gradient.locations = [0.62, 1]
      layer?.insertSublayer(gradient, at: 0)
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
      [dot, taskLabel, actionLabel, timeLabel].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func apply(_ session: AgentSession, selected: Bool, now: Date) {
      sessionID = session.id
      taskLabel.stringValue = session.project
      actionLabel.stringValue = session.action
      timeLabel.stringValue = Self.format(session.elapsed(now: now))
      let color = Self.color(for: session.status)
      dot.layer?.backgroundColor = color.cgColor
      // Une teinte à peine perceptible, sur le dernier tiers de la carte seulement.
      gradient.colors = [
        color.withAlphaComponent(0).cgColor,
        color.withAlphaComponent(selected ? 0.16 : 0.09).cgColor,
      ]
      layer?.borderColor = NSColor.white.withAlphaComponent(selected ? 0.22 : 0.07).cgColor
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

    override func layout() {
      super.layout()
      gradient.frame = bounds
      dot.frame = CGRect(x: 14, y: bounds.height - 22, width: 8, height: 8)
      timeLabel.frame = CGRect(x: bounds.width - 54, y: bounds.height - 25, width: 40, height: 14)
      taskLabel.frame = CGRect(x: 30, y: bounds.height - 26, width: bounds.width - 88, height: 16)
      actionLabel.frame = CGRect(x: 30, y: 9, width: bounds.width - 44, height: 14)
    }

    override func mouseDown(with event: NSEvent) {
      onClick?(sessionID)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
