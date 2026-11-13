import AppKit

/// Grille du mois : une ligne d'initiales de jours, puis les semaines. Le jour courant porte la
/// même pastille pleine que dans la bande de la semaine, pour que les deux surfaces se lisent
/// comme une seule.
///
/// Trois pages — le mois affiché et ses deux voisins — glissent ensemble sous un balayage à deux
/// doigts ou un glisser à la souris : la grille suit le doigt, puis se pose au ressort sur le mois
/// où le geste l'envoyait (vitesse comprise). La molette d'une souris change de mois d'un cran.
/// Un clic sur un jour le choisit ; l'appelant en montre alors les événements.
///
/// Le découpage du mois en cases appartient à `MonthGridLayout` ; chaque page ne fait que le
/// tracer, dans `draw(_:)` : quarante-deux `NSTextField` coûteraient bien plus.
final class MonthGridView: NSView {

  /// Mois affiché après un balayage, un cran de molette ou un retour à aujourd'hui.
  var onMonthChanged: ((Date) -> Void)?

  /// Jour cliqué. Jamais appelé pendant un balayage.
  var onDaySelected: ((Date) -> Void)?

  /// Premier jour du mois affiché.
  private(set) var displayedMonth: Date

  /// Jour choisi, `nil` quand c'est aujourd'hui : la pastille rouge suffit alors.
  private var selectedDate: Date?

  /// Jours qui portent au moins un événement, par mois (clé : premier jour du mois).
  private var eventDays: [Date: Set<Int>] = [:]

  /// Jour affiché comme « aujourd'hui ». Recalculé à chaque dépliage : le panneau peut rester en
  /// mémoire plusieurs jours sans que l'app redémarre.
  private var referenceDate = Date()

  private let calendar: Calendar = {
    var calendar = Calendar.current
    calendar.firstWeekday = 2
    return calendar
  }()

  /// Mois précédent, affiché, suivant — de gauche à droite.
  private let pages = [MonthPageView(), MonthPageView(), MonthPageView()]

  // MARK: Geste

  private static let translationKey = "sublayerTransform.translation.x"

  /// Taux de décélération pour projeter le relâché : 0,99, plus vif que le défilement
  /// (0,998), pour qu'un petit coup sec suffise à tourner la page sans en sauter deux.
  private static let decelerationRate: CGFloat = 0.99

  private var tracker = TabSwipeTracker()
  /// Translation au moment où le geste a pris la grille — non nulle quand on la rattrape en vol.
  private var grabOffset: CGFloat = 0
  /// Derniers déplacements, pour la vitesse au relâché.
  private var samples: [(time: TimeInterval, offset: CGFloat)] = []
  /// Mois à décaler quand le ressort en cours se pose. Rattraper la grille en vol l'applique tout
  /// de suite, et le numéro de génération rend caduque la complétion du ressort interrompu.
  private var pendingShift = 0
  private var settleGeneration = 0
  /// Le geste à deux doigts en cours est à la grille : son inertie ne doit rien relayer.
  private var ownsScrollGesture = false
  private var wheelAccumulator: CGFloat = 0
  private var lastWheelTime: TimeInterval = 0

  // MARK: Survol et appui

  private var trackingArea: NSTrackingArea?
  private var mouseDownPoint: NSPoint?
  private var lastDragTime: TimeInterval = 0

