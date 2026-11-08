import AppKit

/// Le widget calendrier de l'onglet Calendar : l'en-tête de date et l'agenda à gauche, la grille
/// du mois à droite, séparés par un filet.
///
/// N'importe pas EventKit et ne connaît pas sa source : il reçoit un `CalendarAgendaState` et
/// l'affiche. C'est tout l'objet de `CalendarAgendaProviding`.
///
/// L'en-tête et la grille ne dépendent que de la date : ils continuent de s'afficher quand
/// l'accès aux calendriers est refusé, et seul l'agenda porte alors un écriteau.
final class CalendarWidgetView: NSView {

  /// Le jour, sa date et son numéro de semaine — « TUE 13 W42 ».
  private let dayLabel = NSTextField(labelWithString: "")

  /// Le mois affiché au-dessus de la grille — « OCT ».
  private let contextLabel = NSTextField(labelWithString: "")

  private let agendaList = AgendaListView()
  private let monthGrid = MonthGridView()
  private let dividerLayer = CALayer()

  /// Jour couvert par l'en-tête. Recalculé à chaque reconstruction, le panneau pouvant rester
  /// en mémoire d'un jour à l'autre.
  private var referenceDate = Date()

  /// L'en-tête tel que le format local l'écrit — « Mon 27 », « 27 oct. ». Gardé à part de la
  /// vue parce que sa teinte se recompose à chaque repeinte : `applyPalette()` doit pouvoir le
  /// réécrire sans redemander la date.
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
      addSubview(field)
    }

    dayLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    contextLabel.font = .systemFont(ofSize: 16, weight: .semibold)

    layer?.addSublayer(dividerLayer)
    addSubview(agendaList)
    addSubview(monthGrid)

    refresh()
    applyPalette()
  }

  // MARK: - État

  func apply(_ state: CalendarAgendaState) {
    agendaList.apply(state, travel: 0)
  }

  /// Remet l'en-tête et la grille à la bonne date. Appelé à chaque dépliage du panneau, comme
  /// `WeekStripView.refresh()` : sans ça, le widget afficherait la date du jour où il a été
  /// construit.
  func refresh(now date: Date = Date()) {
    referenceDate = date
    let week = calendar.component(.weekOfYear, from: date)
    dayText =
      "\(weekdayFormatter.string(from: date).uppercased()) \(calendar.component(.day, from: date)) W\(week)"
    contextLabel.stringValue = monthFormatter.string(from: date).uppercased()

    applyPalette()
    monthGrid.refresh(now: date)
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

    monthGrid.frame = NSRect(
      x: (bounds.maxX - gridWidth).rounded(),
      y: bounds.minY,
      width: gridWidth,
      height: max(
        0,
        bounds.height - dayLabel.intrinsicContentSize.height - NotchPanelGeometry.calendarHeaderGap)
    )

    let leftWidth = max(0, dividerX - gap - bounds.minX)

    let dayHeight = dayLabel.intrinsicContentSize.height
    dayLabel.frame = NSRect(
      x: bounds.minX,
      y: bounds.maxY - dayHeight,
      width: leftWidth,
      height: dayHeight
    )

    let contextHeight = contextLabel.intrinsicContentSize.height
    contextLabel.frame = NSRect(
      x: monthGrid.frame.minX,
      y: bounds.maxY - contextHeight,
      width: gridWidth,
      height: contextHeight
    )

    // L'agenda prend tout ce qui reste sous l'en-tête et décide lui-même combien de lignes y
    // tiennent.
    let agendaTop = dayLabel.frame.minY - NotchPanelGeometry.calendarHeaderGap
    agendaList.frame = NSRect(
      x: bounds.minX,
      y: bounds.minY,
      width: leftWidth,
      height: max(0, agendaTop - bounds.minY)
    )
  }
}
