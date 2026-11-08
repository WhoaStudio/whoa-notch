import AppKit

/// La rangée du haut de l'onglet Global : la bande de la semaine sur ~60 % de la largeur, un
/// filet, puis les événements du jour choisi sur le reste.
///
/// La liste est `AgendaListView`, la même que celle de l'onglet Calendar : seule la source
/// change. Elle reçoit un état réduit au jour choisi (`showingFirstDayOnly`), donc « No events »
/// et les écriteaux d'accès viennent d'elle.
final class WeekAgendaRowView: NSView {

  private static let stripShare: CGFloat = 0.6

  private let strip = WeekStripView()
  private let agendaList = AgendaListView()
  private let dividerLayer = CALayer()

  /// Lit les événements d'un jour. Fournie par le contrôleur, qui seul connaît la source.
  var dayLoader: ((Date) async -> CalendarAgendaState)? {
    didSet { reloadSelectedDay() }
  }

  /// Dernière lecture demandée : une réponse lente pour un jour déjà quitté est jetée plutôt
  /// que de repeindre la liste avec le mauvais jour.
  private var displayedDate: Date?
  private var loadTask: Task<Void, Never>?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    layer?.addSublayer(dividerLayer)
    addSubview(strip)
    addSubview(agendaList)

    strip.onSelectionChanged = { [weak self] _ in self?.reloadSelectedDay() }
    agendaList.apply(.loading)
    applyPalette()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Remet la bande à la bonne date et relit le jour choisi : le calendrier a pu changer
  /// depuis le dernier dépliage.
  func refresh() {
    strip.refresh()
    reloadSelectedDay()
  }

  func reloadSelectedDay() {
    guard let dayLoader else { return }
    let date = strip.selectedDate
    loadTask?.cancel()
    loadTask = Task { [weak self] in
      let state = await dayLoader(date)
      guard !Task.isCancelled, let self else { return }
      let travel: CGFloat? =
        if let previous = self.displayedDate, previous != date {
          date > previous ? 12 : -12
        } else {
          nil
        }
      self.displayedDate = date
      self.agendaList.apply(state, travel: travel)
    }
  }

  private func applyPalette() {
    dividerLayer.backgroundColor = OverlayPalette.resolved(for: effectiveAppearance).strokeColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  override func layout() {
    super.layout()

    // Même filet que dans l'onglet Calendar : `columnGap` de part et d'autre.
    let gap = NotchPanelGeometry.columnGap
    let dividerWidth = NotchPanelGeometry.dividerWidth
    let dividerX = (bounds.minX + bounds.width * Self.stripShare).rounded()

    strip.frame = NSRect(
      x: bounds.minX,
      y: bounds.minY,
      width: max(0, dividerX - gap - bounds.minX),
      height: bounds.height
    )
    dividerLayer.frame = NSRect(
      x: dividerX, y: bounds.minY, width: dividerWidth, height: bounds.height)

    let listX = dividerX + dividerWidth + gap
    agendaList.frame = NSRect(
      x: listX,
      y: bounds.minY,
      width: max(0, bounds.maxX - listX),
      height: bounds.height
    )
  }
}