  override init(frame frameRect: NSRect) {
    displayedMonth = Date()
    super.init(frame: frameRect)
    displayedMonth = monthStart(of: referenceDate)
    wantsLayer = true
    layer?.masksToBounds = true
    pages.forEach(addSubview)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Month")
    rebuildPages()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - API

  /// Revient au mois d'aujourd'hui, sans jour choisi. Appelé à chaque dépliage du panneau.
  func refresh(now date: Date = Date()) {
    cancelGesture()
    referenceDate = date
    selectedDate = nil
    let month = monthStart(of: date)
    let changed = month != displayedMonth
    displayedMonth = month
    rebuildPages()
    if changed { onMonthChanged?(displayedMonth) }
  }

  /// Montre `date` dans la grille comme jour choisi (`nil` : aujourd'hui), en tournant la page si
  /// besoin — d'un glissé pour un mois voisin, d'un fondu au-delà.
  func select(_ date: Date?, animated: Bool) {
    selectedDate = date.map { calendar.startOfDay(for: $0) }
    let target = monthStart(of: date ?? referenceDate)
    let delta = calendar.dateComponents([.month], from: displayedMonth, to: target).month ?? 0
    if delta == 0 {
      updatePageDecorations()
    } else {
      turn(by: delta, animated: animated)
    }
  }

  func setEventDays(_ days: Set<Int>, forMonth month: Date) {
    guard eventDays[month] != days else { return }
    eventDays[month] = days
    updatePageDecorations()
  }

  /// Oublie les jours marqués : le magasin a changé.
  func clearEventDays() {
    eventDays.removeAll()
    updatePageDecorations()
  }

  // MARK: - Pages

  private func monthStart(of date: Date) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
  }

  private func month(at index: Int) -> Date {
    calendar.date(byAdding: .month, value: index - 1, to: displayedMonth) ?? displayedMonth
  }

  private func rebuildPages() {
    for (index, page) in pages.enumerated() {
      let month = month(at: index)
      page.monthLayout = MonthGridLayout(date: month, calendar: calendar, today: referenceDate)
    }
    updatePageDecorations()
  }

  private func updatePageDecorations() {
    for (index, page) in pages.enumerated() {
      let month = month(at: index)
      page.eventDays = eventDays[month] ?? []
      if let selectedDate, calendar.isDate(selectedDate, equalTo: month, toGranularity: .month),
        !calendar.isDate(selectedDate, inSameDayAs: referenceDate)
      {
        page.selectedDay = calendar.component(.day, from: selectedDate)
      } else {
        page.selectedDay = nil
      }
      page.needsDisplay = true
    }
  }

