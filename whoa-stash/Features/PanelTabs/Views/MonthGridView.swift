import AppKit

/// Grille du mois en cours : une ligne d'initiales de jours, puis les semaines. Le jour courant
/// porte la même pastille pleine que dans la bande de la semaine, pour que les deux surfaces se
/// lisent comme une seule.
///
/// Le découpage du mois en cases appartient à `MonthGridLayout` ; cette vue ne fait que le
/// tracer. Dessinée dans `draw(_:)` et non composée de sous-vues : une grille fait jusqu'à
/// quarante-deux cases, et autant de `NSTextField` coûteraient bien plus que le tracé de
/// quelques chaînes qui ne change qu'une fois par jour.
final class MonthGridView: NSView {

  /// Hauteur de la ligne d'initiales, au-dessus des semaines.
  private let headerHeight: CGFloat = 15

  /// Jour affiché comme « aujourd'hui ». Recalculé à chaque reconstruction : le panneau peut
  /// rester en mémoire plusieurs jours sans que l'app redémarre.
  private var referenceDate = Date()

  private let calendar: Calendar = {
    var calendar = Calendar.current
    calendar.firstWeekday = 2
    return calendar
  }()

  /// Le découpage du mois, calculé une fois par jour plutôt qu'à chaque tracé.
  private var layout: MonthGridLayout

  override init(frame frameRect: NSRect) {
    layout = MonthGridLayout(date: referenceDate, calendar: calendar)
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Reconstruit la grille autour de `date`. À appeler avant chaque apparition du panneau :
  /// sans ça, la pastille resterait sur le jour où la grille a été calculée.
  func refresh(now date: Date = Date()) {
    guard !calendar.isDate(date, inSameDayAs: referenceDate) else { return }
    referenceDate = date
    layout = MonthGridLayout(date: date, calendar: calendar)
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    let columnWidth = bounds.width / CGFloat(MonthGridLayout.columnCount)
    let rowHeight = max(1, (bounds.height - headerHeight) / CGFloat(MonthGridLayout.weekRowCount))

    for (column, initial) in layout.weekdayInitials.enumerated() {
      draw(
        initial,
        font: .systemFont(ofSize: 9, weight: .medium),
        color: color(ofColumn: column, palette: palette),
        centeredIn: NSRect(
          x: (columnWidth * CGFloat(column)).rounded(),
          y: bounds.maxY - headerHeight,
          width: columnWidth.rounded(),
          height: headerHeight
        )
      )
    }

    for (index, day) in layout.days.enumerated() {
      guard let day else { continue }

      // Les bornes sont calculées depuis le bord puis arrondies, et non cumulées case après
      // case : un arrondi par case laisserait dériver la dernière colonne.
      let column = index % MonthGridLayout.columnCount
      let row = index / MonthGridLayout.columnCount
      let cell = NSRect(
        x: (columnWidth * CGFloat(column)).rounded(),
        y: (bounds.maxY - headerHeight - rowHeight * CGFloat(row + 1)).rounded(),
        width: columnWidth.rounded(),
        height: rowHeight.rounded()
      )

      let isToday = index == layout.todayIndex
      if isToday {
        let side = min(cell.width, cell.height) - 3
        let pill = NSRect(
          x: cell.midX - side / 2,
          y: cell.midY - side / 2,
          width: side,
          height: side
        )
        NSColor(cgColor: palette.calendarTodayFill)?.setFill()
        NSBezierPath(roundedRect: pill, xRadius: side / 2, yRadius: side / 2).fill()
      }

      draw(
        "\(day)",
        font: .systemFont(ofSize: 11, weight: isToday ? .bold : .regular),
        // Aujourd'hui : numéro blanc sur la pastille rouge. Les autres jours se lisent à
        // la teinte de leur colonne — la semaine ouvrée franche, le week-end en retrait.
        color: isToday ? palette.tabActiveContent : color(ofColumn: column, palette: palette),
        centeredIn: cell
      )
    }
  }

  /// Teinte d'une colonne : le week-end est le seul que la grille distingue, et elle ne le
  /// distingue que par là.
  private func color(ofColumn column: Int, palette: OverlayPalette) -> NSColor {
    let isWeekend =
      layout.isWeekendColumn.indices.contains(column) && layout.isWeekendColumn[column]
    return isWeekend ? palette.calendarWeekendContent : palette.calendarDayContent
  }

  private func draw(_ text: String, font: NSFont, color: NSColor, centeredIn rect: NSRect) {
    let string = NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color]
    )
    let size = string.size()
    string.draw(
      at: NSPoint(
        x: (rect.midX - size.width / 2).rounded(),
        y: (rect.midY - size.height / 2).rounded()
      )
    )
  }
}
