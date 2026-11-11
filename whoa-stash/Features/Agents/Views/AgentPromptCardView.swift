import AppKit

/// Carte de l'onglet AI qui montre ce que Claude demande : le projet, l'outil, puis la commande ou
/// le fichier — ou la question et ses choix. Elle prend la place de la carte d'utilisation tant
/// qu'une demande attend.
///
/// Quand la demande attend une réponse (`replyID`), la carte répond depuis l'encoche : Allow, Deny
/// et Always pour un outil ; Change plan, Auto mode et Manual pour un plan ; pour des questions
/// ou un formulaire MCP, les choix (cochés puis validés s'ils sont multiples), « Other… » qui ouvre
/// un champ de texte, et une question après l'autre ; pour la fin d'un tour, un champ de réponse.
/// Une simple notification se lit seulement : la réponse se donne dans Claude Code.
final class AgentPromptCardView: NSView {

  var onDecision: ((AgentEvent, AgentEvent.Decision) -> Void)?
  /// Le contenu a changé (autre demande, question suivante, champ ouvert) : la hauteur voulue et le
  /// besoin de clavier ont pu changer.
  var onContentChanged: (() -> Void)?
  /// Un champ de texte est affiché : la fenêtre doit pouvoir prendre le clavier au clic.
  var showsTextInput: Bool { showsInput }
  /// Une demande à laquelle on peut répondre depuis l'encoche est affichée : la carte lit le clavier.
  var isAnswerable: Bool { event?.replyID != nil }
  /// Échap : replier le panneau, la demande reste en attente dans la pastille.
  var onFoldRequested: (() -> Void)?
  /// Choix au focus clavier (flèches, Tab) ; Entrée ou Espace le valide.
  private var focusedOption: Int? {
    didSet {
      for (index, button) in optionButtons.enumerated() {
        button.isKeyFocused = index == focusedOption
      }
    }
  }

  private var event: AgentEvent?
  /// Les rangées de boutons du pied de carte, de haut en bas.
  private var buttonRows: [[PromptButton]] = []
  private var buttons: [PromptButton] { buttonRows.flatMap { $0 } }
  /// Les choix d'une question : des lignes (avec description) ou des pastilles qui passent à la ligne.
  private var optionButtons: [PromptButton] = []
  private var optionsAreRows = false
  /// Une question parmi plusieurs : un segment par question, rempli jusqu'à la courante.
  private let stepDots = StepDots()
  /// Referme le champ « Other… » et revient aux choix.
  private let closeButton = PromptButton(title: "✕", style: .link)
  /// Questions en cours de réponse ; `nil` pour tout autre contenu.
  private var form: AgentPromptForm?
  /// Ce que la carte montre déjà : une mise à jour du même événement garde l'avancement du formulaire.
  private var appliedKey: String?
  private let hintLabel = NSTextField(labelWithString: "Answer in Claude Code")
  private let buttonHeight: CGFloat = 30

  /// Champ de texte de « Other… », d'un champ de formulaire ou d'une réponse libre.
  private let inputBox = NSView()
  private let inputField = NSTextField()
  private let inputButton = PromptButton(title: "Send", style: .primary)
  /// Réponse libre : un rond avec une flèche, dans le champ, à la place du bouton « Send ».
  private let sendIconButton = PromptButton(title: "Send", style: .primary, icon: "arrow.up")
  private var isReplyMode: Bool {
    if case .reply = event?.prompt { return event?.replyID != nil }
    return false
  }
  private var activeSendButton: PromptButton { isReplyMode ? sendIconButton : inputButton }
  private var showsInput = false

  private let dotView = NSView()
  private let projectLabel = NSTextField(labelWithString: "")
  /// Ce que l'agent veut, en gris à droite du projet (« needs permission »).
  private let verbLabel = NSTextField(labelWithString: "")
  /// Halo de couleur qui monte du bas de la carte : ambre pour une permission, turquoise pour une question.
  private let washLayer = CAGradientLayer()
  private let kindLabel = NSTextField(labelWithString: "")
  /// Lien discret en haut à droite : rend la main à l'agent (« Reply in terminal ») ou ferme la carte.
  private var headerLink: PromptButton?
  private let bodyBox = NSView()
  private let bodyLabel = NSTextField(wrappingLabelWithString: "")

  private let inset: CGFloat = 18

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
    washLayer.type = .radial
    washLayer.startPoint = CGPoint(x: 0.5, y: 0)
    washLayer.endPoint = CGPoint(x: 1.1, y: 0.95)
    washLayer.locations = [0, 1]
    layer?.addSublayer(washLayer)

    dotView.wantsLayer = true
    dotView.layer?.backgroundColor = NSColor.systemOrange.cgColor
    dotView.layer?.cornerRadius = 4

    projectLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    projectLabel.textColor = .white
    projectLabel.lineBreakMode = .byTruncatingTail
    verbLabel.font = .systemFont(ofSize: 12, weight: .regular)
    verbLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    verbLabel.lineBreakMode = .byTruncatingTail
    kindLabel.font = .systemFont(ofSize: 11, weight: .regular)
    kindLabel.textColor = NSColor.white.withAlphaComponent(0.4)
    kindLabel.alignment = .right
    kindLabel.lineBreakMode = .byTruncatingTail

    bodyBox.wantsLayer = true
    bodyBox.layer?.cornerRadius = 12
    bodyBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    bodyBox.layer?.borderWidth = 1
    bodyBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
    bodyLabel.isSelectable = false
    bodyLabel.maximumNumberOfLines = 0
    bodyLabel.lineBreakMode = .byTruncatingTail
    bodyBox.addSubview(bodyLabel)

    hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
    hintLabel.textColor = NSColor.white.withAlphaComponent(0.45)
    hintLabel.alignment = .center
    [dotView, projectLabel, verbLabel, kindLabel, bodyBox, hintLabel].forEach(addSubview)

    inputBox.wantsLayer = true
    inputBox.layer?.cornerRadius = buttonHeight / 2
    inputBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
    inputBox.layer?.borderWidth = 1
    inputBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    inputField.isBordered = false
    inputField.drawsBackground = false
    inputField.focusRingType = .none
    inputField.font = .systemFont(ofSize: 13)
    inputField.textColor = .white
    inputField.lineBreakMode = .byTruncatingTail
    inputField.cell?.usesSingleLineMode = true
    inputField.target = self
    inputField.action = #selector(submitInput)
    inputField.delegate = self
    inputBox.addSubview(inputField)
    inputButton.onClick = { [weak self] in
      self?.lastActivated = self?.inputButton
      self?.submitInput()
    }
    inputBox.isHidden = true
    inputButton.isHidden = true
    sendIconButton.onClick = { [weak self] in
      self?.lastActivated = self?.sendIconButton
      self?.submitInput()
    }
    sendIconButton.isHidden = true
    addSubview(inputBox)
    addSubview(inputButton)
    addSubview(sendIconButton)
    closeButton.onClick = { [weak self] in self?.stopTyping() }
    closeButton.isHidden = true
    addSubview(closeButton)
    stepDots.isHidden = true
    addSubview(stepDots)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Clé de l'événement affiché : tant qu'elle ne change pas, c'est la même demande.
  private func key(for event: AgentEvent) -> String {
    event.replyID ?? "\(event.project)|\(String(describing: event.prompt))"
  }

  /// Combien d'autres demandes attendent derrière celle-ci.
  private var queued = 0

  func apply(_ event: AgentEvent, queued: Int = 0) {
    self.queued = queued
    // Une autre demande prend la place de celle qui est affichée : fondu enchaîné.
    if self.event != nil, key(for: event) != appliedKey {
      swapContent { applyContent(event) }
    } else {
      applyContent(event)
    }
  }