  override func layout() {
    super.layout()
    for (index, page) in pages.enumerated() {
      page.frame = NSRect(
        x: bounds.minX + CGFloat(index - 1) * bounds.width, y: bounds.minY,
        width: bounds.width, height: bounds.height)
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    pages.forEach { $0.needsDisplay = true }
  }

  // MARK: - Translation

  private var presentedTranslation: CGFloat {
    let value = (layer?.presentation() ?? layer)?.value(forKeyPath: Self.translationKey)
    return (value as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
  }

  private func setTranslation(_ x: CGFloat) {
    guard let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.removeAnimation(forKey: Self.translationKey)
    layer.setValue(x, forKeyPath: Self.translationKey)
    CATransaction.commit()
  }

  /// Arrête un ressort en vol à l'endroit où il est, et y décale les mois s'il allait tourner la
  /// page : la translation renvoyée est alors celle du même dessin, vue depuis le nouveau mois.
  private func catchInFlight() -> CGFloat {
    var x = presentedTranslation
    settleGeneration += 1
    if pendingShift != 0 {
      let shift = pendingShift
      pendingShift = 0
      shiftMonths(by: shift)
      x += CGFloat(shift) * bounds.width
    }
    setTranslation(x)
    return x
  }

  private func shiftMonths(by delta: Int) {
    guard delta != 0 else { return }
    displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    rebuildPages()
    onMonthChanged?(displayedMonth)
  }

  /// Ressort de la translation vers `target`, en partant de la vitesse du geste (pt/s).
  /// `shift` mois sont décalés quand il se pose.
  private func settle(to target: CGFloat, from current: CGFloat, velocity: CGFloat, shift: Int) {
    pendingShift = shift
    settleGeneration += 1
    let generation = settleGeneration
    let distance = target - current
    let relative = abs(distance) > 0.5 ? velocity / distance : 0
    layer?.springAnimate(
      keyPath: Self.translationKey, to: target, from: current, velocity: relative
    ) { [weak self] in
      guard let self, self.settleGeneration == generation else { return }
      let shift = self.pendingShift
      self.pendingShift = 0
      self.shiftMonths(by: shift)
      self.setTranslation(0)
    }
  }

  /// Tourne la page de `delta` mois. Un mois voisin glisse depuis son côté ; au-delà, ou sans
  /// mouvement, la grille change en fondu.
  private func turn(by delta: Int, animated: Bool) {
    guard delta != 0 else { return }
    let current = catchInFlight()
    if animated, abs(delta) == 1, OverlayAnimation.allowsMotion {
      shiftMonths(by: delta)
      // Le nouveau mois prend la place de l'ancien, qui part du côté opposé : on repart de là
      // où l'ancien était, et le ressort amène le nouveau au centre.
      let start = current + CGFloat(delta) * bounds.width
      setTranslation(start)
      settle(to: 0, from: start, velocity: 0, shift: 0)
    } else {
      setTranslation(0)
      shiftMonths(by: delta)
      if animated { fadeSwap() }
    }
  }

  /// Fondu bref, sans déplacement : ce qui remplace le glissé quand « Réduire les animations »
  /// est actif. Rien du tout si les animations de l'overlay sont coupées.
  private func fadeSwap() {
    guard OverlayAnimation.isEnabled else { return }
    let transition = CATransition()
    transition.type = .fade
    transition.duration = 0.18
    layer?.add(transition, forKey: "monthFade")
  }

  // MARK: - Geste : commun

  private func beginDrag() {
    tracker.cancel()
    grabOffset = OverlayAnimation.allowsMotion ? catchInFlight() : 0
    samples = []
  }

  /// Renvoie `true` tant que le geste est un balayage, c'est-à-dire tant qu'il appartient à la
  /// grille.
  private func moveDrag(dx: CGFloat, dy: CGFloat, time: TimeInterval) -> Bool {
    guard tracker.move(dx: dx, dy: dy) else { return false }
    let raw = grabOffset + tracker.offset
    samples.append((time, raw))
    samples.removeAll { time - $0.time > 0.1 }
    if OverlayAnimation.allowsMotion {
      setTranslation(rubberBanded(raw))
    }
    return true
  }

  private func endDrag(at releaseTime: TimeInterval) {
    let width = max(1, bounds.width)
    let wasSwiping = tracker.isSwiping
    let offset = grabOffset + tracker.offset
    tracker.cancel()
    guard wasSwiping else {
      if grabOffset != 0 { settle(to: 0, from: grabOffset, velocity: 0, shift: 0) }
      return
    }

    let velocity = Self.releaseVelocity(samples: samples, at: releaseTime)
    let page = Self.settlePage(offset: offset, velocity: velocity, width: width)

    guard OverlayAnimation.allowsMotion else {
      if page != 0 { turn(by: -Int(page), animated: true) }
      return
    }
    settle(
      to: page * width, from: rubberBanded(offset), velocity: velocity, shift: -Int(page))
  }

  /// Vitesse au relâché, en pt/s, sur les 100 dernières millisecondes avant `releaseTime`. Un
  /// doigt resté immobile avant de lâcher rend une vitesse nulle : sans ce garde-fou, le dernier
  /// mouvement d'avant la pause lançait encore la page.
  static func releaseVelocity(
    samples: [(time: TimeInterval, offset: CGFloat)], at releaseTime: TimeInterval
  ) -> CGFloat {
    let recent = samples.filter { releaseTime - $0.time <= 0.1 }
    guard let first = recent.first, let last = recent.last, last.time > first.time else {
      return 0
    }
    return (last.offset - first.offset) / CGFloat(last.time - first.time)
  }

  /// Page où se pose la grille : -1 (mois suivant), 0 ou 1 (mois précédent). On projette où le
  /// geste allait, et non où il s'est arrêté — un coup sec tourne la page même court.
  static func settlePage(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> CGFloat {
    guard width > 0 else { return 0 }
    let rate = decelerationRate
    let projected = offset + velocity / 1000 * rate / (1 - rate)
    return max(-1, min(1, (projected / width).rounded()))
  }

  private func cancelGesture() {
    tracker.cancel()
    ownsScrollGesture = false
    mouseDownPoint = nil
    pages[1].pressedIndex = nil
    if pendingShift != 0 || presentedTranslation != 0 {
      _ = catchInFlight()
      setTranslation(0)
    }
  }

  /// Au-delà d'une page dans un sens, la grille résiste de plus en plus au lieu de s'arrêter
  /// net : un geste ne tourne qu'une page à la fois.
  private func rubberBanded(_ x: CGFloat) -> CGFloat {
    let limit = bounds.width
    guard abs(x) > limit, limit > 0 else { return x }
    let over = abs(x) - limit
    let constant: CGFloat = 0.55
    let damped = (over * limit * constant) / (limit + constant * over)
    return (limit + damped) * (x < 0 ? -1 : 1)
  }

  // MARK: - Geste : trackpad et molette

  override func scrollWheel(with event: NSEvent) {
    // Molette d'une souris : un cran, un mois. Vers le haut, le mois d'avant. Une souris à
    // défilement fin envoie des deltas précis sans phase : elle passe aussi par ici, faute de
    // quoi la grille suivrait ses deltas sans jamais recevoir de fin de geste.
    guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty || !event.momentumPhase.isEmpty
    else {
      let delta = event.scrollingDeltaY
      // Un reste d'un ancien défilement, ou de l'autre sens, ne doit pas compter.
      if event.timestamp - lastWheelTime > 0.3 || (delta > 0) != (wheelAccumulator > 0) {
        wheelAccumulator = 0
      }
      lastWheelTime = event.timestamp
      wheelAccumulator += event.hasPreciseScrollingDeltas ? delta / 12 : delta
      if abs(wheelAccumulator) >= 1 {
        turn(by: wheelAccumulator > 0 ? -1 : 1, animated: true)
        wheelAccumulator = 0
      }
      return
    }

    // L'inertie qui suit un balayage de la grille lui appartient : la relayer ferait défiler
    // ou balayer autre chose après coup.
    if !event.momentumPhase.isEmpty {
      if !ownsScrollGesture { super.scrollWheel(with: event) }
      return
    }

    if event.phase.contains(.began) {
      ownsScrollGesture = false
      beginDrag()
      // Le premier delta compte pour la grille ; il ne part au panneau (qui remet alors son
      // propre balayage à zéro) que si la grille ne l'a pas pris.
      if moveDrag(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, time: event.timestamp) {
        ownsScrollGesture = true
      } else {
        super.scrollWheel(with: event)
      }
      return
    }
    if event.phase.contains(.cancelled) {
      let owned = ownsScrollGesture
      tracker.cancel()
      settle(to: 0, from: presentedTranslation, velocity: 0, shift: 0)
      if !owned { super.scrollWheel(with: event) }
      return
    }

    if moveDrag(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, time: event.timestamp) {
      ownsScrollGesture = true
    } else if !ownsScrollGesture {
      // Geste surtout vertical, ou pas encore décidé : le panneau en fait ce qu'il veut.
      super.scrollWheel(with: event)
    }

    if event.phase.contains(.ended) {
      let owned = ownsScrollGesture
      endDrag(at: event.timestamp)
      if !owned { super.scrollWheel(with: event) }
    }
  }

  // MARK: - Geste : souris

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    mouseDownPoint = point
    lastDragTime = event.timestamp
    beginDrag()
    // Retour d'appui immédiat, sur le jour pressé : la sélection, elle, attend le relâché. Une
    // grille rattrapée en vol n'est pas encore à sa place : ce clic l'arrête, il ne choisit rien.
    pages[1].pressedIndex =
      grabOffset == 0 ? pages[1].cellIndex(at: convert(point, to: pages[1])) : nil
  }

  override func mouseDragged(with event: NSEvent) {
    guard mouseDownPoint != nil else { return }
    if moveDrag(dx: event.deltaX, dy: -event.deltaY, time: event.timestamp) {
      pages[1].pressedIndex = nil
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard mouseDownPoint != nil else { return }
    mouseDownPoint = nil
    let wasSwiping = tracker.isSwiping
    let pressed = pages[1].pressedIndex
    pages[1].pressedIndex = nil
    endDrag(at: event.timestamp)
    guard !wasSwiping else { return }

    let point = convert(convert(event.locationInWindow, from: nil), to: pages[1])
    guard let pressed, pages[1].cellIndex(at: point) == pressed,
      let day = pages[1].monthLayout.days[pressed],
      let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
    else { return }
    let isToday = calendar.isDate(date, inSameDayAs: referenceDate)
    selectedDate = isToday ? nil : date
    updatePageDecorations()
    onDaySelected?(date)
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    pages[1].hoveredIndex = tracker.isSwiping ? nil : pages[1].cellIndex(at: convert(point, to: pages[1]))
  }

  override func mouseExited(with event: NSEvent) {
    pages[1].hoveredIndex = nil
  }
}

// MARK: - Page

/// Un mois tracé. Ne reçoit aucun clic : `MonthGridView` les traite et lui demande seulement
/// quelle case est sous un point.
private final class MonthPageView: NSView {

  /// Hauteur de la ligne d'initiales, au-dessus des semaines.
  static let headerHeight: CGFloat = 14

  var monthLayout = MonthGridLayout(date: Date()) { didSet { needsDisplay = true } }
  var selectedDay: Int?
  var eventDays: Set<Int> = []
  var hoveredIndex: Int? {
    didSet { if hoveredIndex != oldValue { needsDisplay = true } }
  }
  var pressedIndex: Int? {
    didSet { if pressedIndex != oldValue { needsDisplay = true } }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var isFlipped: Bool { false }

  /// Hauteur maximale d'une semaine : un mois de quatre ou cinq semaines garde le pas d'un mois
  /// de six au lieu de s'étirer sur toute la hauteur, et ses semaines restent groupées en haut.
  static let maxRowHeight: CGFloat = 22

  private var rowCount: Int { monthLayout.rowCount }

  private var rowHeight: CGFloat {
    min(Self.maxRowHeight, (bounds.height - Self.headerHeight) / CGFloat(rowCount))
  }

  /// Bornes d'une case, calculées depuis le bord puis arrondies — jamais cumulées : un arrondi
  /// par case laisserait dériver la dernière ligne et chevaucher ses voisines.
  private func cellRect(at index: Int) -> NSRect {
    let columns = CGFloat(MonthGridLayout.columnCount)
    let column = CGFloat(index % MonthGridLayout.columnCount)
    let row = CGFloat(index / MonthGridLayout.columnCount)
    let columnWidth = bounds.width / columns
    let top = bounds.maxY - Self.headerHeight
    let x0 = (columnWidth * column).rounded()
    let x1 = (columnWidth * (column + 1)).rounded()
    let y1 = (top - rowHeight * row).rounded()
    let y0 = (top - rowHeight * (row + 1)).rounded()
    return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  func cellIndex(at point: NSPoint) -> Int? {
    guard bounds.contains(point), point.y < bounds.maxY - Self.headerHeight else { return nil }
    let column = Int(point.x / (bounds.width / CGFloat(MonthGridLayout.columnCount)))
    let row = Int((bounds.maxY - Self.headerHeight - point.y) / rowHeight)
    let index = row * MonthGridLayout.columnCount + column
    guard (0..<rowCount).contains(row), monthLayout.days.indices.contains(index),
      monthLayout.days[index] != nil
    else { return nil }
    return index
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    let columnWidth = bounds.width / CGFloat(MonthGridLayout.columnCount)

    for (column, initial) in monthLayout.weekdayInitials.enumerated() {
      let x0 = (columnWidth * CGFloat(column)).rounded()
      let x1 = (columnWidth * CGFloat(column + 1)).rounded()
      draw(
        initial,
        font: .systemFont(ofSize: 9, weight: .medium),
        color: color(ofColumn: column, palette: palette).withAlphaComponent(0.7),
        centeredAt: NSPoint(x: (x0 + x1) / 2, y: bounds.maxY - Self.headerHeight / 2)
      )
    }

    for (index, day) in monthLayout.days.enumerated() {
      guard let day, index / MonthGridLayout.columnCount < rowCount else { continue }
      let cell = cellRect(at: index)
      let column = index % MonthGridLayout.columnCount
      let isToday = index == monthLayout.todayIndex
      let isSelected = day == selectedDay
      let hasEvents = eventDays.contains(day)

      let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: isToday ? .bold : .regular)
      let text = "\(day)"
      let textWidth = (text as NSString).size(withAttributes: [.font: font]).width

      // Une gélule plutôt qu'un cercle : quand la ligne est basse, un cercle de la hauteur de la
      // ligne ne contenait plus deux chiffres en gras.
      let pillHeight = max(14, min(cell.height - 2, 22))
      let pillWidth = min(cell.width - 2, max(pillHeight, textWidth + 9))
      let pill = NSRect(
        x: cell.midX - pillWidth / 2, y: cell.midY - pillHeight / 2,
        width: pillWidth, height: pillHeight)
      let pillPath = NSBezierPath(
        roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2)

      if isToday {
        NSColor(cgColor: palette.calendarTodayFill)?.setFill()
        pillPath.fill()
      } else if index == pressedIndex || index == hoveredIndex || isSelected {
        let alpha: CGFloat = index == pressedIndex ? 0.22 : (isSelected ? 0.16 : 0.09)
        NSColor.white.withAlphaComponent(alpha).setFill()
        pillPath.fill()
      }
      if isSelected, !isToday {
        palette.calendarAccent.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(
          roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: pillHeight / 2 - 0.5,
          yRadius: pillHeight / 2 - 0.5)
        ring.lineWidth = 1
        ring.stroke()
      }

      // Le point d'événement se pose au pied du chiffre, dans la gélule : le chiffre monte d'un
      // cran pour lui faire place, et seulement quand le jour en porte un.
      let lift: CGFloat = hasEvents ? 1.5 : 0
      draw(
        text, font: font,
        color: isToday ? palette.tabActiveContent : color(ofColumn: column, palette: palette),
        centeredAt: NSPoint(x: cell.midX, y: cell.midY + lift))

      if hasEvents {
        let dot: CGFloat = 3
        let dotRect = NSRect(
          x: cell.midX - dot / 2, y: pill.minY + 1.5, width: dot, height: dot)
        (isToday ? palette.tabActiveContent : palette.tabInactiveContent).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
      }
    }
  }

  /// Teinte d'une colonne : le week-end est le seul que la grille distingue, et elle ne le
  /// distingue que par là.
  private func color(ofColumn column: Int, palette: OverlayPalette) -> NSColor {
    let isWeekend =
      monthLayout.isWeekendColumn.indices.contains(column) && monthLayout.isWeekendColumn[column]
    return isWeekend ? palette.calendarWeekendContent : palette.calendarDayContent
  }

  private func draw(_ text: String, font: NSFont, color: NSColor, centeredAt center: NSPoint) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = string.size()
    string.draw(
      at: NSPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded()))
  }
}
