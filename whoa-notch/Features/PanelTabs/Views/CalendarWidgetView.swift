import AppKit

/// Le widget calendrier de l'onglet Calendar : l'en-tête de date et l'agenda à gauche, la grille
/// du mois à droite, séparés par un filet.
///
/// N'importe pas EventKit et ne connaît pas sa source : il reçoit un `CalendarAgendaState` (le
/// jour même, partagé par tous les panneaux) et lit les autres jours par `dayLoader`. C'est tout
/// l'objet de `CalendarAgendaProviding`.
///
/// Un clic sur un jour de la grille en montre les événements ; l'en-tête suit, et un bouton
/// « Today » ramène au jour même. Chaque dépliage du panneau revient à aujourd'hui.
///
/// L'en-tête et la grille ne dépendent que de la date : ils continuent de s'afficher quand
/// l'accès aux calendriers est refusé, et seul l'agenda porte alors la carte d'accès.
final class CalendarWidgetView: NSView {

  /// Lit les événements d'un jour. Fournie par le contrôleur, qui seul connaît la source.
  var dayLoader: ((Date) async -> CalendarAgendaState)? {
    didSet { loadEventDays(for: monthGrid.displayedMonth) }
  }

  /// Le jour, sa date et son numéro de semaine — « TUE 13 W42 ».
  private let dayLabel = NSTextField(labelWithString: "")

  /// Le mois affiché au-dessus de la grille — « OCT », ou « JAN 2027 » hors de l'année.
  private let contextLabel = NSTextField(labelWithString: "")

  private let todayButton = HomePillButton()
  private let agendaList = AgendaListView()
  private let monthGrid = MonthGridView()
  private let dividerLayer = CALayer()

  /// Air entre le mois et la grille. Serré : l'en-tête de la colonne de droite n'est qu'une
  /// étiquette, la place va aux semaines.
  private let monthToGridGap: CGFloat = 3
  private let todayButtonHeight: CGFloat = 18

  /// Jour couvert par l'en-tête et l'agenda partagé. Recalculé à chaque dépliage, le panneau
  /// pouvant rester en mémoire d'un jour à l'autre.
  private var referenceDate = Date()

  /// Jour choisi dans la grille ; `nil` : aujourd'hui, avec l'agenda partagé (et demain).
  private var selectedDate: Date?

  /// Dernier état partagé reçu, pour revenir à aujourd'hui sans relire.
  private var sharedState: CalendarAgendaState = .loading

  private var dayTask: Task<Void, Never>?
  private var dotsTask: Task<Void, Never>?
  private var dotsLoadedMonths: Set<Date> = []

  /// L'en-tête tel qu'il s'écrit — « TUE 13 W42 ». Gardé à part de la vue parce que sa teinte se
  /// recompose à chaque repeinte : `applyPalette()` doit pouvoir le réécrire sans redemander la
  /// date.
  private var dayText = ""

  private let calendar = Calendar.current

