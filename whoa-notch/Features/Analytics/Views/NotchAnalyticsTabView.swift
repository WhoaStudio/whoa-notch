import AppKit

/// Onglet Analytics, ouvert depuis la pastille d'usage de l'en-tête du panneau, de haut en bas :
/// l'en-tête d'usage (titre, actualiser, onglets des fournisseurs, réglages), la carte du
/// fournisseur choisi, les pastilles de filtre puis la section Activity. Un clic sur un onglet de l'en-tête change le
/// fournisseur que montre la carte.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchAnalyticsTabView: NSView {

  /// Relance la lecture des trois fournisseurs (bouton d'actualisation, « Retry »).
  var onRefresh: (() -> Void)?

  var onOpenSettings: (() -> Void)? {
    get { header.onOpenSettings }
    set { header.onOpenSettings = newValue }
  }

  /// Demande la lecture des journaux jusqu'au mois `offset` (0 : le mois en cours).
  var onLoadActivity: ((Int) -> Void)?

  /// Jetons du mois en cours, sans filtre : pour la pastille de l'en-tête du panneau.
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
  private let compare = NotchUsageCompareView()
  private var isComparing = false
  /// Pour que la sortie en fondu d'un bloc ne cache pas celui qui est revenu entre-temps.
  private var transitionID = 0

  /// Dernière lecture reçue de chaque fournisseur : « Updated 3 min ago » en part.
  private var updatedAt: [NotchUsageProvider: Date] = [:]
  private var isRefreshing = false
  private var awaiting: Set<NotchUsageProvider> = []
  private var refreshStart = Date()
  private var refreshTask: Task<Void, Never>?
  /// L'icône tourne au moins ce temps, pour qu'un clic ne clignote pas, et au plus `refreshCap`.
  private static let refreshMinimum: TimeInterval = 0.6
  private static let refreshCap: TimeInterval = 8

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
    [header, card, activity, compare].forEach(addSubview)
    pills.forEach(addSubview)
    compare.wantsLayer = true
    compare.isHidden = true

    let menus: [(NotchUsageFilterPillView, () -> NSMenu)] = [
      (monthPill, { [weak self] in self?.monthMenu() ?? NSMenu() }),
      (modelPill, { [weak self] in self?.modelMenu() ?? NSMenu() }),
      (projectPill, { [weak self] in self?.projectMenu() ?? NSMenu() }),
    ]
    for (pill, menu) in menus { pill.makeMenu = menu }
    pills.forEach { $0.onTitleChanged = { [weak self] in self?.needsLayout = true } }

    header.onRefresh = { [weak self] in self?.beginRefresh() }
    header.onSelect = { [weak self] provider in self?.choose(provider) }
    card.onRetry = { [weak self] in self?.beginRefresh() }
    card.onToggleCompare = { [weak self] in
      guard let self else { return }
      setComparing(!isComparing, animated: true)
    }
    card.canStep = { [weak self] step in self?.neighbour(step) != nil }
    card.onStep = { [weak self] step in
      guard let self, let provider = neighbour(step) else { return }
      choose(provider, animatesEntry: false)
    }
    compare.onSelect = { [weak self] provider in
      guard let self else { return }
      choose(provider)
      setComparing(false, animated: true)
    }
    activity.onStepMonth = { [weak self] delta in
      guard let self else { return }
      setMonth(offset: filter.monthOffset + delta)
    }
    for provider in NotchUsageProvider.allCases { refresh(provider) }
    header.select(selectedProvider)
    filterActivity(by: selectedProvider)
    // `--usage-compare` : ouvre la comparaison d'emblée, pour la vérifier sans clic.
    if CommandLine.arguments.contains("--usage-compare") { setComparing(true, animated: false) }
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
    // « Resets in … » et « Updated … » vieillissent pendant que le panneau est replié.
    card.refreshClock()
    refreshCompare()
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
    for offset in 0...NotchUsageActivityView.maxMonthOffset {
      let title = Self.monthTitleFormatter.string(from: monthStart(offset: offset))
      menu.addItem(
        menuItem(title: title, isSelected: filter.monthOffset == offset) { [weak self] in
          self?.setMonth(offset: offset)
        })
    }
    return menu
  }

  /// Change de mois (menu ou balayage) : relit les journaux jusque-là et recalcule les mesures.
  private func setMonth(offset: Int) {
    let clamped = max(0, min(NotchUsageActivityView.maxMonthOffset, offset))
    filter = ActivityFilter(monthOffset: clamped, agent: filter.agent)
    onLoadActivity?(clamped)
    updateActivity()
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
    activity.monthOffset = filter.monthOffset
    activity.apply(
      summary: isReading
        ? nil
        : ActivityAggregator.summarize(
          records: activityRecords, filter: filter, now: now, calendar: calendar),
      days: isReading
        ? []
        : ActivityAggregator.dailyTokens(
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
    if case .loaded = reading.status { updatedAt[provider] = Date() }
    awaiting.remove(provider)
    settleRefreshIfDone()
    // Une lecture identique ne change rien, sauf pour l'heure de dernière réception.
    let isLoaded = reading.status == .loaded
    if readings[provider] == reading, !isLoaded { return }
    readings[provider] = reading
    refresh(provider)
  }

  private func refresh(_ provider: NotchUsageProvider) {
    guard let reading = readings[provider] else { return }
    header.apply(reading, for: provider)
    if provider == selectedProvider {
      card.apply(reading, provider: provider, updatedAt: updatedAt[provider])
    }
    refreshCompare()
  }

  private func refreshCompare() {
    compare.apply(readings: readings, current: selectedProvider, updatedAt: updatedAt)
  }

  /// Le fournisseur voisin de celui qui est choisi, dans l'ordre de l'en-tête.
  private func neighbour(_ step: Int) -> NotchUsageProvider? {
    NotchUsageProvider(rawValue: selectedProvider.rawValue + step)
  }

  /// Choisit un fournisseur. Le contenu de la carte arrive du côté où il se trouve dans
  /// l'en-tête, sauf après un balayage : celui-ci l'a déjà fait entrer.
  private func choose(_ provider: NotchUsageProvider, animatesEntry: Bool = true) {
    let direction: CGFloat = provider.rawValue > selectedProvider.rawValue ? 1 : -1
    select(provider, enter: animatesEntry ? direction * 14 : nil)
    filterActivity(by: provider)
  }

  private func select(_ provider: NotchUsageProvider, enter: CGFloat?) {
    guard provider != selectedProvider, let reading = readings[provider] else { return }
    selectedProvider = provider
    header.select(provider)
    card.apply(reading, provider: provider, updatedAt: updatedAt[provider], enter: enter)
    refreshCompare()
  }

  // MARK: - Comparaison

  /// Ouvre ou ferme la comparaison : les fournisseurs en trois lignes prennent la place des
  /// filtres et de l'activité, qui s'effacent en fondu pendant qu'elle monte.
  private func setComparing(_ on: Bool, animated: Bool) {
    guard on != isComparing else { return }
    isComparing = on
    transitionID += 1
    let id = transitionID
    var filters: [NSView] = pills
    filters.append(activity)
    let leaving: [NSView] = on ? filters : [compare]
    let entering: [NSView] = on ? [compare] : filters
    refreshCompare()
    for view in entering {
      view.layer?.removeAnimation(forKey: "fadeOut")
      view.layer?.opacity = 1
      view.isHidden = false
    }
    needsLayout = true
    guard animated, OverlayAnimation.allowsMotion else {
      leaving.forEach { $0.isHidden = true }
      return
    }
    entering.forEach { $0.layer?.springReveal(x: 0, y: -8) }
    for view in leaving { fadeOutAndHide(view, id: id) }
  }

  private func fadeOutAndHide(_ view: NSView, id: Int) {
    guard let layer = view.layer else {
      view.isHidden = true
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self, weak view] in
      guard let self, let view, transitionID == id else { return }
      view.isHidden = true
      view.layer?.removeAnimation(forKey: "fadeOut")
      view.layer?.opacity = 1
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = 0.12
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    layer.add(fade, forKey: "fadeOut")
    CATransaction.commit()
  }

  // MARK: - Actualisation

  /// L'icône tourne jusqu'à ce que les trois fournisseurs aient répondu (au moins 0,6 s, au plus
  /// 8 s : un fournisseur qui garde sa lecture précédente peut ne rien renvoyer).
  private func beginRefresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    refreshStart = Date()
    awaiting = Set(NotchUsageProvider.allCases)
    header.setRefreshing(true)
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.refreshCap))
      guard !Task.isCancelled else { return }
      self?.endRefresh()
    }
    onRefresh?()
  }

  private func settleRefreshIfDone() {
    guard isRefreshing, awaiting.isEmpty else { return }
    let wait = max(0, Self.refreshMinimum - Date().timeIntervalSince(refreshStart))
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(wait))
      guard !Task.isCancelled else { return }
      self?.endRefresh()
    }
  }

  private func endRefresh() {
    isRefreshing = false
    refreshTask?.cancel()
    refreshTask = nil
    awaiting = []
    header.setRefreshing(false)
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

    // Comparaison : prend toute la place sous la carte.
    compare.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, top))

    // Les pastilles gardent leur largeur naturelle ; si leurs titres ne tiennent pas ensemble,
    // les plus larges se tronquent au milieu plutôt que de déborder du panneau.
    var widths = pills.map(\.fittingWidth)
    let minimum: CGFloat = 96
    var overflow = widths.reduce(0, +) + pillGap * CGFloat(widths.count - 1) - bounds.width
    while overflow > 0.5, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }),
      widths[widest] > minimum
    {
      let cut = min(overflow, widths[widest] - minimum)
      widths[widest] -= cut
      overflow -= cut
    }
    var x: CGFloat = 0
    for (pill, width) in zip(pills, widths) {
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
