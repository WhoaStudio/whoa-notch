import AppKit

/// Bande horizontale de trois semaines, centrée sur le jour courant au premier affichage.
/// Le calendrier de l'utilisateur décide du premier jour de la semaine.
final class WeekStripView: NSView {

  private static let dayWidth: CGFloat = 44
  private static let dayGap: CGFloat = 8
  private static let dayCount = 21

  /// Place laissée à gauche et à droite du premier et du dernier jour : celle du mois à gauche,
  /// d'un fondu à droite. La bande s'arrête ainsi jour contre mois, et jamais sous un voile.
  private static let leadingInset: CGFloat = 56
  private static let trailingInset: CGFloat = 24

  /// Les fondus débordent un peu des marges, pour que le bord d'un jour ne se voie pas coupé.
  private static let leadingFadeWidth: CGFloat = leadingInset + 28
  private static let trailingFadeWidth: CGFloat = trailingInset + 24

  /// Raideur du ressort d'arrêt, en rad/s. Amorti de façon critique : il se pose sans jamais
  /// rebondir, et reprend la vitesse du geste au lieu de repartir de zéro.
  private static let springOmega: Double = 13

  /// Distance que l'inertie couvrirait encore, exprimée en secondes de vitesse de lâcher.
  /// Détermine sur quel jour le ressort se pose, pas la durée du mouvement.
  private static let projectionTime: Double = 0.22

  /// Fenêtre sur laquelle la vitesse du lâcher est estimée.
  private static let velocityWindow: TimeInterval = 0.08

  private let scrollView = WeekStripScrollView()
  private let documentView = NSView()
  private let selectionRing = CALayer()
  private var cells: [WeekDayCellView] = []
  private var days: [Date] = []
  private var leadingDayIndex: Int?
  private var motion: SpringMotion?
  private var displayLink: CADisplayLink?
  private var velocitySamples: [(time: TimeInterval, dx: CGFloat)] = []
  private var selectedIndex: Int?

  /// Vrai tant qu'un doigt est sur le trackpad : le tic ne se sent que là, et pendant le
  /// ressort qui suit le lâcher il n'y a plus de doigt pour le recevoir.
  private var isFingerDown = false

  private let monthLabel = PassthroughLabel(labelWithString: "")
  private let leadingFade = CAGradientLayer()
  private let trailingFade = CAGradientLayer()
  private var monthIndex: Int?