  private let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter
  }()

  private let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM")
    return formatter
  }()

  private let monthYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
    return formatter
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    for field in [dayLabel, contextLabel] {
      field.isBezeled = false
      field.drawsBackground = false
      field.isEditable = false
      field.isSelectable = false
      field.alignment = field === contextLabel ? .right : .left
      field.lineBreakMode = .byTruncatingTail
      field.wantsLayer = true
      addSubview(field)
    }

    dayLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    // Le mois n'est qu'une étiquette au-dessus de la grille : à 16 pt comme le jour, il prenait
    // aux semaines la hauteur qui leur manquait.
    contextLabel.font = .systemFont(ofSize: 11, weight: .semibold)

    layer?.addSublayer(dividerLayer)
    agendaList.isInteractive = true
    // La carte d'accès relit le jour : la lecture passe par le modèle partagé, qui rattrape
    // alors l'accès accordé et repousse l'agenda à tous les panneaux.
    agendaList.onAccessResolved = { [weak self] in self?.reloadAfterAccessChange() }
    addSubview(agendaList)
    addSubview(monthGrid)

    todayButton.title = "Today"
    todayButton.isHidden = true
    todayButton.onClick = { [weak self] in self?.select(nil) }
    addSubview(todayButton)

    monthGrid.onDaySelected = { [weak self] date in self?.select(date) }
    monthGrid.onMonthChanged = { [weak self] month in self?.monthChanged(to: month) }

    refresh()
  }

  // MARK: - État

  func apply(_ state: CalendarAgendaState) {
    let changed = state != sharedState
    sharedState = state
    if selectedDate == nil {
      agendaList.apply(state, travel: 0)
    }
    guard changed else { return }
    // Le magasin a changé : les points des jours et le jour choisi se relisent.
    dotsLoadedMonths.removeAll()
    monthGrid.clearEventDays()
    loadEventDays(for: monthGrid.displayedMonth)
    if selectedDate != nil { loadSelectedDay(travel: nil) }
  }

  /// Revient à aujourd'hui, le mois du jour et une liste repliée. Appelé à chaque dépliage du
  /// panneau, comme `WeekStripView.refresh()` : sans ça, le widget afficherait la date du jour où
  /// il a été construit, ou le dernier jour consulté.
  func refresh(now date: Date = Date()) {
    referenceDate = date
    selectedDate = nil
    dayTask?.cancel()
    monthGrid.refresh(now: date)
    agendaList.collapseAll(animated: false)
    agendaList.apply(sharedState)
    agendaList.playEntrance()
    updateHeading(travel: nil)
    updateMonthLabel(for: monthGrid.displayedMonth, animated: false)
    loadEventDays(for: monthGrid.displayedMonth)
  }

  // MARK: - Jour choisi

  private func select(_ date: Date?) {
    let previous = selectedDate ?? referenceDate
    let isToday = date.map { calendar.isDate($0, inSameDayAs: referenceDate) } ?? true
    let next = isToday ? nil : date.map { calendar.startOfDay(for: $0) }
    guard next != selectedDate else { return }
    selectedDate = next

    // Le contenu arrive du côté où le jour se trouve : un jour plus tard entre par la droite.
    let target = next ?? referenceDate
    let travel: CGFloat = target > previous ? 12 : -12
    agendaList.collapseAll(animated: false)
    monthGrid.select(next ?? referenceDate, animated: true)
    updateHeading(travel: travel)

    if next == nil {
      dayTask?.cancel()
      agendaList.apply(sharedState, travel: travel)
    } else {
      loadSelectedDay(travel: travel)
    }
  }

  private func loadSelectedDay(travel: CGFloat?) {
    guard let date = selectedDate, let dayLoader else { return }
    dayTask?.cancel()
    dayTask = Task { [weak self] in
      let state = await dayLoader(date)
      guard !Task.isCancelled, let self, self.selectedDate == date else { return }
      self.agendaList.apply(state, travel: travel)
    }
  }

  private func reloadAfterAccessChange() {
    guard let dayLoader else { return }
    let date = selectedDate ?? referenceDate
    let selected = selectedDate
    dayTask?.cancel()
    dayTask = Task { [weak self] in
      let state = await dayLoader(date)
      // Sans jour choisi, c'est le modèle partagé qui repousse l'agenda par `apply(_:)`.
      guard !Task.isCancelled, let self, selected != nil, self.selectedDate == selected else {
        return
      }
      self.agendaList.apply(state)
    }
  }

  // MARK: - Mois affiché et points des jours

  private func monthChanged(to month: Date) {
    updateMonthLabel(for: month, animated: true)
    loadEventDays(for: month)
  }

  /// Lit, jour par jour, ceux du mois qui portent un événement, puis ceux des deux mois voisins :
  /// la page qui glisse sous le doigt a alors déjà ses points. La source ne sait lire qu'une
  /// journée à la fois ; une lecture par jour reste bon marché pour EventKit, et n'a lieu qu'une
  /// fois par mois consulté tant que le magasin ne change pas.
  private func loadEventDays(for month: Date) {
    guard let dayLoader, sharedState.agenda != nil else { return }
    let calendar = calendar
    let months = [0, 1, -1].compactMap { calendar.date(byAdding: .month, value: $0, to: month) }
      .filter { !dotsLoadedMonths.contains($0) }
    guard !months.isEmpty else { return }
    dotsTask?.cancel()
    dotsTask = Task { [weak self] in
      for month in months {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { continue }
        var marked: Set<Int> = []
        var complete = true
        for day in days {
          guard let date = calendar.date(byAdding: .day, value: day - 1, to: month) else {
            continue
          }
          let state = await dayLoader(date)
          guard !Task.isCancelled else { return }
          // Une lecture ratée n'est pas un jour vide : le mois sera relu plus tard.
          guard let agenda = state.agenda else {
            complete = false
            continue
          }
          if !agenda.today.isEmpty { marked.insert(day) }
        }
        guard let self else { return }
        if complete { self.dotsLoadedMonths.insert(month) }
        self.monthGrid.setEventDays(marked, forMonth: month)
      }
    }
  }

  // MARK: - En-tête

  private func updateHeading(travel: CGFloat?) {
    let date = selectedDate ?? referenceDate
    let week = calendar.component(.weekOfYear, from: date)
    dayText =
      "\(weekdayFormatter.string(from: date).uppercased()) \(calendar.component(.day, from: date)) W\(week)"
    applyPalette()

    let showsToday = selectedDate != nil
    if showsToday != !todayButton.isHidden {
      todayButton.isHidden = !showsToday
      if showsToday { todayButton.layer?.crossfadeIn(delay: 0.04, duration: 0.18) }
    }
    if let travel { dayLabel.layer?.springReveal(x: travel / 2, y: 0) }
    needsLayout = true
  }

  private func updateMonthLabel(for month: Date, animated: Bool) {
    let sameYear = calendar.isDate(month, equalTo: referenceDate, toGranularity: .year)
    let text = (sameYear ? monthFormatter : monthYearFormatter).string(from: month).uppercased()
    guard text != contextLabel.stringValue else { return }
    contextLabel.stringValue = text
    if animated { contextLabel.layer?.crossfadeIn(delay: 0, duration: 0.18) }
    needsLayout = true
  }

  // MARK: - Palette

  private func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    dayLabel.attributedStringValue = dayHeading(palette: palette)
    contextLabel.textColor = palette.calendarAccent
    dividerLayer.backgroundColor = palette.strokeColor
  }

  /// L'en-tête en deux teintes : le quantième en blanc, le nom du jour en rouge. Le partage se
  /// fait sur les chiffres et non sur un découpage du format, qui ne tiendrait pas d'une langue
  /// à l'autre — « Mon 27 » ici, « 27 oct. » ailleurs, et dans les deux cas c'est le nombre
  /// qu'il faut détacher.
  private func dayHeading(palette: OverlayPalette) -> NSAttributedString {
    let heading = NSMutableAttributedString(
      string: dayText,
      attributes: [.font: dayLabel.font as Any, .foregroundColor: palette.calendarAccent]
    )
    var location = 0
    for character in dayText {
      let length = String(character).utf16.count
      if character.isNumber {
        heading.addAttribute(
          .foregroundColor,
          value: palette.tabActiveContent,
          range: NSRange(location: location, length: length)
        )
      }
      location += length
    }
    return heading
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()

    // La grille est calée à droite, à sa largeur propre ; l'agenda prend tout ce qui reste à
    // gauche. Le filet se pose entre les deux, à égale distance.
    let gridWidth = min(NotchPanelGeometry.monthGridWidth, bounds.width / 2)
    let gap = NotchPanelGeometry.columnGap
    let dividerX = (bounds.maxX - gridWidth - gap - NotchPanelGeometry.dividerWidth).rounded()

    dividerLayer.frame = NSRect(
      x: dividerX,
      y: bounds.minY,
      width: NotchPanelGeometry.dividerWidth,
      height: bounds.height
    )

    let leftWidth = max(0, dividerX - gap - bounds.minX)
    let dayHeight = dayLabel.intrinsicContentSize.height
    let dayY = bounds.maxY - dayHeight

    // Le bouton « Today » se cale à droite de la colonne, centré sur l'en-tête ; le jour garde
    // le reste et se coupe plutôt que de passer dessous.
    let buttonWidth = todayButton.isHidden ? 0 : todayButton.fittingWidth
    todayButton.frame = NSRect(
      x: bounds.minX + leftWidth - buttonWidth,
      y: (dayY + (dayHeight - todayButtonHeight) / 2).rounded(),
      width: buttonWidth,
      height: todayButtonHeight
    )
    dayLabel.frame = NSRect(
      x: bounds.minX,
      y: dayY,
      width: max(0, leftWidth - (buttonWidth > 0 ? buttonWidth + 8 : 0)),
      height: dayHeight
    )

    // Le mois se pose sur la ligne de base du jour, à la taille d'une étiquette. La grille
    // prend tout ce qui reste dessous : c'est ce qu'on lui retirait en la plaçant sous un
    // en-tête de 16 pt et 10 pt d'air, et ses lignes ne contenaient plus la pastille du jour.
    let gridX = (bounds.maxX - gridWidth).rounded()
    let contextHeight = contextLabel.intrinsicContentSize.height
    let dayBaseline = dayY + dayHeight - dayLabel.firstBaselineOffsetFromTop
    let contextY = (dayBaseline - contextHeight + contextLabel.firstBaselineOffsetFromTop).rounded()
    contextLabel.frame = NSRect(
      x: gridX,
      y: contextY,
      width: gridWidth,
      height: contextHeight
    )

    monthGrid.frame = NSRect(
      x: gridX,
      y: bounds.minY,
      width: gridWidth,
      height: max(0, contextY - monthToGridGap - bounds.minY)
    )

    // L'agenda prend tout ce qui reste sous l'en-tête et décide lui-même combien de lignes y
    // tiennent.
    let agendaTop = dayY - NotchPanelGeometry.calendarHeaderGap
    agendaList.frame = NSRect(
      x: bounds.minX,
      y: bounds.minY,
      width: leftWidth,
      height: max(0, agendaTop - bounds.minY)
    )
  }
}