  private func applyContent(_ event: AgentEvent) {
    self.event = event
    syncForm(for: event)
    var look = Self.look(for: event)
    // Lecture seule : même carte, teinte neutre.
    if event.replyID == nil { look.wash = NSColor.white.withAlphaComponent(0.06) }
    washLayer.colors = [look.wash.cgColor, NSColor.clear.cgColor]
    dotView.layer?.backgroundColor = look.dot.cgColor
    verbLabel.stringValue = queued > 0 ? "\(look.verb) · +\(queued) waiting" : look.verb
    bodyBox.toolTip = nil
    stepDots.isHidden = true
    rebuildFooter(for: event)
    projectLabel.stringValue = event.project
    let body = NSMutableAttributedString()
    let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let plain: [NSAttributedString.Key: Any] = [
      .font: mono, .foregroundColor: NSColor.white.withAlphaComponent(0.9),
    ]
    let bold: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
    ]
    let dim: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .regular),
      .foregroundColor: NSColor.white.withAlphaComponent(0.6),
    ]

    switch event.prompt {
    case .tool(let name, let detail):
      kindLabel.stringValue = "\(event.source.label) · \(name)"
      let command = detail.isEmpty ? name : detail
      body.append(NSAttributedString(string: command, attributes: plain))
      bodyBox.toolTip = command
    case .plan(let title, let text):
      kindLabel.stringValue = event.source.label
      body.append(NSAttributedString(string: title, attributes: bold))
      let rest = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
      if !rest.isEmpty {
        body.append(
          NSAttributedString(string: "\n" + rest.joined(separator: "\n"), attributes: dim))
      }
    case .questions(let questions):
      if let form {
        if questions.count > 1 {
          kindLabel.stringValue = ""
          stepDots.set(count: questions.count, index: form.index)
          stepDots.isHidden = false
        } else {
          kindLabel.stringValue = event.source.label
        }
        // Seule la question : les choix sont des lignes ou des pastilles sous le texte.
        body.append(NSAttributedString(string: form.current.text, attributes: bold))
      } else {
        kindLabel.stringValue =
          questions.count > 1 ? "\(event.source.label) · \(questions.count)" : event.source.label
        for (index, question) in questions.enumerated() {
          if index > 0 { body.append(NSAttributedString(string: "\n\n", attributes: plain)) }
          body.append(NSAttributedString(string: question.text, attributes: bold))
          for option in question.options {
            body.append(
              NSAttributedString(
                string: "\n\(question.multiSelect ? "☐" : "○") \(option.label)", attributes: bold))
            if !option.detail.isEmpty {
              body.append(NSAttributedString(string: "  \(option.detail)", attributes: dim))
            }
          }
        }
      }
    case .reply(let last):
      kindLabel.stringValue = event.source.label
      body.append(
        NSAttributedString(string: last.isEmpty ? "Claude finished its turn." : last, attributes: bold))
    case .message(let text):
      kindLabel.stringValue = event.source.label
      body.append(
        NSAttributedString(
          string: text, attributes: [.font: bold[.font]!, .foregroundColor: NSColor.white]))
    case nil:
      kindLabel.stringValue = ""
    }
    bodyLabel.maximumNumberOfLines = {
      if form != nil { return 2 }
      if case .tool = event.prompt { return 4 }
      if case .reply = event.prompt { return 3 }
      return 0
    }()
    // Une question n'a pas de boîte : le texte pose la question, les choix répondent dessous.
    bodyBox.layer?.backgroundColor =
      (form != nil ? NSColor.clear : NSColor.black.withAlphaComponent(0.4)).cgColor
    bodyBox.layer?.borderWidth = form != nil ? 0 : 1
    // Rien à répondre d'ici : l'en-tête dit où répondre (Claude Desktop a un lien pour l'ouvrir).
    if event.replyID == nil, event.source == .claudeCode, event.prompt != nil {
      kindLabel.stringValue = "Answer in Claude Code"
    }
    bodyLabel.attributedStringValue = body
    needsLayout = true
    onContentChanged?()
  }

  /// Hauteur dont la carte a besoin à cette largeur : le panneau grandit ou rétrécit pour elle.
  /// Mêmes mesures que `layout()` et `layoutQuestion(top:)`.
  func fittingHeight(width: CGFloat) -> CGFloat {
    let contentWidth = max(0, width - 2 * inset)
    let rowGap: CGFloat = 8
    func textHeight(_ width: CGFloat) -> CGFloat {
      ceil(bodyLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? 0)
    }
    if form != nil {
      var options: CGFloat = 0
      if showsInput {
        options = buttonHeight
      } else if !optionButtons.isEmpty {
        if optionsAreRows {
          let count = CGFloat(optionButtons.count)
          options = count * 28 + (count - 1) * 6
        } else {
          var lines = 1
          var x: CGFloat = 0
          for button in optionButtons {
            let width = min(button.fittingWidth, contentWidth)
            if x > 0, x + width > contentWidth {
              lines += 1
              x = 0
            }
            x += width + 6
          }
          options = CGFloat(lines) * 28 + CGFloat(lines - 1) * 6
        }
      }
      return 50 + min(textHeight(contentWidth), 40) + options + 12
        + CGFloat(buttonRows.count) * (buttonHeight + rowGap)
    }
    let rowCount = buttonRows.count + (showsInput ? 1 : 0)
    let footerHeight: CGFloat = rowCount == 0 ? 0 : CGFloat(rowCount) * (buttonHeight + rowGap) + 2
    return 40 + (textHeight(contentWidth - 20) + 16) + 12 + footerHeight
  }

  /// Teinte, point et verbe d'une demande : la couleur dit le genre, pas les boutons.
  private static func look(for event: AgentEvent) -> (wash: NSColor, dot: NSColor, verb: String) {
    let amber = NSColor.systemOrange
    let cyan = NSColor.systemTeal
    switch event.prompt {
    case .tool:
      return (amber.withAlphaComponent(0.34), amber, "needs permission")
    case .plan:
      return (amber.withAlphaComponent(0.34), amber, "has a plan ready")
    case .questions:
      return (
        cyan.withAlphaComponent(0.30), cyan,
        event.response == .elicitation ? "needs a form" : "is asking")
    case .reply:
      return (NSColor.white.withAlphaComponent(0.07), .systemGreen, "finished")
    case .message:
      return (NSColor.white.withAlphaComponent(0.07), amber, "needs input")
    case nil:
      return (.clear, amber, "")
    }
  }

  // MARK: - Pied de carte

  /// Un bouton du pied de carte.
  private struct Item {
    var title: String
    var style: PromptButton.Style
    var isEnabled = true
    /// Description d'un choix de question ; une ligne au lieu d'une pastille quand un choix en a une.
    var detail = ""
    /// Case cochée ou non d'un choix multiple ; `nil` hors choix multiple.
    var mark: Bool?
    /// Touche qui déclenche le bouton, rappelée par une pastille (« 1 », « ↩ »).
    var hint: String?
    var action: () -> Void
  }

  /// Ce que la carte montre sous le texte : les choix, les rangées de commandes, le champ.
  private struct Footer {
    var rows: [[Item]] = []
    var options: [Item] = []
    var input: (placeholder: String, send: String)?
    /// « Other… » est ouvert et on peut le refermer (pas pour un champ de formulaire).
    var closesInput = false
  }

  /// Le formulaire reste le même tant que l'événement ne change pas : une mise à jour (autre
  /// demande en file, compteur) ne ramène pas la carte à la première question.
  private func syncForm(for event: AgentEvent) {
    let key = key(for: event)
    defer { appliedKey = key }
    guard key != appliedKey else { return }
    inputField.stringValue = ""
    if case .questions(let questions) = event.prompt, event.replyID != nil, !questions.isEmpty {
      form = AgentPromptForm(questions: questions)
    } else {
      form = nil
    }
  }

  /// Ce que la demande permet depuis l'encoche, rangée par rangée ; vide quand la réponse reste dans
  /// Claude Code. `input` : le champ de texte et son bouton, au-dessus des rangées.
  private func footer(for event: AgentEvent) -> Footer {
    guard event.replyID != nil else { return Footer() }
    let decide: (AgentEvent.Decision) -> Void = { [weak self] decision in
      guard let self, let event = self.event else { return }
      self.send(event, decision)
    }
    switch event.prompt {
    case .tool:
      var items = [
        Item(title: "Deny", style: .secondary) { decide(.deny) },
        Item(title: "Allow", style: .primary) { decide(.allow) },
      ]
      if event.offersAlways { items.append(Item(title: "Always", style: .secondary) { decide(.allowAlways) }) }
      return Footer(rows: [items])
    case .plan:
      return Footer(rows: [
        [
          Item(title: "Change plan", style: .secondary) { decide(.plan(.change)) },
          Item(title: "Auto mode", style: .primary) { decide(.plan(.auto)) },
          Item(title: "Manual", style: .secondary) { decide(.plan(.manual)) },
        ]
      ])
    case .questions:
      guard let form else { return Footer() }
      return formFooter(form, event: event, decide: decide)
    case .reply:
      return Footer(input: ("Reply to Claude…", "Send"))
    default:
      return Footer()
    }
  }

  private func formFooter(
    _ form: AgentPromptForm, event: AgentEvent, decide: @escaping (AgentEvent.Decision) -> Void
  ) -> Footer {
    let question = form.current
    let verb = form.isLast ? "Send" : "Next"
    var footer = Footer()
    var controls: [Item] = []
    if form.isTyping {
      // « Other… » prend la place des choix, sous la question.
      footer.input = (question.freeText ? "Your answer…" : "Type your answer…", verb)
      footer.closesInput = !question.freeText
    } else {
      let selected = form.selections[form.index]
      footer.options = question.options.prefix(4).enumerated().map { index, option in
        Item(
          title: option.label, style: selected.contains(option.label) ? .selected : .secondary,
          detail: option.detail, mark: question.multiSelect ? selected.contains(option.label) : nil,
          hint: "\(index + 1)"
        ) { [weak self] in self?.choose(option.label) }
      }
      controls.append(Item(title: "Other…", style: .secondary) { [weak self] in self?.startTyping() })
      if question.multiSelect {
        controls.append(
          Item(title: verb, style: .primary, isEnabled: form.canSendChoices, hint: "↩") {
            [weak self] in
            self?.sendChoices()
          })
      }
    }
    if event.response == .elicitation {
      controls.append(Item(title: "Decline", style: .decline) { decide(.deny) })
    }
    if !controls.isEmpty { footer.rows.append(controls) }
    return footer
  }

  /// Le lien d'en-tête : rendre la main sur une question ou un formulaire, fermer une réponse libre.
  private func headerLink(for event: AgentEvent) -> (title: String, action: () -> Void)? {
    guard event.replyID != nil else {
      return event.prompt != nil && event.source == .claudeDesktop
        ? ("Open Claude", { Self.openClaudeDesktop() }) : nil
    }
    let decide: (AgentEvent.Decision) -> Void = { [weak self] decision in
      guard let self, let event = self.event else { return }
      self.send(event, decision)
    }
    switch event.prompt {
    case .questions:
      let desktop = event.source == .claudeDesktop
      return (
        desktop ? "Reply in Claude" : "Reply in terminal",
        {
          decide(.handBack)
          if desktop { Self.openClaudeDesktop() }
        }
      )
    case .reply:
      return ("Dismiss", { decide(.handBack) })
    default:
      return nil
    }
  }

  private static func openClaudeDesktop() {
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: ClaudeDesktopWatcher.bundleID)
    else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
  }

  private func rebuildFooter(for event: AgentEvent) {
    buttons.forEach { $0.removeFromSuperview() }
    optionButtons.forEach { $0.removeFromSuperview() }
    focusedOption = nil
    lastActivated = nil
    let footer = footer(for: event)
    optionsAreRows = footer.options.contains { !$0.detail.isEmpty }
    optionButtons = footer.options.map { item in
      let button = PromptButton(
        title: item.title, style: item.style, detail: optionsAreRows ? item.detail : nil)
      button.setMark(checked: item.mark)
      button.hint = item.hint
      button.onClick = activating(button, item.action)
      addSubview(button)
      return button
    }
    buttonRows = footer.rows.map { row in
      row.map { item in
        let button = PromptButton(title: item.title, style: item.style)
        button.isEnabled = item.isEnabled
        button.hint = item.hint
        button.onClick = activating(button, item.action)
        addSubview(button)
        return button
      }
    }
    headerLink?.removeFromSuperview()
    headerLink = nil
    if let link = headerLink(for: event) {
      let button = PromptButton(title: link.title, style: .link)
      button.onClick = activating(button, link.action)
      addSubview(button)
      headerLink = button
    }
    let wasShowingInput = showsInput
    showsInput = footer.input != nil
    inputBox.isHidden = !showsInput
    inputButton.isHidden = !showsInput || isReplyMode
    sendIconButton.isHidden = !(showsInput && isReplyMode)
    sendIconButton.isEnabled = !inputField.stringValue
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    closeButton.isHidden = !(showsInput && footer.closesInput)
    if let input = footer.input {
      inputField.placeholderAttributedString = NSAttributedString(
        string: input.placeholder,
        attributes: [
          .font: NSFont.systemFont(ofSize: 13),
          .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ])
      inputButton.setTitle(input.send)
      if !wasShowingInput { focusInputSoon() }
    }
    // « Answer in Claude Code » est dit dans l'en-tête, plus au pied de la carte.
    hintLabel.isHidden = true
    needsLayout = true
  }

  private func focusInputSoon() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.showsInput else { return }
      self.window?.makeFirstResponder(self.inputField)
    }
  }

  // MARK: - Réponses

  /// Le bouton qui vient d'être actionné : il se coche un instant quand la réponse part.
  private weak var lastActivated: PromptButton?

  private func send(_ event: AgentEvent, _ decision: AgentEvent.Decision) {
    lastActivated?.showAnswered()
    onDecision?(event, decision)
  }

  /// Retient le bouton avant de lancer son action.
  private func activating(_ button: PromptButton?, _ action: @escaping () -> Void) -> () -> Void {
    { [weak self, weak button] in
      self?.lastActivated = button
      action()
    }
  }

  /// Question suivante : l'ancienne s'efface pendant que la nouvelle entre.
  private func refreshForm() {
    guard let event else { return }
    swapContent {
      inputField.stringValue = ""
      applyContent(event)
    }
  }

  /// Applique `change` en montrant l'ancien contenu s'effacer (instantané du calque, 0,15 s) pendant
  /// que le nouveau entre en fondu, légèrement grossi. Sans mouvement ou hors écran : `change` seul.
  private func swapContent(_ change: () -> Void) {
    guard OverlayAnimation.allowsMotion, let layer, window != nil, !isHiddenOrHasHiddenAncestor,
      bounds.width > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds)
    else {
      change()
      return
    }
    cacheDisplay(in: bounds, to: rep)
    change()
    layoutSubtreeIfNeeded()
    if let image = rep.cgImage {
      let snapshot = CALayer()
      snapshot.frame = bounds
      snapshot.contents = image
      snapshot.contentsScale = window?.backingScaleFactor ?? 2
      snapshot.zPosition = 100
      layer.addSublayer(snapshot)
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 1
      fade.toValue = 0
      fade.duration = 0.15
      fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
      fade.fillMode = .forwards
      fade.isRemovedOnCompletion = false
      CATransaction.begin()
      CATransaction.setCompletionBlock { snapshot.removeFromSuperlayer() }
      snapshot.add(fade, forKey: "fadeOut")
      CATransaction.commit()
    }
    for view in subviews { view.layer?.crossfadeIn() }
  }

  /// Ce qui apparaît dans la même carte (champ « Other… », choix de retour) glisse de 6 pt en
  /// montant et se fond.
  private func phaseIn(_ views: [NSView]) {
    for view in views where !view.isHidden { view.layer?.springReveal(y: -6) }
  }

  private func finish(with outcome: AgentPromptForm.Outcome) {
    switch outcome {
    case .stay: break
    case .advanced: refreshForm()
    case .finished(let answers):
      guard let event else { return }
      send(event, .answer(answers))
    }
  }

  private func choose(_ label: String) {
    guard var updated = form else { return }
    let outcome = updated.choose(label)
    form = updated
    if outcome == .stay, let event { apply(event) } else { finish(with: outcome) }
  }

  private func sendChoices() {
    guard var updated = form else { return }
    let outcome = updated.sendChoices()
    form = updated
    finish(with: outcome)
  }

  private func startTyping() {
    guard var updated = form else { return }
    updated.startTyping()
    form = updated
    if let event {
      apply(event)
      layoutSubtreeIfNeeded()
      phaseIn([inputBox, inputButton, closeButton])
    }
  }

  private func stopTyping() {
    guard var updated = form else { return }
    updated.stopTyping()
    form = updated
    if let event {
      apply(event)
      layoutSubtreeIfNeeded()
      phaseIn(optionButtons + buttons)
    }
  }

  /// Entrée dans le champ, ou son bouton : une réponse libre, ou le texte d'une question.
  @objc private func submitInput() {
    guard let event else { return }
    if lastActivated == nil || lastActivated?.superview == nil { lastActivated = activeSendButton }
    let text = inputField.stringValue
    if case .reply = event.prompt {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      send(event, .reply(trimmed))
      return
    }
    guard var updated = form else { return }
    guard updated.isValid(text) else {
      flagInvalidInput()
      return
    }
    let outcome = updated.submit(text: text)
    form = updated
    finish(with: outcome)
  }

  /// Le texte n'a pas le type du champ (un nombre attendu) : le contour rougit jusqu'à la frappe suivante.
  private func flagInvalidInput() {
    inputBox.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
  }

  // MARK: - Clavier

  /// Les touches de la carte, quand elle est dans la fenêtre clé : `1`–`4` choisissent, les flèches et
  /// Tab déplacent le focus, Entrée valide le choix au focus ou l'envoi d'un choix multiple, Échap
  /// referme « Other… » puis replie le panneau. Entrée n'autorise jamais un outil.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isAnswerable, !isHiddenOrHasHiddenAncestor,
      event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    else { return super.performKeyEquivalent(with: event) }
    let editing = inputField.currentEditor().map { window?.firstResponder === $0 } ?? false

    switch event.keyCode {
    case 53:  // Échap
      if showsInput, !closeButton.isHidden {
        stopTyping()
      } else {
        onFoldRequested?()
      }
      return true
    case 36, 76:  // Entrée
      if showsInput {
        if editing { return super.performKeyEquivalent(with: event) }
        window?.makeFirstResponder(inputField)
        return true
      }
      if let index = focusedOption, optionButtons.indices.contains(index) {
        optionButtons[index].activate()
        return true
      }
      if form != nil, let primary = buttons.first(where: { $0.isPrimary && $0.isEnabled }) {
        primary.activate()
        return true
      }
      return super.performKeyEquivalent(with: event)
    case 48, 125, 124, 126, 123:  // Tab, flèches
      guard !showsInput, !optionButtons.isEmpty else { return super.performKeyEquivalent(with: event) }
      let backwards = event.keyCode == 126 || event.keyCode == 123
        || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
      moveFocus(by: backwards ? -1 : 1)
      return true
    case 49:  // Espace
      guard !showsInput, let index = focusedOption, optionButtons.indices.contains(index) else {
        return super.performKeyEquivalent(with: event)
      }
      optionButtons[index].activate()
      return true
    default:
      guard !showsInput, let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
        (1...4).contains(digit), optionButtons.indices.contains(digit - 1)
      else { return super.performKeyEquivalent(with: event) }
      optionButtons[digit - 1].activate()
      return true
    }
  }

  private func moveFocus(by delta: Int) {
    let count = optionButtons.count
    guard let current = focusedOption else {
      focusedOption = delta > 0 ? 0 : count - 1
      return
    }
    focusedOption = (current + delta + count) % count
  }

  /// Une rangée de commandes à leur taille, calées à gauche ; si elle déborde, largeurs égales.
  private func placeRow(_ row: [PromptButton], y: CGFloat, contentWidth: CGFloat) {
    let gap: CGFloat = 8
    let natural = row.map(\.fittingWidth)
    let fits = natural.reduce(0, +) + gap * CGFloat(max(row.count - 1, 0)) <= contentWidth
    let equal = (contentWidth - gap * CGFloat(row.count - 1)) / CGFloat(max(row.count, 1))
    var x = inset
    for (index, button) in row.enumerated() {
      let width = fits ? natural[index] : equal
      button.frame = NSRect(x: x, y: y, width: width, height: buttonHeight)
      x += width + gap
    }
  }

  /// Une question : son texte sans boîte, puis les choix (ou le champ « Other… » à leur place),
  /// puis les commandes en bas.
  private func layoutQuestion(top: CGFloat) {
    let contentWidth = bounds.width - 2 * inset
    hintLabel.frame = .zero
    // Texte de la question, deux lignes au plus.
    bodyLabel.preferredMaxLayoutWidth = contentWidth
    let fitting = bodyLabel.cell?.cellSize(
      forBounds: NSRect(x: 0, y: 0, width: contentWidth, height: 10_000)).height ?? 0
    let textHeight = min(ceil(fitting), 40)
    let textTop = top - 28
    bodyBox.frame = NSRect(
      x: inset, y: textTop - textHeight, width: contentWidth, height: textHeight)
    bodyLabel.frame = bodyBox.bounds

    // Commandes, du bas vers le haut.
    var floor: CGFloat = 12
    for row in buttonRows.reversed() {
      placeRow(row, y: floor, contentWidth: contentWidth)
      floor += buttonHeight + 8
    }
    let areaTop = textTop - textHeight - 8
    let gap: CGFloat = 6

    if showsInput {
      let y = areaTop - buttonHeight
      let sendWidth = max(inputButton.fittingWidth, 76)
      inputButton.frame = NSRect(
        x: inset + contentWidth - sendWidth, y: y, width: sendWidth, height: buttonHeight)
      var fieldRight = inputButton.frame.minX - 8
      if !closeButton.isHidden {
        let width = closeButton.fittingWidth
        closeButton.frame = NSRect(x: fieldRight - width, y: y, width: width, height: buttonHeight)
        fieldRight = closeButton.frame.minX - 6
      }
      inputBox.frame = NSRect(x: inset, y: y, width: fieldRight - inset, height: buttonHeight)
      inputField.frame = inputBox.bounds.insetBy(dx: 12, dy: (buttonHeight - 18) / 2)
      return
    }

    let count = optionButtons.count
    guard count > 0 else { return }
    if optionsAreRows {
      let available = areaTop - floor + 2
      let height = min(28, max(20, (available - gap * CGFloat(count - 1)) / CGFloat(count)))
      for (index, button) in optionButtons.enumerated() {
        button.frame = NSRect(
          x: inset, y: areaTop - height - CGFloat(index) * (height + gap), width: contentWidth,
          height: height)
      }
    } else {
      var x = inset
      var y = areaTop - 28
      for button in optionButtons {
        let width = min(button.fittingWidth, contentWidth)
        if x > inset, x + width > inset + contentWidth {
          x = inset
          y -= 28 + gap
        }
        button.frame = NSRect(x: x, y: y, width: width, height: 28)
        x += width + gap
      }
    }
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    washLayer.frame = bounds
    CATransaction.commit()
    let top = bounds.maxY - 14
    dotView.frame = NSRect(x: inset, y: top - 16 + 5, width: 8, height: 8)
    projectLabel.sizeToFit()
    let nameWidth = min(projectLabel.frame.width, bounds.width * 0.4)
    projectLabel.frame = NSRect(
      x: dotView.frame.maxX + 8, y: top - 18, width: nameWidth, height: 18)
    var rightEdge = bounds.width - inset
    if let link = headerLink {
      let width = link.fittingWidth
      link.frame = NSRect(x: rightEdge - width, y: top - 17, width: width, height: 16)
      rightEdge = link.frame.minX - 10
    }
    if !stepDots.isHidden {
      let width = stepDots.fittingWidth
      stepDots.frame = NSRect(x: rightEdge - width, y: top - 11, width: width, height: 4)
      rightEdge = stepDots.frame.minX - 10
    }
    let kindWidth =
      kindLabel.stringValue.isEmpty
      ? 0 : min(kindLabel.intrinsicContentSize.width + 8, bounds.width * 0.4)
    kindLabel.frame = NSRect(x: rightEdge - kindWidth, y: top - 17, width: kindWidth, height: 16)
    let verbX = projectLabel.frame.maxX + 8
    verbLabel.frame = NSRect(
      x: verbX, y: top - 17, width: max(0, kindLabel.frame.minX - 8 - verbX), height: 16)

    if form != nil {
      layoutQuestion(top: top)
      return
    }
    let boxTop = top - 26
    let rowCount = buttonRows.count + (showsInput ? 1 : 0)
    let rowGap: CGFloat = 8
    let footerHeight: CGFloat = rowCount == 0 ? 0 : CGFloat(rowCount) * (buttonHeight + rowGap) + 2
    let boxBottom = 12 + footerHeight
    bodyBox.frame = NSRect(
      x: inset, y: boxBottom, width: bounds.width - 2 * inset, height: max(0, boxTop - boxBottom))
    hintLabel.frame = NSRect(x: inset, y: 12, width: bounds.width - 2 * inset, height: 14)

    // De haut en bas : le champ de texte, puis les rangées de boutons.
    let contentWidth = bounds.width - 2 * inset
    var slot = rowCount - 1
    func rowY() -> CGFloat { 12 + CGFloat(slot) * (buttonHeight + rowGap) }
    if showsInput {
      let y = rowY()
      if isReplyMode {
        // Champ sur toute la largeur, avec le rond d'envoi à l'intérieur, à droite.
        let icon: CGFloat = 24
        inputBox.frame = NSRect(x: inset, y: y, width: contentWidth, height: buttonHeight)
        sendIconButton.frame = NSRect(
          x: inputBox.frame.maxX - 3 - icon, y: y + (buttonHeight - icon) / 2, width: icon,
          height: icon)
        inputField.frame = NSRect(
          x: 12, y: (buttonHeight - 18) / 2, width: contentWidth - 12 - icon - 10, height: 18)
      } else {
        let sendWidth: CGFloat = 76
        inputButton.frame = NSRect(
          x: inset + contentWidth - sendWidth, y: y, width: sendWidth, height: buttonHeight)
        inputBox.frame = NSRect(
          x: inset, y: y, width: contentWidth - sendWidth - 8, height: buttonHeight)
        inputField.frame = inputBox.bounds.insetBy(dx: 12, dy: (buttonHeight - 18) / 2)
      }
      slot -= 1
    }
    for row in buttonRows {
      placeRow(row, y: rowY(), contentWidth: contentWidth)
      slot -= 1
    }
    bodyLabel.preferredMaxLayoutWidth = bodyBox.bounds.width - 20
    // Texte calé en haut de la boîte, pas centré : une courte commande ne flotte pas au milieu.
    let textWidth = bodyBox.bounds.width - 20
    let fitting = bodyLabel.cell?.cellSize(
      forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 10_000)).height ?? 0
    let textHeight = min(fitting, max(0, bodyBox.bounds.height - 16))
    bodyLabel.frame = NSRect(
      x: 10, y: bodyBox.bounds.height - 8 - textHeight, width: textWidth, height: textHeight)
  }
}

