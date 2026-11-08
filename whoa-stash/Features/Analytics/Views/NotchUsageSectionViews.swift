import AppKit

/// Carte du fournisseur choisi : marque et nom à gauche ; à droite le titre « 7D 47% remaining »,
/// l'instant de réinitialisation, la barre de progression et une ligne dessous.
final class NotchUsageCardView: NSView {

  static let height: CGFloat = 86

  private static let barGreen = NSColor(srgbRed: 0.62, green: 0.84, blue: 0.64, alpha: 1)

  private static let resetFormatter: DateFormatter = {
    let formatter = DateFormatter()
    // « Thu 9:00 AM » ; le gabarit laisse les locales 24 h afficher « jeu. 09:00 ».
    formatter.setLocalizedDateFormatFromTemplate("EEE jmm")
    return formatter
  }()

  private let markView = NotchUsageMarkView()
  private let nameLabel = NSTextField(labelWithString: "")
  private let titleLabel = NSTextField(labelWithString: "")
  private let resetLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")
  /// Relance Claude Code quand la session a expiré ; caché dans tous les autres états.
  private let reauthButton = NSButton(title: "Reconnect", target: nil, action: nil)
  private let trackLayer = CALayer()
  private let fillLayer = CALayer()
  private var remaining: Double = 0
  private var provider: NotchUsageProvider = .claude

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

    nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
    titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
    resetLabel.font = .systemFont(ofSize: 12, weight: .regular)
    detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
    nameLabel.textColor = .white
    titleLabel.textColor = .white
    resetLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    detailLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    resetLabel.alignment = .right

    trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    fillLayer.backgroundColor = Self.barGreen.cgColor
    layer?.addSublayer(trackLayer)
    layer?.addSublayer(fillLayer)

    reauthButton.bezelStyle = .rounded
    reauthButton.controlSize = .small
    reauthButton.target = self
    reauthButton.action = #selector(reauth)
    reauthButton.isHidden = true

