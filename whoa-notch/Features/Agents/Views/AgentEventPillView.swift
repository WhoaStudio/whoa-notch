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

  /// Compte à rebours avant que la demande soit rendue à l'agent : un anneau autour de la pastille.
  private let ringLayer = CAShapeLayer()
  private var ringTask: Task<Void, Never>?
  /// Les dernières secondes montrées par l'anneau.
  private static let ringWindow: TimeInterval = 30

  /// Le vert de l'état « terminé » : icône, texte, et dégradé de fond. Défini une seule fois.
  /// `systemGreen` s'adapte au mode clair/sombre (l'app force `.darkAqua`).
  static let doneTint: NSColor = .systemGreen

  /// Dégradé horizontal du fond : transparent au milieu, vert au bord droit. Visible seulement
  /// pour l'état « terminé ».
  private let backgroundGradient = CAGradientLayer()

  private static let dotSize: CGFloat = 8
  private let inset: CGFloat = NotchPanelGeometry.wingEdgeInset
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

    backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
    backgroundGradient.endPoint = CGPoint(x: 1, y: 0.5)
    backgroundGradient.colors = [
      NSColor.clear.cgColor, Self.doneTint.withAlphaComponent(0.25).cgColor,
    ]
    backgroundGradient.isHidden = true
    layer?.insertSublayer(backgroundGradient, at: 0)

    ringLayer.fillColor = nil
    ringLayer.lineWidth = 1.5
    ringLayer.lineCap = .round
    ringLayer.isHidden = true
    layer?.addSublayer(ringLayer)

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

  /// Ce que dit l'aile droite et sa teinte : ce qui est demandé, puis `+N` pour les demandes qui
  /// attendent derrière.
  static func status(for event: AgentEvent, queued: Int) -> (text: String, tint: NSColor) {
    var text: String
    let tint: NSColor
    switch event.prompt {
    case .tool:
      text = event.replyID != nil ? "Allow?" : "Permission"
      tint = .systemOrange
    case .plan:
      text = "Plan ready"
      tint = .systemOrange
    case .questions(let questions):
      if event.response == .elicitation {
        text = "Form"
      } else {
        text = questions.count > 1 ? "\(questions.count) questions" : "Question"
      }
      tint = .systemTeal
    case .reply, .message, nil:
      text = event.kind.statusText
      tint = event.kind == .needsInput ? .systemOrange : Self.doneTint
    }
    if queued > 0 { text += " +\(queued)" }
    return (text, tint)
  }

  /// `queued` : les demandes qui attendent derrière celle-ci. `deadline` : quand elle sera rendue à
  /// l'agent faute de réponse — l'anneau de la pastille se vide sur les 30 dernières secondes.
  func apply(_ event: AgentEvent, notchWidth: CGFloat, queued: Int = 0, deadline: Date? = nil) {
    let status = Self.status(for: event, queued: queued)
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
      iconView.contentTintColor = status.tint
    }
    dotView.isHidden = event.prompt == nil
    dotView.layer?.backgroundColor = status.tint.cgColor
    // Dégradé vert seulement pour un état « terminé » (sans demande, ni attente).
    backgroundGradient.isHidden = event.prompt != nil || event.kind == .needsInput
    projectLabel.stringValue = event.project
    statusLabel.stringValue = status.text
    statusLabel.textColor = status.tint
    self.notchWidth = notchWidth
    startCountdown(until: event.prompt == nil ? nil : deadline, tint: status.tint)
    needsLayout = true
  }

  // MARK: - Compte à rebours

  private func startCountdown(until deadline: Date?, tint: NSColor) {
    ringTask?.cancel()
    ringTask = nil
    ringLayer.removeAllAnimations()
    ringLayer.isHidden = true
    guard let deadline, deadline.timeIntervalSinceNow > 0 else { return }
    ringLayer.strokeColor = tint.cgColor
    let lead = deadline.timeIntervalSinceNow - Self.ringWindow
    if lead <= 0 {
      runRing(until: deadline)
      return
    }
    // Trop tôt pour l'anneau : on l'allume quand il ne reste plus que 30 s.
    ringTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(lead))
      guard !Task.isCancelled else { return }
      self?.runRing(until: deadline)
    }
  }

  private func runRing(until deadline: Date) {
    let remaining = deadline.timeIntervalSinceNow
    guard remaining > 0 else { return }
    let fraction = min(1, remaining / Self.ringWindow)
    ringLayer.isHidden = false
    ringLayer.strokeEnd = 0
    guard OverlayAnimation.allowsMotion else {
      // Sans mouvement : l'anneau reste à sa part restante, sans se vider.
      ringLayer.strokeEnd = CGFloat(fraction)
      return
    }
    let drain = CABasicAnimation(keyPath: "strokeEnd")
    drain.fromValue = fraction
    drain.toValue = 0
    drain.duration = remaining
    drain.timingFunction = CAMediaTimingFunction(name: .linear)
    ringLayer.add(drain, forKey: "drain")
  }

  override func layout() {
    super.layout()
    let wing = Self.wingWidth
    iconView.frame = NSRect(
      x: inset, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

    dotView.frame = NSRect(
      x: iconView.frame.maxX - Self.dotSize + 3, y: iconView.frame.maxY - Self.dotSize + 3,
      width: Self.dotSize, height: Self.dotSize)

    // Anneau autour de la pastille, qui part du haut et tourne dans le sens des aiguilles.
    let ringFrame = dotView.frame.insetBy(dx: -3.5, dy: -3.5)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ringLayer.frame = ringFrame
    let path = CGMutablePath()
    path.addArc(
      center: CGPoint(x: ringFrame.width / 2, y: ringFrame.height / 2),
      radius: ringFrame.width / 2 - 0.75, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi,
      clockwise: true)
    ringLayer.path = path
    CATransaction.commit()

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backgroundGradient.frame = bounds
    CATransaction.commit()

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