  private let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM")
    return formatter
  }()

  /// Appelé quand le jour choisi change, y compris au retour sur aujourd'hui après une
  /// reconstruction.
  var onSelectionChanged: ((Date) -> Void)?

  /// Jour choisi, aujourd'hui tant que l'utilisateur n'a rien cliqué.
  var selectedDate: Date {
    guard let selectedIndex, days.indices.contains(selectedIndex) else { return referenceDate }
    return days[selectedIndex]
  }

  /// Jour affiché comme « aujourd'hui ». Recalculé à chaque reconstruction : le panneau peut
  /// rester en mémoire plusieurs jours sans que l'app redémarre.
  private var referenceDate = Date()

  private let calendar = Calendar.current
  private let feedback: OverlayFeedback

  init(
    frame frameRect: NSRect = .zero,
    feedback: OverlayFeedback = SystemOverlayFeedback(playsSound: false)
  ) {
    self.feedback = feedback
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    documentView.wantsLayer = true
    selectionRing.borderWidth = 1.5
    selectionRing.cornerCurve = .continuous
    selectionRing.isHidden = true
    documentView.layer?.addSublayer(selectionRing)
    scrollView.documentView = documentView
    scrollView.onScroll = { [weak self] event in
      self?.handleScroll(event)
    }
    addSubview(scrollView)

    // Fondus noir → transparent sur chaque bord, puis le mois par-dessus celui de gauche.
    let black = NSColor.black.cgColor
    let clear = NSColor.black.withAlphaComponent(0).cgColor
    for fade in [leadingFade, trailingFade] {
      fade.startPoint = CGPoint(x: 0, y: 0.5)
      fade.endPoint = CGPoint(x: 1, y: 0.5)
      layer?.addSublayer(fade)
    }
    leadingFade.colors = [black, clear]
    trailingFade.colors = [clear, black]

    monthLabel.wantsLayer = true
    monthLabel.font = .systemFont(ofSize: 22, weight: .bold)
    monthLabel.isBezeled = false
    monthLabel.drawsBackground = false
    monthLabel.isEditable = false
    monthLabel.isSelectable = false
    monthLabel.lineBreakMode = .byClipping
    addSubview(monthLabel)
    applyMonthColor()

    rebuild()
  }

  /// Reconstruit les trois semaines autour de `date`. À appeler avant chaque apparition du
  /// panneau : sans ça, la sélection resterait sur le jour où les cases ont été créées.
  func refresh(now date: Date = Date()) {
    guard !calendar.isDate(date, inSameDayAs: referenceDate) || days.isEmpty else { return }
    referenceDate = date
    rebuild()
  }

  private func rebuild() {
    stopMotion()

    cells.forEach { $0.removeFromSuperview() }
    days = daysAround(referenceDate)
    cells = days.map { day in
      WeekDayCellView(
        initial: initial(for: day),
        dayNumber: calendar.component(.day, from: day),
        isToday: calendar.isDateInToday(day),
        isWeekend: calendar.isDateInWeekend(day)
      )
    }
    for (position, cell) in cells.enumerated() {
      cell.onClick = { [weak self] in self?.select(index: position) }
      documentView.addSubview(cell)
    }
    leadingDayIndex = nil
    monthIndex = nil
    // La sélection repart d'aujourd'hui : l'ancienne n'a plus de sens sur une autre plage.
    select(index: days.firstIndex(where: { calendar.isDateInToday($0) }) ?? days.count / 2)
    needsLayout = true
  }

  private func select(index: Int) {
    guard cells.indices.contains(index), index != selectedIndex else { return }
    let animated = selectedIndex != nil
    selectedIndex = index
    updateSelectionRing(animated: animated)
    onSelectionChanged?(days[index])
  }

  private func updateSelectionRing(animated: Bool) {
    guard let selectedIndex, cells.indices.contains(selectedIndex) else { return }
    let cell = cells[selectedIndex]
    cell.layoutSubtreeIfNeeded()
    let frame = cell.convert(cell.selectionFrame, to: documentView)
    guard !frame.isEmpty else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    selectionRing.bounds = CGRect(origin: .zero, size: frame.size)
    selectionRing.cornerRadius = frame.width / 2
    let position = CGPoint(x: frame.midX, y: frame.midY)
    if animated && !selectionRing.isHidden {
      selectionRing.springAnimate(keyPath: "position", to: position)
    } else {
      selectionRing.position = position
    }
    selectionRing.isHidden = false
    CATransaction.commit()
  }

  /// Les 21 jours allant du début de la semaine précédente à la fin de la semaine suivante.
  private func daysAround(_ date: Date) -> [Date] {
    guard
      let currentWeek = calendar.dateInterval(of: .weekOfYear, for: date),
      let firstDay = calendar.date(byAdding: .day, value: -7, to: currentWeek.start)
    else {
      return [date]
    }

    return (0..<Self.dayCount).compactMap {
      calendar.date(byAdding: .day, value: $0, to: firstDay)
    }
  }

  /// Première lettre du jour, prise dans les noms très courts du calendrier plutôt que tronquée
  /// à la main : toutes les langues n'abrègent pas en coupant au premier caractère.
  private func initial(for date: Date) -> String {
    let index = calendar.component(.weekday, from: date) - 1
    let symbols = calendar.veryShortWeekdaySymbols
    guard symbols.indices.contains(index) else { return "" }
    return symbols[index].uppercased()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cells.forEach { $0.applyPalette() }
    applyMonthColor()
  }

  private func applyMonthColor() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    monthLabel.textColor = palette.tabActiveContent
    selectionRing.borderColor = palette.calendarDayContent.withAlphaComponent(0.7).cgColor
  }

  override func layout() {
    super.layout()

    scrollView.frame = bounds

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    leadingFade.frame = NSRect(x: 0, y: 0, width: Self.leadingFadeWidth, height: bounds.height)
    trailingFade.frame = NSRect(
      x: bounds.width - Self.trailingFadeWidth, y: 0, width: Self.trailingFadeWidth,
      height: bounds.height)
    CATransaction.commit()

    let monthHeight = monthLabel.intrinsicContentSize.height
    monthLabel.frame = NSRect(
      x: 0, y: bounds.midY - monthHeight / 2, width: Self.leadingInset, height: monthHeight)

    // Le document fait exactement la largeur des cases : pas de marge latérale, donc la
    // butée du défilement tombe pile sur le premier et le dernier jour.
    let documentWidth =
      Self.leadingInset + Self.trailingInset
      + CGFloat(cells.count) * Self.stride - (cells.isEmpty ? 0 : Self.dayGap)
    documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: bounds.height)

    for (position, cell) in cells.enumerated() {
      let x = Self.leadingInset + CGFloat(position) * Self.stride
      cell.frame = NSRect(x: x, y: bounds.minY, width: Self.dayWidth, height: bounds.height)
    }

    updateSelectionRing(animated: false)

    if leadingDayIndex == nil, !days.isEmpty, bounds.width > 0 {
      // Premier affichage : aujourd'hui au centre, autant que les bornes le permettent.
      let today = days.firstIndex(where: { calendar.isDateInToday($0) }) ?? days.count / 2
      let centeredX =
        Self.leadingInset + CGFloat(today) * Self.stride + Self.dayWidth / 2 - bounds.width / 2
      setOffset(snappedOrigin(near: centeredX))
      leadingDayIndex = leadingIndex()
      updateMonth()
    }
  }

  private static var stride: CGFloat { dayWidth + dayGap }

  /// Abscisse maximale du défilement : le dernier jour collé au bord droit.
  private var maxOriginX: CGFloat {
    max(0, documentView.frame.width - scrollView.contentView.bounds.width)
  }

  // MARK: - Défilement

  /// Le défilement est piloté ici plutôt que par `NSScrollView` : son inertie s'arrête où elle
  /// veut, et l'alignement sur un jour repartait alors d'un second mouvement, d'où l'à-coup.
  /// Ici le doigt déplace la bande directement, et au lâcher un seul ressort part de la
  /// vitesse du geste vers le jour où elle aurait fini.
  private func handleScroll(_ event: NSEvent) {
    guard event.hasPreciseScrollingDeltas else {
      handleWheelStep(event)
      return
    }

    // L'inertie du système arrive après `.ended` : le ressort l'a déjà remplacée.
    guard event.momentumPhase.isEmpty else { return }

    if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
      isFingerDown = true
      stopMotion()
      velocitySamples.removeAll()
    }

    let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
    if dx != 0 {
      stopMotion()
      // Le contenu suit le doigt : sens naturel déjà résolu dans `scrollingDelta`.
      setOffset(scrollView.contentView.bounds.origin.x - dx)
      velocitySamples.append((event.timestamp, -dx))
      velocitySamples.removeAll { event.timestamp - $0.time > Self.velocityWindow }
    }

    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      isFingerDown = false
      release(at: event.timestamp)
    }
  }

  /// Molette de souris : un cran, un jour. Chaque cran déplace la cible du ressort en cours,
  /// donc des crans rapprochés s'enchaînent sans repartir de l'arrêt.
  private func handleWheelStep(_ event: NSEvent) {
    let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
    guard delta != 0 else { return }

    let current = scrollView.contentView.bounds.origin.x
    let base = motion?.target ?? current
    let target = snappedOrigin(near: base - (delta > 0 ? 1 : -1) * Self.stride)
    animate(to: target, velocity: 0)
  }

  private func release(at time: TimeInterval) {
    let recent = velocitySamples.filter { time - $0.time <= Self.velocityWindow }
    velocitySamples.removeAll()

    var velocity: CGFloat = 0
    if let first = recent.first, time - first.time > 0 {
      velocity = recent.reduce(0) { $0 + $1.dx } / CGFloat(max(time - first.time, 0.016))
    }

    let origin = scrollView.contentView.bounds.origin.x
    let landing = snappedOrigin(near: origin + velocity * Self.projectionTime)
    animate(to: landing, velocity: velocity)
  }

  private func animate(to target: CGFloat, velocity: CGFloat) {
    let origin = scrollView.contentView.bounds.origin.x

    // Mouvement réduit : on se pose directement, sans trajet à regarder.
    if !OverlayAnimation.allowsMotion {
      stopMotion()
      setOffset(target)
      return
    }

    motion = SpringMotion(
      from: origin,
      to: target,
      velocity: velocity,
      omega: Self.springOmega,
      startTime: CACurrentMediaTime()
    )
    guard displayLink == nil else { return }
    let link = displayLink(target: self, selector: #selector(stepMotion(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func stepMotion(_ link: CADisplayLink) {
    guard let motion else { return stopMotion() }
    guard OverlayAnimation.allowsMotion else {
      setOffset(motion.target)
      stopMotion()
      return
    }
    let state = motion.state(at: CACurrentMediaTime())
    setOffset(state.position)
    if state.isSettled {
      setOffset(motion.target)
      stopMotion()
    }
  }

  private func stopMotion() {
    displayLink?.invalidate()
    displayLink = nil
    motion = nil
  }

  private func setOffset(_ x: CGFloat) {
    let clamped = min(max(x, 0), maxOriginX)
    scrollView.contentView.setBoundsOrigin(
      NSPoint(x: clamped, y: scrollView.contentView.bounds.origin.y))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    tickIfDayChanged()
  }

  private func tickIfDayChanged() {
    updateMonth()
    let index = leadingIndex()
    guard index != leadingDayIndex else { return }
    if let leadingDayIndex, isFingerDown {
      let step = index > leadingDayIndex ? 1 : -1
      for _ in Swift.stride(from: leadingDayIndex + step, through: index, by: step) {
        feedback.tickCrossed()
      }
    }
    leadingDayIndex = index
  }

  /// Le mois du jour qui est au milieu de la bande. Réécrit seulement quand le jour change.
  private func updateMonth() {
    guard !days.isEmpty else { return }
    let origin = scrollView.contentView.bounds.origin.x
    let position = (origin + bounds.width / 2 - Self.leadingInset) / Self.stride
    let index = min(max(Int(position.rounded(.down)), 0), days.count - 1)
    guard index != monthIndex else { return }
    let previousIndex = monthIndex
    monthIndex = index
    let month = monthFormatter.string(from: days[index])
    guard month != monthLabel.stringValue else { return }
    monthLabel.stringValue = month
    if let previousIndex {
      monthLabel.layer?.springReveal(x: index > previousIndex ? 8 : -8, y: 0)
    }
  }

  /// Jour le plus proche du bord gauche visible.
  private func leadingIndex() -> Int {
    guard !days.isEmpty else { return 0 }
    let position = scrollView.contentView.bounds.origin.x / Self.stride
    return min(max(Int(position.rounded()), 0), days.count - 1)
  }

  /// Position d'arrêt la plus proche de `x` : un jour aligné sur le bord gauche, ou la butée
  /// droite, où le dernier jour est aligné sur le bord droit.
  private func snappedOrigin(near x: CGFloat) -> CGFloat {
    let maxX = maxOriginX
    let dayAligned = min(max((x / Self.stride).rounded() * Self.stride, 0), maxX)
    return abs(maxX - x) < abs(dayAligned - x) ? maxX : dayAligned
  }
}

