import AppKit

/// Liste des événements du jour : une barre d'accent à la couleur du calendrier porteur, l'heure,
/// puis le titre. Quand la journée est épuisée, la liste enchaîne sur demain sous un intertitre —
/// sans quoi le widget serait vide tous les soirs.
///
/// Dessinée dans `draw(_:)`, comme `MonthGridView` : une ligne n'est qu'une barre et deux chaînes,
/// et la liste change au rythme des événements, pas à celui de la souris.
///
/// `isInteractive` (onglet Calendar) ajoute : survol et appui sur les lignes, un clic qui déplie
/// l'événement (titre entier, plage horaire, durée), le titre qui défile au survol quand il est
/// coupé, et le trait « maintenant » entre ce qui est passé et ce qui vient.
final class AgendaListView: NSView {

  private var state: CalendarAgendaState = .loading

  /// Posé par l'onglet Global : quand l'agenda est illisible, la liste montre alors une carte
  /// avec un bouton (demander l'accès, ou ouvrir Réglages) au lieu d'une simple phrase, et
  /// appelle ceci quand la demande est tranchée pour que l'appelant relise le jour. Sans lui,
  /// la liste garde sa phrase.
  var onAccessResolved: (() -> Void)? {
    didSet { updateAccessCard() }
  }

  /// Lignes cliquables et dépliables, titres qui défilent, trait « maintenant ».
  var isInteractive = false {
    didSet {
      if !isInteractive { collapseAll(animated: false) }
      needsDisplay = true
      updateMarquees()
    }
  }

  private let accessCard = CalendarAccessCardView()

  /// Hauteur d'une ligne d'événement.
  private let rowHeight: CGFloat = 24

  /// Hauteur de l'intertitre « Tomorrow », plus serré qu'une ligne d'événement : il sépare, il
  /// ne s'énumère pas.
  private let headingHeight: CGFloat = 18

  /// Hauteur du trait « maintenant ».
  private let nowMarkerHeight: CGFloat = 8

  /// Hauteur d'une ligne de détail dans un événement déplié.
  private let detailLineHeight: CGFloat = 17

  /// Largeur de la barre d'accent et son écart au texte.
  private let accentWidth: CGFloat = 3
  private let accentGap: CGFloat = 9

  /// Écart entre l'heure et le titre.
  private let timeTitleGap: CGFloat = 8

  private let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
  private let titleFont = NSFont.systemFont(ofSize: 11, weight: .regular)

