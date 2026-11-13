import AppKit

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
      // Le titre entier reste lisible en info-bulle quand la pastille le tronque.
      toolTip = newValue
      needsLayout = true
      onTitleChanged?()
    }
  }

  // Le panneau ne prend jamais le focus : sans cela, le premier clic serait avalé.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard let menu = makeMenu?() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
  }

  static let height: CGFloat = 30
  /// Plafond de largeur : un nom de modèle ou de projet très long ne pousse plus les autres
  /// pastilles hors du panneau, il se tronque au milieu.
  static let maxWidth: CGFloat = 220

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
    label.lineBreakMode = .byTruncatingMiddle
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

  var fittingWidth: CGFloat { min(Self.maxWidth, 12 + labelWidth + 8 + 10 + 11) }

  /// Largeur du libellé en entier ; la pastille s'étire jusqu'à `maxWidth`, puis le libellé se
  /// tronque.
  private var labelWidth: CGFloat {
    ceil(max(label.intrinsicContentSize.width, label.attributedStringValue.size().width)) + 6
  }

  override func layout() {
    super.layout()
    let size = label.intrinsicContentSize
    let room = max(0, bounds.width - 12 - 8 - 10 - 11)
    label.frame = NSRect(
      x: 12, y: (bounds.height - size.height) / 2, width: min(labelWidth, room),
      height: size.height)
    chevron.frame = NSRect(
      x: label.frame.maxX + 8, y: (bounds.height - 10) / 2, width: 10, height: 10)
  }
}