/// Bouton de la carte. Un seul `.primary` par carte (la réponse attendue) ; le reste se tait.
final class PromptButton: NSView {

  enum Style {
    /// Fond clair, texte sombre : la réponse attendue.
    case primary
    /// Gris discret.
    case secondary
    /// Choix coché d'une question : teinte turquoise.
    case selected
    /// Refus d'un formulaire.
    case decline
    /// Texte souligné, sans fond : actions de repli.
    case link
  }

  var onClick: (() -> Void)?

  func activate() { if isEnabled { onClick?() } }

  private var isAnswered = false

  /// Réponse donnée : le bouton se coche et verdit un instant, pendant que la carte se retire.
  func showAnswered() {
    guard style != .link, !isAnswered else { return }
    isAnswered = true
    hintView?.isHidden = true
    label.stringValue = isRow ? "✓ \(label.stringValue)" : "✓"
    label.textColor = NSColor(calibratedWhite: 0.06, alpha: 1)
    updateBackground()
    if OverlayAnimation.allowsMotion {
      let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
      pulse.values = [1, 1.06, 1]
      pulse.keyTimes = [0, 0.4, 1]
      pulse.duration = 0.22
      layer?.add(pulse, forKey: "answered")
    }
  }
  var isPrimary: Bool { style == .primary }