  /// Heures affichées dans le format de l'utilisateur — 24 h en France, AM/PM aux États-Unis.
  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("j:mm")
    return formatter
  }()

  private let intervalFormatter: DateIntervalFormatter = {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  private let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.maximumUnitCount = 2
    return formatter
  }()

  /// Largeur de la colonne de l'heure, devant le titre : la plus large des heures possibles
  /// dans le format de l'utilisateur, mesurée une fois. Une largeur fixe de 52 pt collait
  /// « 12:00 PM » au titre ; mesurer chaque heure ferait danser les titres d'une ligne à
  /// l'autre.
  private lazy var timeColumnWidth: CGFloat = {
    let calendar = Calendar.current
    let base = calendar.startOfDay(for: Date())
    let samples = [10, 12, 22].compactMap {
      calendar.date(bySettingHour: $0, minute: 58, second: 0, of: base)
    }
    let texts = samples.map(timeFormatter.string(from:)) + ["All day"]
    let widest = texts.map { ($0 as NSString).size(withAttributes: [.font: timeFont]).width }
      .max() ?? 40
    return ceil(widest) + timeTitleGap
  }()

  // MARK: Interaction

  private var trackingArea: NSTrackingArea?
  private var hoveredEventID: String?
  private var pressedEventID: String?

  /// Ouverture de chaque événement, de 0 (replié) à 1 (déplié). Un seul se déplie à la fois ;
  /// celui qu'on quitte se replie pendant que l'autre s'ouvre.
  private var expansion: [String: SpringValue] = [:]

  /// Entrée échelonnée des lignes, depuis `entranceStart`.
  private var entranceStart: CFTimeInterval?
  private let entranceStagger: CFTimeInterval = 0.035
  private let entranceDuration: CFTimeInterval = 0.24

  private var displayLink: CADisplayLink?
  private var lastTick: CFTimeInterval?

  /// Un défilement de titre par ligne visible, posé exactement sur le titre coupé.
  private var marquees: [TitleMarqueeOverlay] = []
  private var marqueeEventIDs: [String?] = []
  private var marqueeActiveID: String?

  /// Titre de l'événement déplié, sur deux lignes au plus et coupé d'une ellipse au-delà — ce
  /// que le tracé direct d'une chaîne ne sait pas faire hors d'un champ.
  private let expandedTitleField = ExpandedTitleField(wrappingLabelWithString: "")
  private var expandedTitleID: String?

  /// Heure courante, pour le trait « maintenant » et le passé estompé. Remplaçable en test.
  var now: () -> Date = { Date() }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    accessCard.isHidden = true
    accessCard.onAction = { [weak self] in self?.performAccessAction() }
    expandedTitleField.isHidden = true
    expandedTitleField.maximumNumberOfLines = 2
    expandedTitleField.lineBreakMode = .byWordWrapping
    expandedTitleField.cell?.truncatesLastVisibleLine = true
    expandedTitleField.font = titleFont
    addSubview(expandedTitleField)
    addSubview(accessCard)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ newState: CalendarAgendaState, travel: CGFloat? = nil) {
    guard newState != state else { return }
    state = newState
    // Un événement déplié qui n'est plus dans la liste ne doit pas réapparaître ouvert.
    let ids = Set(events().map(\.id))
    expansion = expansion.filter { ids.contains($0.key) }
    needsDisplay = true
    updateAccessCard()
    updateMarquees()
    if let travel, window != nil {
      layer?.springReveal(x: travel, y: travel == 0 ? -8 : 0)
    }
  }

  /// Fait entrer les lignes l'une après l'autre, de quelques points vers leur place. Sans
  /// mouvement autorisé, elles sont simplement là.
  func playEntrance() {
    guard OverlayAnimation.allowsMotion, window != nil else {
      entranceStart = nil
      return
    }
    entranceStart = CACurrentMediaTime()
    startTicking()
    needsDisplay = true
  }

  /// Replie tout — au repli du panneau, ou au changement de jour.
  func collapseAll(animated: Bool) {
    for id in expansion.keys {
      expansion[id]?.target = 0
      if !animated || !OverlayAnimation.allowsMotion { expansion[id] = nil }
    }
    if animated { startTicking() }
    needsDisplay = true
    updateMarquees()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    accessCard.frame = bounds
    updateMarquees()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { stopTicking() }
  }

  // MARK: - Carte d'accès

  /// Accès refusé ou pas encore demandé, et un appelant prêt à relire : la carte remplace la
  /// phrase.
  private var accessToShow: CalendarAccess? {
    guard onAccessResolved != nil, case .unavailable(let access) = state else { return nil }
    return access
  }

  private func updateAccessCard() {
    if let access = accessToShow {
      accessCard.apply(access)
      accessCard.isHidden = false
    } else {
      accessCard.isHidden = true
    }
    needsDisplay = true
  }

  private func performAccessAction() {
    switch state {
    case .unavailable(.notDetermined):
      Task { [weak self] in
        await PrivacyPermissionService.request(.calendars)
        self?.onAccessResolved?()
      }
    case .unavailable:
      PrivacyPermissionService.openSettings(.calendars)
    default:
      break
    }
  }

  // MARK: - Ce qu'il y a à écrire

  /// Une entrée de la liste, déjà résolue : la mise en page n'a plus à distinguer d'où vient la
  /// ligne, et le calcul de ce qui tient dans la hauteur se fait sur une seule séquence.
  private enum Entry {
    case heading(String)
    case event(AgendaEvent, isPast: Bool)
    case now
  }

  private func events() -> [AgendaEvent] {
    guard let agenda = state.agenda else { return [] }
    return agenda.today.events + agenda.tomorrow.events
  }

  private func entries() -> [Entry] {
    guard let agenda = state.agenda else { return [] }
    let now = self.now()

    let isToday = Calendar.current.isDate(agenda.today.date, inSameDayAs: now)
    var entries: [Entry] = []
    var markerPlaced = !(isInteractive && isToday)
    var sawPast = false
    for event in agenda.today.events {
      let isPast = !markerPlaced && !event.isAllDay && Self.hasEnded(event, at: now)
      if !markerPlaced, !event.isAllDay, event.start > now {
        // Le trait ne se pose qu'entre du passé et de l'à-venir : en tête de journée, il ne
        // dirait rien.
        if sawPast { entries.append(.now) }
        markerPlaced = true
      }
      sawPast = sawPast || isPast
      entries.append(.event(event, isPast: isPast))
    }
    if !markerPlaced, sawPast { entries.append(.now) }

    // Demain ne s'annonce que s'il a quelque chose à annoncer, et toujours sous son
    // intertitre : sans lui, les événements de demain se liraient comme ceux d'aujourd'hui.
    if !agenda.tomorrow.isEmpty {
      entries.append(.heading("Tomorrow"))
      entries.append(contentsOf: agenda.tomorrow.events.map { Entry.event($0, isPast: false) })
    }
    return entries
  }

  private static func hasEnded(_ event: AgendaEvent, at now: Date) -> Bool {
    event.isPointInTime ? event.start <= now : event.end <= now
  }

  /// Mot à afficher quand il n'y a aucune ligne. Les trois situations ne se disent pas avec les
  /// mêmes mots : l'utilisateur doit savoir s'il n'a rien de prévu, ou si l'app n'a simplement
  /// pas le droit de le lui dire.
  private var placeholder: String? {
    switch state {
    case .loading:
      nil
    case .loaded:
      "No events"
    case .unavailable(.notDetermined):
      accessToShow == nil ? "Calendar access not granted" : nil
    case .unavailable:
      accessToShow == nil ? "Calendar access denied — enable it in System Settings" : nil
    }
  }

  // MARK: - Mise en page des lignes

  private struct Row {
    let entry: Entry
    let rect: NSRect
    let index: Int

    var event: AgendaEvent? {
      if case .event(let event, _) = entry { return event }
      return nil
    }
  }

  /// Ce qui tient dans la hauteur, et combien d'entrées restent dessous. Une ligne de trop vaut
  /// mieux qu'un titre coupé en deux : on s'arrête à la dernière entrée entièrement visible.
  private func rowLayout() -> (rows: [Row], remaining: Int, bottom: CGFloat) {
    let all = entries()
    var heights: [CGFloat] = []
    var used: CGFloat = 0
    for entry in all {
      let height = self.height(of: entry)
      guard used + height <= bounds.height else { break }
      heights.append(height)
      used += height
    }

    // La mention du reste prend elle-même une ligne : si elle ne tient pas, on sacrifie la
    // dernière entrée affichée pour la lui laisser.
    if all.count > heights.count, used + headingHeight > bounds.height, let last = heights.popLast()
    {
      used -= last
    }

    var rows: [Row] = []
    var y = bounds.maxY
    for (index, height) in heights.enumerated() {
      y -= height
      rows.append(
        Row(
          entry: all[index], rect: NSRect(x: bounds.minX, y: y, width: bounds.width, height: height),
          index: index))
    }
    return (rows, all.count - heights.count, y)
  }

  private func height(of entry: Entry) -> CGFloat {
    switch entry {
    case .heading: headingHeight
    case .now: nowMarkerHeight
    case .event(let event, _):
      rowHeight + (expansion[event.id]?.value ?? 0) * extraHeight(of: event)
    }
  }

  private var titleX: CGFloat { bounds.minX + accentWidth + accentGap + timeColumnWidth }

  private var titleWidth: CGFloat { max(0, bounds.maxX - titleX) }

  /// Lignes de titre qu'un événement déplié occupe : deux au plus, le reste se lit au survol.
  private func titleLineCount(of event: AgendaEvent) -> Int {
    let title = displayTitle(of: event) as NSString
    let width = title.size(withAttributes: [.font: titleFont]).width
    return width > titleWidth ? 2 : 1
  }

  /// Avance d'une ligne de titre à l'autre, quand le titre déplié passe à la ligne.
  private lazy var titleLineHeight: CGFloat = ceil(
    NSLayoutManager().defaultLineHeight(for: titleFont))

  /// Boîte d'une ligne de titre, telle que la liste l'a toujours tracée.
  private var titleLineBox: CGFloat { ceil(titleFont.boundingRectForFont.height) }

  private func extraHeight(of event: AgendaEvent) -> CGFloat {
    CGFloat(titleLineCount(of: event) - 1) * titleLineHeight + detailLineHeight
  }

  private func displayTitle(of event: AgendaEvent) -> String {
    event.title.isEmpty ? "(no title)" : event.title
  }

  // MARK: - Tracé

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    let (rows, remaining, bottom) = rowLayout()

    guard !rows.isEmpty || remaining > 0 else {
      if let placeholder {
        draw(
          placeholder,
          font: .systemFont(ofSize: 11, weight: .regular),
          color: palette.tabInactiveContent,
          at: NSPoint(x: bounds.minX, y: bounds.maxY - rowHeight)
        )
      }
      return
    }

    let now = CACurrentMediaTime()
    for row in rows {
      let appearance = entranceProgress(of: row.index, at: now)
      guard appearance > 0 else { continue }
      let rect = row.rect.offsetBy(dx: 0, dy: -(1 - appearance) * 6)
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: row.rect.union(rect)).addClip()
      draw(row.entry, in: rect, palette: palette, opacity: appearance)
      NSGraphicsContext.restoreGraphicsState()
    }

    if remaining > 0 {
      let appearance = entranceProgress(of: rows.count, at: now)
      draw(
        "+\(remaining) more",
        font: .systemFont(ofSize: 10, weight: .medium),
        color: palette.tabInactiveContent.withAlphaComponent(appearance),
        at: NSPoint(x: bounds.minX + accentWidth + accentGap, y: bottom - headingHeight + 4)
      )
    }
  }

  /// 0 avant que la ligne n'entre, 1 une fois posée. Courbe en sortie franche (cubique) : la
  /// ligne arrive vite et se pose doucement.
  private func entranceProgress(of index: Int, at now: CFTimeInterval) -> CGFloat {
    guard let entranceStart else { return 1 }
    let elapsed = now - entranceStart - Double(index) * entranceStagger
    let t = min(1, max(0, elapsed / entranceDuration))
    return CGFloat(1 - pow(1 - t, 3))
  }

  private func draw(_ entry: Entry, in rect: NSRect, palette: OverlayPalette, opacity: CGFloat) {
    switch entry {
    case .heading(let title):
      draw(
        title.uppercased(),
        font: .systemFont(ofSize: 9, weight: .semibold),
        color: palette.tabInactiveContent.withAlphaComponent(opacity),
        at: NSPoint(x: rect.minX, y: rect.minY + 4)
      )

    case .now:
      // Un point sur l'axe des barres d'accent, puis un filet : l'heure qu'il est, posée entre
      // ce qui est fait et ce qui vient.
      let color = palette.calendarAccent.withAlphaComponent(opacity)
      color.setFill()
      let dot: CGFloat = 5
      let centerX = rect.minX + accentWidth / 2
      NSBezierPath(
        ovalIn: NSRect(x: centerX - dot / 2, y: rect.midY - dot / 2, width: dot, height: dot)
      ).fill()
      NSRect(x: centerX, y: rect.midY - 0.5, width: rect.maxX - centerX, height: 1).fill()

    case .event(let event, let isPast):
      drawEvent(event, isPast: isPast, in: rect, palette: palette, opacity: opacity)
    }
  }

  private func drawEvent(
    _ event: AgendaEvent, isPast: Bool, in rect: NSRect, palette: OverlayPalette,
    opacity: CGFloat
  ) {
    let progress = expansion[event.id]?.value ?? 0
    // Le passé s'efface d'un cran : la journée se lit depuis maintenant.
    let alpha = opacity * (isPast ? 0.45 : 1)

    // Fond de ligne derrière le texte seulement — la barre d'accent reste nue.
    if isInteractive {
      let highlight: CGFloat =
        event.id == pressedEventID
        ? 0.14 : max(event.id == hoveredEventID ? 0.07 : 0, 0.06 * min(1, progress * 2))
      if highlight > 0 {
        let x = rect.minX + accentWidth + accentGap - 5
        let background = NSRect(x: x, y: rect.minY + 1, width: rect.maxX - x, height: rect.height - 2)
        NSColor.white.withAlphaComponent(highlight * opacity).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
      }
    }

    // Barre d'accent à la couleur du calendrier porteur : c'est le seul endroit du panneau où
    // la couleur ne vient pas de la palette, et c'est voulu — elle est le rappel du calendrier
    // d'où sort l'événement.
    let bar = NSRect(x: rect.minX, y: rect.minY + 3, width: accentWidth, height: rect.height - 6)
    let accent = NSColor(cgColor: event.color.cgColor) ?? palette.tabActiveContent
    accent.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: bar, xRadius: accentWidth / 2, yRadius: accentWidth / 2).fill()

    // Le titre et l'heure se teintent de cette même couleur, relevée pour l'un, assombrie pour
    // l'autre : les trois marques d'une ligne disent alors le même calendrier.
    let firstLineY = rect.maxY - rowHeight / 2 - 7
    let timeColor = OverlayPalette.agendaTimeColor(for: accent).withAlphaComponent(alpha)
    draw(time(of: event), font: timeFont, color: timeColor, at: NSPoint(x: bar.maxX + accentGap, y: firstLineY))

    let titleColor = OverlayPalette.agendaTitleColor(for: accent).withAlphaComponent(alpha)
    if marqueeActiveID != event.id, expandedTitleID != event.id {
      // Déplié, le titre a droit à deux lignes ; le rectangle grandit avec l'ouverture, et le
      // texte se coupe là où il en est.
      let lines = progress > 0 ? CGFloat(titleLineCount(of: event)) : 1
      let extra = (lines - 1) * titleLineHeight * progress
      let titleRect = NSRect(
        x: titleX, y: firstLineY - extra, width: titleWidth, height: titleLineBox + extra)
      drawWrapped(displayTitle(of: event), color: titleColor, in: titleRect)
    }

    guard progress > 0.01 else { return }
    let titleLines = CGFloat(titleLineCount(of: event) - 1) * titleLineHeight
    draw(
      detail(of: event),
      font: .systemFont(ofSize: 10, weight: .regular),
      color: palette.tabInactiveContent.withAlphaComponent(alpha * progress),
      at: NSPoint(x: titleX, y: firstLineY - titleLines - detailLineHeight - 1)
    )
  }

  /// « All day » pour un événement sans heure, l'heure seule pour un rappel sans durée — qui
  /// s'écrirait sinon « 17:00 – 17:00 » —, et l'heure de début sinon. La liste étant étroite,
  /// l'heure de fin n'y figure que dans la ligne dépliée.
  private func time(of event: AgendaEvent) -> String {
    guard !event.isAllDay else { return "All day" }
    return timeFormatter.string(from: event.start)
  }

  /// Ligne de détail d'un événement déplié : la plage horaire et la durée.
  private func detail(of event: AgendaEvent) -> String {
    if event.isAllDay { return "All day" }
    if event.isPointInTime { return "At \(timeFormatter.string(from: event.start))" }
    let range = intervalFormatter.string(from: event.start, to: event.end)
    guard let duration = durationFormatter.string(from: event.end.timeIntervalSince(event.start))
    else { return range }
    return "\(range) · \(duration)"
  }

  private func drawWrapped(_ text: String, color: NSColor, in rect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode =
      rect.height > titleLineBox + titleLineHeight / 2 ? .byWordWrapping : .byTruncatingTail
    NSAttributedString(
      string: text,
      attributes: [.font: titleFont, .foregroundColor: color, .paragraphStyle: style]
    ).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }

  private func draw(_ text: String, font: NSFont, color: NSColor, at point: NSPoint) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
      .draw(at: point)
  }

  // MARK: - Survol, appui, dépliage

  private func eventID(at point: NSPoint) -> String? {
    rowLayout().rows.first { $0.rect.contains(point) }?.event?.id
  }

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
    guard isInteractive else { return super.mouseMoved(with: event) }
    let id = eventID(at: convert(event.locationInWindow, from: nil))
    guard id != hoveredEventID else { return }
    hoveredEventID = id
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    guard hoveredEventID != nil else { return }
    hoveredEventID = nil
    needsDisplay = true
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isInteractive }

  override func mouseDown(with event: NSEvent) {
    guard isInteractive, accessCard.isHidden else { return super.mouseDown(with: event) }
    // Retour d'appui immédiat ; le dépliage attend le relâché, qu'un glisser dehors annule.
    pressedEventID = eventID(at: convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard isInteractive, pressedEventID != nil else { return super.mouseDragged(with: event) }
  }

  override func mouseUp(with event: NSEvent) {
    guard isInteractive, accessCard.isHidden else { return super.mouseUp(with: event) }
    let pressed = pressedEventID
    pressedEventID = nil
    let id = eventID(at: convert(event.locationInWindow, from: nil))
    if let id, id == pressed {
      toggle(id)
    } else if pressed == nil, id == nil {
      // Un clic dans le vide de la liste replie ce qui était ouvert.
      collapseAll(animated: true)
    }
    needsDisplay = true
  }

  private func toggle(_ id: String) {
    let opening = (expansion[id]?.target ?? 0) < 1
    for key in expansion.keys { expansion[key]?.target = 0 }
    if opening {
      expansion[id, default: SpringValue()].target = 1
    }
    if OverlayAnimation.allowsMotion {
      startTicking()
    } else {
      for key in expansion.keys { expansion[key]?.settle() }
      expansion = expansion.filter { $0.value.value > 0 }
    }
    // Un titre qui défile ne doit pas rester posé sur une ligne qui s'ouvre.
    updateMarquees()
    needsDisplay = true
  }

  // MARK: - Horloge

  private func startTicking() {
    guard displayLink == nil, window != nil else { return }
    let link = displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    lastTick = nil
  }

  private func stopTicking() {
    displayLink?.invalidate()
    displayLink = nil
    lastTick = nil
  }

  @objc private func tick(_ link: CADisplayLink) {
    let now = link.timestamp
    let dt = min(1.0 / 30, lastTick.map { now - $0 } ?? 1.0 / 60)
    lastTick = now

    var moving = false
    for key in Array(expansion.keys) {
      expansion[key]?.step(dt: CGFloat(dt))
      if let spring = expansion[key] {
        if spring.isSettled {
          if spring.target == 0 { expansion[key] = nil }
        } else {
          moving = true
        }
      }
    }

    if let entranceStart {
      let rowCount = rowLayout().rows.count + 1
      let end = entranceStart + Double(rowCount) * entranceStagger + entranceDuration
      if CACurrentMediaTime() >= end {
        self.entranceStart = nil
      } else {
        moving = true
      }
    }

    needsDisplay = true
    updateMarquees()
    if !moving { stopTicking() }
  }

  // MARK: - Titre déplié

  /// Pose le champ du titre sur l'événement le plus ouvert, à la hauteur que son ouverture lui
  /// donne : il grandit d'une ligne à deux avec la ligne.
  private func updateExpandedTitle() {
    let open = expansion.filter { $0.value.value > 0.01 }.max { $0.value.value < $1.value.value }
    guard isInteractive, let open,
      let row = rowLayout().rows.first(where: { $0.event?.id == open.key }),
      let event = row.event
    else {
      if expandedTitleID != nil {
        expandedTitleID = nil
        expandedTitleField.isHidden = true
        needsDisplay = true
      }
      return
    }

    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    let accent = NSColor(cgColor: event.color.cgColor) ?? palette.tabActiveContent
    var color = OverlayPalette.agendaTitleColor(for: accent)
    if case .event(_, true) = row.entry { color = color.withAlphaComponent(0.45) }
    if expandedTitleID != event.id {
      expandedTitleID = event.id
      expandedTitleField.stringValue = displayTitle(of: event)
      needsDisplay = true
    }
    expandedTitleField.textColor = color
    expandedTitleField.isHidden = false

    // Même haut que le titre tracé, pour qu'il ne saute pas quand le champ prend le relais.
    let firstLineY = row.rect.maxY - rowHeight / 2 - 7
    let lines = CGFloat(titleLineCount(of: event) - 1)
    let oneLine = titleLineHeight + 2
    let height = oneLine + lines * titleLineHeight * open.value.value
    // Même ligne de base que l'heure tracée à côté (`draw(at:)` pose le bas de la boîte de la
    // police au point donné), pour que le titre ne saute pas quand le champ prend le relais.
    let baseline = firstLineY - titleFont.descender
    let top = baseline + expandedTitleField.firstBaselineOffsetFromTop
    expandedTitleField.frame = NSRect(
      x: titleX - 2, y: top - height, width: titleWidth + 2, height: height)
  }

  // MARK: - Titres qui défilent

  /// Pose un défilement sur chaque titre coupé d'une ligne repliée et immobile. Rien pendant
  /// qu'une ligne bouge : le défilement suivrait mal un titre qui se déplace.
  private func updateMarquees() {
    updateExpandedTitle()
    let isMoving = entranceStart != nil || expansion.values.contains { !$0.isSettled }
    var targets: [(id: String, rect: NSRect, text: String, color: NSColor)] = []
    if isInteractive, !isMoving, accessCard.isHidden {
      let palette = OverlayPalette.resolved(for: effectiveAppearance)
      for row in rowLayout().rows {
        guard let event = row.event, expansion[event.id] == nil else { continue }
        let title = displayTitle(of: event)
        let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
        guard width > titleWidth else { continue }
        let accent = NSColor(cgColor: event.color.cgColor) ?? palette.tabActiveContent
        var color = OverlayPalette.agendaTitleColor(for: accent)
        if case .event(_, true) = row.entry { color = color.withAlphaComponent(0.45) }
        let firstLineY = row.rect.maxY - rowHeight / 2 - 7
        targets.append(
          (
            event.id,
            // Le champ du défilement décale son texte de 2 pt : on le recule d'autant pour que
            // le titre ne saute pas quand il prend le relais.
            NSRect(x: titleX - 2, y: firstLineY, width: titleWidth + 2, height: titleLineBox),
            title, color
          ))
      }
    }

    while marquees.count < targets.count {
      let overlay = TitleMarqueeOverlay()
      let index = marquees.count
      overlay.onActiveChanged = { [weak self] active in
        guard let self else { return }
        self.marqueeActiveID = active ? self.marqueeEventIDs[index] : nil
        self.needsDisplay = true
      }
      addSubview(overlay, positioned: .below, relativeTo: accessCard)
      marquees.append(overlay)
      marqueeEventIDs.append(nil)
    }

    for (index, overlay) in marquees.enumerated() {
      guard index < targets.count else {
        if marqueeEventIDs[index] != nil {
          overlay.apply(text: "", font: titleFont, color: nil)
          marqueeEventIDs[index] = nil
        }
        overlay.frame = .zero
        continue
      }
      let target = targets[index]
      if marqueeEventIDs[index] != target.id {
        marqueeEventIDs[index] = target.id
        overlay.apply(text: target.text, font: titleFont, color: target.color)
      }
      if overlay.frame != target.rect { overlay.frame = target.rect }
    }
  }
}

private final class ExpandedTitleField: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Valeur au ressort critique (sans rebond), pas à pas : la cible peut changer à tout moment et
/// la valeur repart d'où elle est, à sa vitesse — c'est ce qui rend le dépliage interruptible.
private struct SpringValue {

  var value: CGFloat = 0
  var velocity: CGFloat = 0
  var target: CGFloat = 0

  /// Temps de réponse, en secondes (au sens d'Apple : pas une durée, une raideur).
  private let response: CGFloat = 0.32

  var isSettled: Bool { abs(value - target) < 0.001 && abs(velocity) < 0.01 }

  mutating func step(dt: CGFloat) {
    let omega = 2 * .pi / response
    // Petits pas : l'intégration reste stable même si une image saute.
    let steps = max(1, Int((dt / (1.0 / 240)).rounded(.up)))
    let h = dt / CGFloat(steps)
    for _ in 0..<steps {
      let acceleration = -omega * omega * (value - target) - 2 * omega * velocity
      velocity += acceleration * h
      value += velocity * h
    }
    if isSettled { settle() }
  }

  mutating func settle() {
    value = target
    velocity = 0
  }
}