/// Le mois recouvre les premiers jours : il ne doit ni prendre leurs clics ni leur défilement.
private final class PassthroughLabel: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class WeekStripScrollView: NSScrollView {

  var onScroll: ((NSEvent) -> Void)?

  /// N'appelle pas `super` : la bande est déplacée par `WeekStripView`, qui seule connaît les
  /// jours où elle doit se poser.
  override func scrollWheel(with event: NSEvent) {
    onScroll?(event)
  }
}

/// Ressort amorti de façon critique, résolu en forme fermée : la position à l'instant `t` ne
/// dépend que des conditions de départ, donc l'image affichée ne dérive pas si une image saute.
private struct SpringMotion {

  let target: CGFloat
  private let offset: Double
  private let slope: Double
  private let omega: Double
  private let startTime: TimeInterval

  init(
    from origin: CGFloat, to target: CGFloat, velocity: CGFloat, omega: Double,
    startTime: TimeInterval
  ) {
    self.target = target
    self.omega = omega
    self.startTime = startTime
    offset = Double(origin - target)
    slope = Double(velocity) + omega * offset
  }

  func state(at time: TimeInterval) -> (position: CGFloat, isSettled: Bool) {
    let t = max(0, time - startTime)
    let decay = exp(-omega * t)
    let displacement = (offset + slope * t) * decay
    let speed = (slope - omega * (offset + slope * t)) * decay
    let settled = abs(displacement) < 0.25 && abs(speed) < 4
    return (target + CGFloat(displacement), settled)
  }
}