  /// Touche qui déclenche le bouton, en pastille à droite (« 1 », « ↩ »).
  var hint: String? {
    didSet {
      guard hint != oldValue else { return }
      if let hint {
        let chip = hintView ?? NSTextField(labelWithString: "")
        if hintView == nil {
          chip.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
          chip.alignment = .center
          chip.wantsLayer = true
          chip.layer?.cornerRadius = 4
          chip.layer?.borderWidth = 1
          addSubview(chip)
          hintView = chip
        }
        chip.stringValue = hint
        let dark = style == .primary
        chip.textColor = dark ? NSColor.black.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(0.5)
        chip.layer?.borderColor =
          (dark ? NSColor.black.withAlphaComponent(0.25) : NSColor.white.withAlphaComponent(0.2)).cgColor
      } else {
        hintView?.removeFromSuperview()
        hintView = nil
      }
      needsLayout = true
    }
  }
  private var hintView: NSTextField?
  private var hintWidth: CGFloat { hintView.map { ceil($0.intrinsicContentSize.width) + 8 } ?? 0 }

  /// Focus clavier (flèches, Tab) : un contour clair.
  var isKeyFocused = false { didSet { updateBackground() } }
  /// Grisé et sans effet (« Send » d'un choix multiple vide).
  var isEnabled = true { didSet { updateBackground() } }