/// Les jetons du mois en courbe douce : un dégradé sous le trait, une lueur légère, presque
/// aucun repère. La courbe se dessine de gauche à droite à l'apparition et se déforme quand les
/// données changent ; le survol montre le jour et ses jetons.
final class NotchUsageDailyChartView: NSView {

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("d MMM")
    return formatter
  }()

  /// Le vert de la barre d'usage : la courbe n'en introduit pas un second.
  private let tint = NotchUsageCardView.barGreen
  private let plotTop: CGFloat = 8
  private let plotBottom: CGFloat = 3

  var days: [ActivityDay] = [] {
    didSet {
      guard days != oldValue else { return }
      hideHover()
      let sameShape = !oldValue.isEmpty && oldValue.count == days.count
      applyGeometry(animated: sameShape)
      if !days.isEmpty && !sameShape { pendingReveal = true }
      needsLayout = true
    }
  }

  private let plot = CALayer()
  private let revealMask = CALayer()
  private let baseline = CALayer()
  private let fill = CAGradientLayer()
  private let fillShape = CAShapeLayer()
  private let glow = CAShapeLayer()
  private let line = CAShapeLayer()
  private let guide = CALayer()
  private let dot = CAShapeLayer()
  private let tip = NotchUsageHoverTip()

  private var points: [CGPoint] = []
  private var pendingReveal = false
  private var trackingArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.addSublayer(plot)
    layer?.addSublayer(guide)
    layer?.addSublayer(dot)
    layer?.addSublayer(tip.layer)

    baseline.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    plot.addSublayer(baseline)

    fill.colors = [tint.withAlphaComponent(0.34).cgColor, tint.withAlphaComponent(0).cgColor]
    fill.startPoint = CGPoint(x: 0.5, y: 1)
    fill.endPoint = CGPoint(x: 0.5, y: 0)
    fill.mask = fillShape
    plot.addSublayer(fill)

    for shape in [glow, line] {
      shape.fillColor = nil
      shape.strokeColor = tint.cgColor
      shape.lineCap = .round
      shape.lineJoin = .round
    }
    line.lineWidth = 1.75
    glow.lineWidth = 3
    glow.shadowColor = tint.cgColor
    glow.shadowOpacity = 0.9
    glow.shadowRadius = 5
    glow.shadowOffset = .zero
    plot.addSublayer(glow)
    plot.addSublayer(line)

    revealMask.backgroundColor = NSColor.white.cgColor
    revealMask.anchorPoint = CGPoint(x: 0, y: 0.5)
    plot.mask = revealMask

    guide.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
    dot.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
    dot.fillColor = tint.cgColor
    dot.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor
    dot.lineWidth = 1.5
    hideHover()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Géométrie

  override func layout() {
    super.layout()
    applyGeometry(animated: false)
    if pendingReveal, !bounds.isEmpty {
      pendingReveal = false
      playReveal()
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    tip.updateScale(window?.backingScaleFactor ?? 2)
  }

  private var reduceMotion: Bool { !OverlayAnimation.allowsMotion }

  private func applyGeometry(animated: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    plot.frame = bounds
    baseline.frame = CGRect(x: 0, y: plotBottom - 0.5, width: bounds.width, height: 1)
    fill.frame = bounds
    fillShape.frame = bounds
    revealMask.bounds = CGRect(x: 0, y: 0, width: bounds.width + 16, height: bounds.height + 16)
    revealMask.position = CGPoint(x: -8, y: bounds.height / 2)

    plot.isHidden = days.isEmpty
    baseline.isHidden = days.isEmpty
    guard !days.isEmpty, !bounds.isEmpty else {
      points = []
      return
    }

    let peak = CGFloat(max(1, days.map(\.tokens).max() ?? 1))
    let height = bounds.height - plotTop - plotBottom
    let step = days.count > 1 ? bounds.width / CGFloat(days.count - 1) : 0
    points = days.enumerated().map { index, day in
      CGPoint(
        x: days.count > 1 ? CGFloat(index) * step : bounds.width / 2,
        y: plotBottom + height * CGFloat(day.tokens) / peak)
    }

    let curve = Self.monotonePath(through: points)
    let area = CGMutablePath()
    area.addPath(curve)
    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: 0))
    area.addLine(to: CGPoint(x: points[0].x, y: 0))
    area.closeSubpath()

    let morph = animated && !reduceMotion && !bounds.isEmpty
    for (shape, path) in [(line, curve), (glow, curve), (fillShape, area as CGPath)] {
      let previous = shape.path
      shape.path = path
      if morph, let previous {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = previous
        animation.toValue = path
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        shape.add(animation, forKey: "morph")
      }
    }
  }

  /// Cubique monotone (Fritsch–Carlson, tangentes à moyenne harmonique) : lisse, sans angle, et
  /// sans dépassement — une courbe qui ne descend jamais sous les jours à zéro.
  private static func monotonePath(through points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 1 else {
      path.addLine(to: first)
      return path
    }

    let count = points.count
    let dx = (0..<count - 1).map { points[$0 + 1].x - points[$0].x }
    let slope = (0..<count - 1).map { dx[$0] == 0 ? 0 : (points[$0 + 1].y - points[$0].y) / dx[$0] }
    var tangent = [CGFloat](repeating: 0, count: count)
    tangent[0] = slope[0]
    tangent[count - 1] = slope[count - 2]
    for index in 1..<count - 1 {
      let before = slope[index - 1]
      let after = slope[index]
      tangent[index] = before * after <= 0 ? 0 : 2 / (1 / before + 1 / after)
    }
    for index in 0..<count - 1 {
      let third = dx[index] / 3
      path.addCurve(
        to: points[index + 1],
        control1: CGPoint(x: points[index].x + third, y: points[index].y + tangent[index] * third),
        control2: CGPoint(
          x: points[index + 1].x - third, y: points[index + 1].y - tangent[index + 1] * third))
    }
    return path
  }

  // MARK: - Apparition

  /// La courbe se révèle de gauche à droite : un seul masque porte le trait, la lueur et le fond.
  private func playReveal() {
    guard !reduceMotion else { return }
    let animation = CABasicAnimation(keyPath: "transform.scale.x")
    animation.fromValue = 0
    animation.toValue = 1
    animation.duration = 0.9
    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    revealMask.add(animation, forKey: "reveal")
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    guard days.count > 0, points.count == days.count, bounds.width > 0 else { return }
    let x = convert(event.locationInWindow, from: nil).x
    let ratio = days.count > 1 ? x / bounds.width : 0
    let index = min(days.count - 1, max(0, Int((ratio * CGFloat(days.count - 1)).rounded())))
    showHover(at: index)
  }

  override func mouseExited(with event: NSEvent) { hideHover() }

  private func showHover(at index: Int) {
    let point = points[index]
    let day = days[index]
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    guide.frame = CGRect(x: point.x - 0.5, y: plotBottom, width: 1, height: bounds.height - plotBottom)
    dot.position = point

    let text = "\(Self.dayFormatter.string(from: day.date)) · \(ActivityFormatting.tokens(day.tokens))"
    // À l'opposé du point pour ne pas le masquer ; bornée à la largeur du graphique.
    tip.show(text, x: point.x, y: bounds.height - 18, within: bounds.width, placement: .beside)
    [guide, dot].forEach { $0.isHidden = false }
  }

  func hideHover() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    [guide, dot].forEach { $0.isHidden = true }
    CATransaction.commit()
    tip.hide()
  }
}

/// Section « Activity » : le mois choisi, deux mesures et la courbe d'usage quotidien, tirés des
/// journaux des agents. Un balayage horizontal (deux doigts ou glisser) change de mois : le
/// contenu suit le doigt, résiste aux deux bouts (le mois en cours, six mois en arrière) et
/// change au relâché.
final class NotchUsageActivityView: NSView {

