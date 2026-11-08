import AppKit

/// Onglet Analytics, ouvert depuis la pastille d'usage de l'en-tête du panneau, de haut en bas :
/// l'en-tête d'usage (titre, actualiser, onglets des fournisseurs, réglages), la carte du
/// fournisseur choisi, les pastilles de filtre puis la section Activity. Un clic sur un onglet de l'en-tête change le
/// fournisseur que montre la carte.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchAnalyticsTabView: NSView {

  var onRefresh: (() -> Void)? {
    get { header.onRefresh }
    set { header.onRefresh = newValue }
  }

  var onOpenSettings: (() -> Void)? {
    get { header.onOpenSettings }
    set { header.onOpenSettings = newValue }
  }

  /// Demande la lecture des journaux jusqu'au mois `offset` (0 : le mois en cours).
  var onLoadActivity: ((Int) -> Void)?

  /// Jetons et coût du mois en cours, sans filtre : pour la pastille de l'en-tête du panneau.
  /// `nil` tant que les journaux se lisent.
  var onMonthSummaryChanged: ((ActivitySummary?) -> Void)?

  static let activityHeight: CGFloat = 96
  private let sectionGap: CGFloat = 12
  private let pillGap: CGFloat = 8

  private let header = NotchUsageHeaderView()
  private let card = NotchUsageCardView()
  private let monthPill = NotchUsageFilterPillView(title: "Month")
  private let modelPill = NotchUsageFilterPillView(title: "All models")
  private let projectPill = NotchUsageFilterPillView(title: "All projects")
  private var pills: [NotchUsageFilterPillView] { [monthPill, modelPill, projectPill] }
  private let activity = NotchUsageActivityView()

  private var activityRecords: [ActivityRecord] = []
  private var isLoadingActivity = true
  private var filter = ActivityFilter()
  private let calendar = Calendar.current

  private var selectedProvider: NotchUsageProvider = .claude
  private var readings: [NotchUsageProvider: NotchUsageReading] = [
    .claude: .loading(windowLabel: "5H"),
    .codex: .loading(windowLabel: "7D"),
    .copilot: .loading(windowLabel: "MO"),
  ]

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    [header, card, activity].forEach(addSubview)
    pills.forEach(addSubview)

    let menus: [(NotchUsageFilterPillView, () -> NSMenu)] = [
      (monthPill, { [weak self] in self?.monthMenu() ?? NSMenu() }),
      (modelPill, { [weak self] in self?.modelMenu() ?? NSMenu() }),
      (projectPill, { [weak self] in self?.projectMenu() ?? NSMenu() }),
    ]
    for (pill, menu) in menus { pill.makeMenu = menu }
    pills.forEach { $0.onTitleChanged = { [weak self] in self?.needsLayout = true } }

    header.onSelect = { [weak self] provider in
      self?.select(provider, animated: true)
      self?.filterActivity(by: provider)
    }
    for provider in NotchUsageProvider.allCases { refresh(provider) }
    header.select(selectedProvider)
    filterActivity(by: selectedProvider)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - État

  func apply(claude state: ClaudeUsageState) {
    update(.claude, NotchUsageReading.claude(state))
  }

  func apply(codex state: CodexUsageState) {
    update(.codex, NotchUsageReading.codex(state))
  }

  func apply(copilot state: CopilotUsageState) {
    update(.copilot, NotchUsageReading.copilot(state))
  }

  /// Remet le mois à jour et relit les journaux — appelé à chaque dépliage.
  func refreshPeriod() {
    activity.refreshPeriod()
    onLoadActivity?(filter.monthOffset)
  }

  /// Requêtes lues dans les journaux : les mesures et les menus de filtre en sont recalculés.
  func apply(activityRecords records: [ActivityRecord], isLoading: Bool) {
    activityRecords = records
    isLoadingActivity = isLoading
    updateActivity()
  }

  // MARK: - Filtres

  private static let monthTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    return formatter
  }()

  private func monthStart(offset: Int) -> Date {
    ActivityAggregator.month(offset: offset, now: Date(), calendar: calendar).start
  }

  /// Entrée de menu dont l'action est une closure, rangée dans `representedObject`.
  private final class MenuAction {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
  }

  private func menuItem(title: String, isSelected: Bool, handler: @escaping () -> Void)
    -> NSMenuItem
  {
    let item = NSMenuItem(title: title, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = MenuAction(handler)
    item.state = isSelected ? .on : .off
    return item
  }

  @objc private func menuItemChosen(_ item: NSMenuItem) {
    (item.representedObject as? MenuAction)?.run()
  }

  private func monthMenu() -> NSMenu {
    let menu = NSMenu()
    for offset in 0..<6 {
      let title = Self.monthTitleFormatter.string(from: monthStart(offset: offset))
      menu.addItem(
        menuItem(title: title, isSelected: filter.monthOffset == offset) { [weak self] in
          guard let self else { return }
          filter = ActivityFilter(monthOffset: offset, agent: filter.agent)
          onLoadActivity?(offset)
          updateActivity()
        })
    }
    return menu
  }

  /// Le fournisseur choisi dans l'en-tête filtre aussi l'activité. Copilot n'a pas de journaux :
  /// l'activité repasse à tous les agents.
  private func filterActivity(by provider: NotchUsageProvider) {
    setAgentFilter(ActivityAgent.allCases.first { Self.provider(for: $0) == provider })
  }

  private static func provider(for agent: ActivityAgent) -> NotchUsageProvider? {
    switch agent {
    case .claudeCode: .claude
    case .codex: .codex
    }
  }

  private func setAgentFilter(_ agent: ActivityAgent?) {
    // Modèles et projets proposés dépendent de l'agent : on repart de zéro.
    filter = ActivityFilter(monthOffset: filter.monthOffset, agent: agent)
    updateActivity()
  }

  private func modelMenu() -> NSMenu {
    valueMenu(allTitle: "All models", values: options().models, selected: filter.model) {
      $0.filter.model = $1
    }
  }

  private func projectMenu() -> NSMenu {
    valueMenu(allTitle: "All projects", values: options().projects, selected: filter.project) {
      $0.filter.project = $1
    }
  }

  private func valueMenu(
    allTitle: String, values: [String], selected: String?,
    assign: @escaping (NotchAnalyticsTabView, String?) -> Void
  ) -> NSMenu {
    let menu = NSMenu()
    let choices: [(String, String?)] = [(allTitle, nil)] + values.map { ($0, $0) }
    for (title, value) in choices {
      menu.addItem(
        menuItem(title: title, isSelected: selected == value) { [weak self] in
          guard let self else { return }
          assign(self, value)
          updateActivity()
        })
    }
    return menu
  }

  private func options() -> ActivityOptions {
    ActivityAggregator.options(
      records: activityRecords, filter: filter, now: Date(), calendar: calendar)
  }

  /// Recalcule les mesures et le libellé des pastilles à partir des
  /// requêtes déjà lues : changer un filtre ne relit rien.
  private func updateActivity() {
    let isReading = isLoadingActivity && activityRecords.isEmpty
    let now = Date()
    activity.apply(
      summary: isReading
        ? nil
        : ActivityAggregator.summarize(
          records: activityRecords, filter: filter, now: now, calendar: calendar),
      period: monthStart(offset: filter.monthOffset))

    monthPill.title =
      filter.monthOffset == 0
      ? "Month" : Self.monthTitleFormatter.string(from: monthStart(offset: filter.monthOffset))
    modelPill.title = filter.model ?? "All models"
    projectPill.title = filter.project ?? "All projects"

    needsLayout = true

    onMonthSummaryChanged?(
      isReading
        ? nil
        : ActivityAggregator.summarize(
          records: activityRecords, filter: ActivityFilter(), now: now, calendar: calendar))
  }

  private func update(_ provider: NotchUsageProvider, _ reading: NotchUsageReading) {
    guard readings[provider] != reading else { return }
    readings[provider] = reading
    refresh(provider)
  }

  private func refresh(_ provider: NotchUsageProvider) {
    guard let reading = readings[provider] else { return }
    header.apply(reading, for: provider)
    if provider == selectedProvider {
      card.apply(reading, provider: provider)
    }
  }

  private func select(_ provider: NotchUsageProvider, animated: Bool) {
    guard provider != selectedProvider, let reading = readings[provider] else { return }
    selectedProvider = provider
    header.select(provider)

    card.apply(reading, provider: provider)
    if animated { card.layer?.springReveal(x: 8, y: 0) }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()

    var top = bounds.maxY
    header.frame = NSRect(
      x: 0, y: top - NotchUsageHeaderView.height, width: bounds.width,
      height: NotchUsageHeaderView.height)
    top = header.frame.minY - sectionGap

    card.frame = NSRect(
      x: 0, y: top - NotchUsageCardView.height, width: bounds.width,
      height: NotchUsageCardView.height)
    top = card.frame.minY - sectionGap

    var x: CGFloat = 0
    for pill in pills {
      let width = pill.fittingWidth
      pill.frame = NSRect(
        x: x, y: top - NotchUsageFilterPillView.height, width: width,
        height: NotchUsageFilterPillView.height)
      x += width + pillGap
    }
    top -= NotchUsageFilterPillView.height + sectionGap

    activity.frame = NSRect(
      x: 0, y: top - Self.activityHeight, width: bounds.width, height: Self.activityHeight)
  }
}