  fileprivate let style: Style
  private let label: NSTextField
  /// Description d'un choix en ligne ; `nil` pour un bouton ou une pastille.
  private let detailLabel: NSTextField?
  private var checkView: NSImageView?
  private var isRow: Bool { detailLabel != nil }
  private var isHovered = false { didSet { updateBackground() } }

  /// Largeur du bouton à sa taille : le titre et un peu d'air (rien pour un lien).
  var fittingWidth: CGFloat {
    ceil(label.intrinsicContentSize.width) + (style == .link ? 8 : 28)
      + (checkView == nil ? 0 : 18) + (hintView == nil ? 0 : hintWidth + 6)
  }

  /// Symbole SF affiché à la place du titre (bouton rond) ; le titre reste le nom du bouton.
  private var iconView: NSImageView?

  init(title: String, style: Style, detail: String? = nil, icon: String? = nil) {
    self.style = style
    label = NSTextField(labelWithString: title)
    detailLabel = detail.map { NSTextField(labelWithString: $0) }
    super.init(frame: .zero)
    wantsLayer = true
    label.font = .systemFont(
      ofSize: style == .link ? 11 : (detail == nil ? 13 : 12),
      weight: style == .link ? .regular : .semibold)
    switch style {
    case .primary: label.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
    case .secondary: label.textColor = NSColor.white.withAlphaComponent(0.9)
    case .selected: label.textColor = NSColor.systemTeal.blended(withFraction: 0.5, of: .white)
    case .decline: label.textColor = NSColor(calibratedRed: 1, green: 0.62, blue: 0.64, alpha: 1)
    case .link: label.textColor = NSColor.white.withAlphaComponent(0.55)
    }
    if let icon {
      let view = NSImageView()
      let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
      view.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
        .withSymbolConfiguration(configuration)
      view.contentTintColor = NSColor(calibratedWhite: 0.08, alpha: 1)
      addSubview(view)
      iconView = view
      label.isHidden = true
    }
    label.alignment = style == .link ? .right : (detail == nil ? .center : .left)
    label.lineBreakMode = .byTruncatingTail
    toolTip = title
    addSubview(label)
    if let detailLabel {
      detailLabel.font = .systemFont(ofSize: 11)
      detailLabel.textColor = NSColor.white.withAlphaComponent(0.5)
      detailLabel.lineBreakMode = .byTruncatingTail
      addSubview(detailLabel)
      toolTip = detail?.isEmpty == false ? "\(title) — \(detail ?? "")" : title
    }
    updateBackground()
  }