    [markView, nameLabel, titleLabel, resetLabel, detailLabel, reauthButton].forEach(addSubview)
  }

  @objc private func reauth() {
    AgentLoginLauncher.open(command: provider.loginCommand)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ reading: NotchUsageReading, provider: NotchUsageProvider) {
    self.provider = provider
    markView.mark = provider.mark
    markView.color = .white
    nameLabel.stringValue = provider.name
    reauthButton.isHidden = !reading.needsReauth
    titleLabel.lineBreakMode = .byTruncatingTail

    let bold = NSFont.systemFont(ofSize: 14, weight: .semibold)
    let regular = NSFont.systemFont(ofSize: 14, weight: .regular)

    switch reading.status {
    case .loaded:
      let percentage = reading.remainingPercentage ?? 0
      let title = NSMutableAttributedString(
        string: reading.windowLabel + "  ",
        attributes: [.font: bold, .foregroundColor: NSColor.white])
      title.append(
        NSAttributedString(
          string: "\(percentage)% remaining",
          attributes: [.font: regular, .foregroundColor: NSColor.white]))
      titleLabel.attributedStringValue = title
      resetLabel.stringValue = reading.resetsAt.map(Self.resetFormatter.string(from:)) ?? ""
      // TODO: « N resets available » — aucune source ne fournit ce compte ; la ligne ne
      // montre que ce qu'un instantané porte vraiment (Claude : le quota hebdomadaire).
      detailLabel.stringValue = reading.secondaryLine ?? ""
      remaining = reading.remaining ?? 0
    case .loading:
      titleLabel.stringValue = "Loading…"
      resetLabel.stringValue = ""
      detailLabel.stringValue = ""
      remaining = 0
    case .unavailable(let reason):
      // La raison complète va dans l'info-bulle : le titre tronque, la carte reste étroite.
      titleLabel.stringValue = reading.needsReauth ? "Session expired" : reason
      titleLabel.toolTip = reason
      resetLabel.stringValue = ""
      detailLabel.stringValue = reading.needsReauth ? "Sign in again to \(provider.name)" : ""
      remaining = 0
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let inset: CGFloat = 20
    let markSize: CGFloat = 26
    let columnX = (bounds.width * 0.36).rounded()
    let right = bounds.width - inset

    markView.frame = NSRect(
      x: inset, y: (bounds.height - markSize) / 2, width: markSize, height: markSize)
    let name = nameLabel.intrinsicContentSize
    nameLabel.frame = NSRect(
      x: markView.frame.maxX + 12, y: (bounds.height - name.height) / 2,
      width: min(ceil(name.width), columnX - markView.frame.maxX - 16), height: name.height)

    let barHeight: CGFloat = 6
    let barY = (bounds.height - barHeight) / 2
    let title = titleLabel.intrinsicContentSize
    let detail = detailLabel.intrinsicContentSize

    resetLabel.sizeToFit()
    let resetWidth = ceil(resetLabel.frame.width)
    resetLabel.frame = NSRect(
      x: right - resetWidth, y: barY + 11 + (title.height - resetLabel.frame.height) / 2,
      width: resetWidth, height: resetLabel.frame.height)
    titleLabel.frame = NSRect(
      x: columnX, y: barY + 11, width: max(0, resetLabel.frame.minX - columnX - 8),
      height: title.height)
    detailLabel.frame = NSRect(
      x: columnX, y: barY - 9 - detail.height, width: right - columnX, height: detail.height)

    reauthButton.sizeToFit()
    reauthButton.frame.origin = NSPoint(
      x: right - reauthButton.frame.width,
      y: barY + 11 + (title.height - reauthButton.frame.height) / 2)
    if reauthButton.frame.width > 0, !reauthButton.isHidden {
      titleLabel.frame.size.width = max(0, reauthButton.frame.minX - columnX - 8)
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let track = NSRect(x: columnX, y: barY, width: right - columnX, height: barHeight)
    trackLayer.frame = track
    trackLayer.cornerRadius = barHeight / 2
    fillLayer.frame = NSRect(
      x: track.minX, y: track.minY, width: track.width * CGFloat(min(1, max(0, remaining))),
      height: barHeight)
    fillLayer.cornerRadius = barHeight / 2
    CATransaction.commit()
  }
}

/// Pastille de filtre (« Month », « All models »…) : libellé et chevron. Un clic ouvre le menu
/// que construit `makeMenu`.
final class NotchUsageFilterPillView: NSView {

  /// Construit le menu à chaque clic : ses entrées dépendent des requêtes déjà lues.
  var makeMenu: (() -> NSMenu)?
  var onTitleChanged: (() -> Void)?

  var title: String {
    get { label.stringValue }
    set {
      guard newValue != label.stringValue else { return }
      label.stringValue = newValue
      needsLayout = true
      onTitleChanged?()
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard let menu = makeMenu?() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
  }

  static let height: CGFloat = 30

  private let label = NSTextField(labelWithString: "")
  private let chevron = NSImageView()

  init(title: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
    label.stringValue = title
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = NSColor.white.withAlphaComponent(0.92)
    label.lineBreakMode = .byClipping
    let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
    chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    chevron.contentTintColor = NSColor.white.withAlphaComponent(0.7)
    addSubview(label)
    addSubview(chevron)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var fittingWidth: CGFloat { 12 + labelWidth + 8 + 10 + 11 }

  /// Largeur du libellé en entier : le titre ne se tronque jamais, c'est la pastille qui s'étire.
  private var labelWidth: CGFloat {
    ceil(max(label.intrinsicContentSize.width, label.attributedStringValue.size().width)) + 2
  }

  override func layout() {
    super.layout()
    let size = label.intrinsicContentSize
    label.frame = NSRect(
      x: 12, y: (bounds.height - size.height) / 2, width: labelWidth, height: size.height)
    chevron.frame = NSRect(
      x: label.frame.maxX + 8, y: (bounds.height - 10) / 2, width: 10, height: 10)
  }
}

/// Section « Activity » : le mois choisi et quatre mesures tirées des journaux des agents.
final class NotchUsageActivityView: NSView {

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
    return formatter
  }()

  private let titleLabel = NSTextField(labelWithString: "Activity")
  private let periodLabel = NSTextField(labelWithString: "")
  private let metrics: [(value: NSTextField, caption: NSTextField)]

  override init(frame frameRect: NSRect) {
    let captions = ["Tokens", "Cost", "Forecast", "Active days"]
    metrics = captions.map { caption in
      let value = NSTextField(labelWithString: "…")
      value.font = .systemFont(ofSize: 21, weight: .regular)
      value.textColor = .white
      let label = NSTextField(labelWithString: caption)
      label.font = .systemFont(ofSize: 13, weight: .regular)
      label.textColor = NSColor.white.withAlphaComponent(0.85)
      return (value, label)
    }
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 20
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

    titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
    titleLabel.textColor = .white
    periodLabel.font = .systemFont(ofSize: 13, weight: .regular)
    periodLabel.textColor = NSColor.white.withAlphaComponent(0.85)
    periodLabel.stringValue = Self.monthFormatter.string(from: Date())
    addSubview(titleLabel)
    addSubview(periodLabel)
    for (value, caption) in metrics {
      addSubview(value)
      addSubview(caption)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Le mois peut changer pendant que le panneau reste en mémoire : relu à chaque dépliage.
  func refreshPeriod() {
    periodLabel.stringValue = Self.monthFormatter.string(from: Date())
    needsLayout = true
  }

  /// Montre les mesures du mois `period`. `summary` à `nil` : journaux en cours de lecture.
  func apply(summary: ActivitySummary?, period: Date) {
    periodLabel.stringValue = Self.monthFormatter.string(from: period)
    guard let summary else {
      metrics.forEach {
        $0.value.stringValue = "…"
        $0.value.toolTip = nil
      }
      needsLayout = true
      return
    }
    let values = [
      ActivityFormatting.tokens(summary.tokens),
      ActivityFormatting.money(summary.cost),
      ActivityFormatting.money(summary.forecast),
      ActivityFormatting.activeDays(summary),
    ]
    for (metric, value) in zip(metrics, values) { metric.value.stringValue = value }
    let unpriced =
      summary.cost == nil ? "Aucun tarif connu pour les modèles de cette période." : nil
    metrics[1].value.toolTip = unpriced
    metrics[2].value.toolTip = unpriced
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let inset: CGFloat = 18
    let title = titleLabel.intrinsicContentSize
    titleLabel.frame = NSRect(
      x: inset, y: bounds.maxY - 14 - title.height, width: ceil(title.width), height: title.height)
    let period = periodLabel.intrinsicContentSize
    periodLabel.frame = NSRect(
      x: bounds.maxX - inset - ceil(period.width), y: titleLabel.frame.midY - period.height / 2,
      width: ceil(period.width), height: period.height)

    let columnWidth = (bounds.width - 2 * inset) / CGFloat(metrics.count)
    for (index, metric) in metrics.enumerated() {
      let x = inset + CGFloat(index) * columnWidth
      let caption = metric.caption.intrinsicContentSize
      let value = metric.value.intrinsicContentSize
      metric.caption.frame = NSRect(
        x: x, y: 12, width: columnWidth - 4, height: caption.height)
      metric.value.frame = NSRect(
        x: x, y: metric.caption.frame.maxY + 2, width: columnWidth - 4, height: value.height)
    }
  }
}