  /// Mois les plus anciens que le menu propose : 0 est le mois en cours.
  static let maxMonthOffset = 5

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
    return formatter
  }()

  /// Un balayage demande le mois `delta` plus loin dans le passé (`+1`) ou plus près (`-1`).
  var onStepMonth: ((Int) -> Void)?
  /// Mois affiché, `0` pour le mois en cours : dit jusqu'où le balayage peut aller.
  var monthOffset = 0

  private let titleLabel = NSTextField(labelWithString: "Activity")
  /// Le contenu qui suit le doigt ; le titre reste en place.
  private let page = NSView()
  private let periodLabel = NSTextField(labelWithString: "")
  private let emptyLabel = NSTextField(labelWithString: "")
  private let metrics: [(value: NSTextField, caption: NSTextField)]
  private let chart = NotchUsageDailyChartView()
  private let pager = NotchUsageSwipePager()

  override init(frame frameRect: NSRect) {
    let captions = ["Tokens", "Active days"]
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

    page.wantsLayer = true
    titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
    titleLabel.textColor = .white
    periodLabel.font = .systemFont(ofSize: 13, weight: .regular)
    periodLabel.textColor = NSColor.white.withAlphaComponent(0.85)
    periodLabel.stringValue = Self.monthFormatter.string(from: Date())
    emptyLabel.font = .systemFont(ofSize: 13, weight: .regular)
    emptyLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    emptyLabel.alignment = .center
    emptyLabel.isHidden = true

    addSubview(titleLabel)
    addSubview(page)
    page.addSubview(periodLabel)
    page.addSubview(chart)
    page.addSubview(emptyLabel)
    for (value, caption) in metrics {
      page.addSubview(value)
      page.addSubview(caption)
    }
    configurePager()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func configurePager() {
    pager.width = { [weak self] in self?.bounds.width ?? 1 }
    // Le doigt vers la droite remonte dans le temps, comme la grille du calendrier.
    pager.allows = { [weak self] direction in
      guard let self else { return false }
      return (0...Self.maxMonthOffset).contains(monthOffset + direction)
    }
    pager.presentedOffset = { [weak self] in self?.page.layer?.presentedTranslationX ?? 0 }
    pager.onTrack = { [weak self] x in
      self?.chart.hideHover()
      self?.page.layer?.trackSwipe(to: x)
    }
    pager.onCancel = { [weak self] from, velocity in
      self?.page.layer?.settleSwipe(from: from, velocity: velocity)
    }
    pager.onCommit = { [weak self] direction, from, _ in
      guard let self else { return }
      page.layer?.commitSwipe(page: direction, from: from) { [weak self] in
        self?.onStepMonth?(direction)
      }
    }
  }

  /// Le mois peut changer pendant que le panneau reste en mémoire : relu à chaque dépliage.
  func refreshPeriod() {
    periodLabel.stringValue = Self.monthFormatter.string(from: Date())
    needsLayout = true
  }

  /// Montre les mesures du mois `period`. `summary` à `nil` : journaux en cours de lecture.
  func apply(summary: ActivitySummary?, days: [ActivityDay], period: Date) {
    let monthName = Self.monthFormatter.string(from: period)
    periodLabel.stringValue = monthName
    guard let summary else {
      metrics.forEach { $0.value.stringValue = "…" }
      chart.days = []
      emptyLabel.isHidden = true
      needsLayout = true
      return
    }
    let values = [
      ActivityFormatting.tokens(summary.tokens),
      ActivityFormatting.activeDays(summary),
    ]
    for (metric, value) in zip(metrics, values) { metric.value.stringValue = value }
    // Aucun jeton ce mois-là : une courbe plate sur zéro dirait « chargement », pas « rien ».
    let isEmpty = summary.tokens == 0
    chart.days = isEmpty ? [] : days
    emptyLabel.stringValue = "No activity in \(monthName)"
    emptyLabel.isHidden = !isEmpty
    needsLayout = true
  }

  override func layout() {
    super.layout()
    page.frame = bounds
    let inset: CGFloat = 18
    let title = titleLabel.intrinsicContentSize
    titleLabel.frame = NSRect(
      x: inset, y: bounds.maxY - 14 - title.height, width: ceil(title.width), height: title.height)
    let period = periodLabel.intrinsicContentSize
    periodLabel.frame = NSRect(
      x: bounds.maxX - inset - ceil(period.width), y: titleLabel.frame.midY - period.height / 2,
      width: ceil(period.width), height: period.height)

    // Colonnes à la largeur de leur contenu (légende et valeur), et non plus 92 pt fixes qui
    // rognaient « 12 Active days » ou un grand total.
    var x = inset
    for metric in metrics {
      let caption = metric.caption.intrinsicContentSize
      let value = metric.value.intrinsicContentSize
      let columnWidth = ceil(max(caption.width, value.width, 84)) + 4
      metric.caption.frame = NSRect(x: x, y: 12, width: columnWidth, height: caption.height)
      metric.value.frame = NSRect(
        x: x, y: metric.caption.frame.maxY + 2, width: columnWidth, height: value.height)
      x += columnWidth + 16
    }

    let chartX = x - 8
    let chartTop = titleLabel.frame.minY - 10
    chart.frame = NSRect(
      x: chartX, y: 12, width: max(0, bounds.maxX - inset - chartX), height: max(0, chartTop - 12))
    emptyLabel.sizeToFit()
    emptyLabel.frame = NSRect(
      x: chart.frame.minX, y: chart.frame.midY - emptyLabel.frame.height / 2,
      width: chart.frame.width, height: emptyLabel.frame.height)
  }

  // MARK: - Geste

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) { pager.mouseDown(event) }

  override func mouseDragged(with event: NSEvent) { pager.mouseDragged(event) }

  override func mouseUp(with event: NSEvent) { pager.mouseUp(event) }

  override func scrollWheel(with event: NSEvent) {
    if !pager.scrollWheel(event) { super.scrollWheel(with: event) }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { pager.cancel() }
  }
}