  /// Case d'un choix multiple, cochée ou non ; `nil` l'enlève.
  func setMark(checked: Bool?) {
    guard let checked else {
      checkView?.removeFromSuperview()
      checkView = nil
      return
    }
    let view = checkView ?? NSImageView()
    if checkView == nil {
      addSubview(view)
      checkView = view
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    view.image = NSImage(
      systemSymbolName: checked ? "checkmark.square.fill" : "square", accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration)
    view.contentTintColor =
      checked ? NSColor.systemTeal : NSColor.white.withAlphaComponent(0.45)
    needsLayout = true
  }

  func setTitle(_ title: String) {
    label.stringValue = title
    toolTip = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = isRow ? 8 : bounds.height / 2
    if let iconView {
      iconView.frame = bounds.insetBy(dx: 5, dy: 5)
      return
    }
    let height = label.intrinsicContentSize.height
    var x: CGFloat = style == .link ? 0 : (isRow ? 10 : 8)
    if let checkView {
      checkView.frame = NSRect(x: 10, y: (bounds.height - 14) / 2, width: 14, height: 14)
      x = isRow ? 30 : 28
    }
    var trailing: CGFloat = style == .link ? 0 : (isRow ? 10 : 8)
    if let hintView {
      let width = hintWidth
      hintView.frame = NSRect(
        x: bounds.width - trailing - width, y: (bounds.height - 16) / 2, width: width, height: 16)
      trailing += width + 6
    }
    if let detailLabel {
      // Titre à son aplomb, description qui prend le reste de la ligne.
      let width = min(ceil(label.intrinsicContentSize.width) + 4, max(0, bounds.width - x - trailing))
      label.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
      let detailHeight = detailLabel.intrinsicContentSize.height
      let detailX = label.frame.maxX + 8
      detailLabel.frame = NSRect(
        x: detailX, y: (bounds.height - detailHeight) / 2,
        width: max(0, bounds.width - detailX - trailing), height: detailHeight)
    } else {
      label.frame = NSRect(
        x: x, y: (bounds.height - height) / 2, width: max(0, bounds.width - x - trailing),
        height: height)
    }
  }

  private func updateBackground() {
    let base: NSColor
    switch style {
    case .primary: base = NSColor(calibratedWhite: 0.94, alpha: 1)
    case .secondary: base = NSColor.white.withAlphaComponent(isRow ? 0.07 : 0.10)
    case .selected: base = NSColor.systemTeal.withAlphaComponent(0.22)
    case .decline: base = NSColor(calibratedRed: 0.26, green: 0.12, blue: 0.11, alpha: 1)
    case .link: base = .clear
    }
    let shade = isHovered && isEnabled && style != .link ? base.withAlphaComponent(0.8) : base
    layer?.backgroundColor =
      (isAnswered ? NSColor.systemGreen.withAlphaComponent(0.9) : shade).cgColor
    let outlined = style == .selected || isRow || isKeyFocused
    layer?.borderWidth = isKeyFocused ? 1.5 : (outlined ? 1 : 0)
    layer?.borderColor =
      (isKeyFocused
        ? NSColor.white.withAlphaComponent(0.7)
        : style == .selected
          ? NSColor.systemTeal.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.08))
      .cgColor
    if style == .link {
      label.textColor = NSColor.white.withAlphaComponent(isHovered ? 0.9 : 0.55)
    }
    alphaValue = isEnabled ? 1 : 0.4
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    )
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true }
  override func mouseExited(with event: NSEvent) { isHovered = false }
  override func mouseDown(with event: NSEvent) { if isEnabled { onClick?() } }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Un segment par question d'un formulaire, rempli jusqu'à la question courante.
private final class StepDots: NSView {

  private var count = 0
  private var index = 0
  private let segmentWidth: CGFloat = 12
  private let gap: CGFloat = 3

  var fittingWidth: CGFloat {
    CGFloat(count) * segmentWidth + CGFloat(max(count - 1, 0)) * gap
  }

  func set(count: Int, index: Int) {
    self.count = count
    self.index = index
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    for step in 0..<count {
      let rect = NSRect(
        x: CGFloat(step) * (segmentWidth + gap), y: 0, width: segmentWidth, height: bounds.height)
      let alpha: CGFloat = step <= index ? 0.85 : 0.2
      NSColor.white.withAlphaComponent(alpha).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension AgentPromptCardView: NSTextFieldDelegate {
  /// Une frappe rend au contour sa couleur de repos.
  func controlTextDidChange(_ notification: Notification) {
    inputBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    // Le rond d'envoi ne s'allume que s'il y a un texte à envoyer.
    sendIconButton.isEnabled = !inputField.stringValue
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