// MARK: - Une case

/// Une case de la bande : l'initiale du jour, et son numéro dans une pastille qui n'est peinte
/// que pour aujourd'hui.
private final class WeekDayCellView: NSView {

  private let initialLabel = NSTextField(labelWithString: "")
  private let numberLabel = NSTextField(labelWithString: "")
  private let pillLayer = CALayer()
  private let isToday: Bool
  private let isWeekend: Bool

  /// Côté de la pastille du jour courant.
  private let pillSize: CGFloat = 24

  /// Écart entre la pastille et l'anneau du jour choisi.
  private let ringInset: CGFloat = 3

  var onClick: (() -> Void)?

  var selectionFrame: CGRect {
    pillLayer.frame.insetBy(dx: -ringInset, dy: -ringInset)
  }

  init(initial: String, dayNumber: Int, isToday: Bool, isWeekend: Bool) {
    self.isToday = isToday
    self.isWeekend = isWeekend
    super.init(frame: .zero)
    wantsLayer = true

    pillLayer.cornerRadius = pillSize / 2
    pillLayer.cornerCurve = .continuous
    layer?.addSublayer(pillLayer)

    for (field, text) in [(initialLabel, initial), (numberLabel, "\(dayNumber)")] {
      field.stringValue = text
      field.isBezeled = false
      field.drawsBackground = false
      field.isEditable = false
      field.isSelectable = false
      field.alignment = .center
      addSubview(field)
    }

    initialLabel.font = .systemFont(ofSize: 10, weight: .medium)
    numberLabel.font = .systemFont(ofSize: 13, weight: isToday ? .bold : .regular)

    applyPalette()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    // La bande se lit comme la grille du mois : la semaine ouvrée franche, le week-end en
    // retrait, et le jour courant blanc sur sa pastille rouge.
    let dayColor = isWeekend ? palette.calendarWeekendContent : palette.calendarDayContent
    initialLabel.textColor = dayColor
    numberLabel.textColor = isToday ? palette.tabActiveContent : dayColor
    pillLayer.backgroundColor = isToday ? palette.calendarTodayFill : nil
  }

  override func mouseDown(with event: NSEvent) {
    // Reçu pour recevoir `mouseUp` : le clic ne compte qu'au relâchement, dans la case.
  }

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onClick?()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  override func layout() {
    super.layout()

    let initialHeight = initialLabel.intrinsicContentSize.height
    initialLabel.frame = NSRect(
      x: bounds.minX,
      y: bounds.maxY - initialHeight,
      width: bounds.width,
      height: initialHeight
    )

    let pill = NSRect(
      x: bounds.midX - pillSize / 2,
      y: initialLabel.frame.minY - 4 - pillSize,
      width: pillSize,
      height: pillSize
    )
    pillLayer.frame = pill

    let numberHeight = numberLabel.intrinsicContentSize.height
    numberLabel.frame = NSRect(
      x: bounds.minX,
      y: pill.midY - numberHeight / 2,
      width: bounds.width,
      height: numberHeight
    )
  }
}
