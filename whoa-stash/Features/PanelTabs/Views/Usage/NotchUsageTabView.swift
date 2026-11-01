import AppKit

/// Contenu de l'onglet AI du panneau de l'encoche, de haut en bas : l'en-tête (titre, actualiser,
/// onglets des fournisseurs, réglages), la carte du fournisseur choisi, les pastilles de filtre
/// et la section Activity. Un clic sur un onglet de l'en-tête change le fournisseur que montre la
/// carte.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchUsageTabView: NSView {

    var onRefresh: (() -> Void)? {
        get { header.onRefresh }
        set { header.onRefresh = newValue }
    }

    var onOpenSettings: (() -> Void)? {
        get { header.onOpenSettings }
        set { header.onOpenSettings = newValue }
    }

    var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
        get { promptCard.onDecision }
        set { promptCard.onDecision = newValue }
    }

    /// Demande la lecture des journaux jusqu'au mois `offset` (0 : le mois en cours).
    var onLoadActivity: ((Int) -> Void)?

    private let header = NotchUsageHeaderView()
    private let card = NotchUsageCardView()
    private let pills: [NotchUsageFilterPillView]
    private let activity = NotchUsageActivityView()
    /// Demande de Claude en attente : remplace la carte, les pastilles et l'activité, le temps qu'elle attend.
    private let promptCard = AgentPromptCardView()
    private var isShowingPrompt = false
    /// Ce que fait l'agent : passe après une demande en attente, avant la carte d'utilisation.
    private let activityCard = AgentActivityCardView()
    private var agentActivity: AgentActivity?

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

    private let sectionGap: CGFloat = 12
    private let pillGap: CGFloat = 8

    override init(frame frameRect: NSRect) {
        pills = ["Month", "All agents", "All models", "All projects"].map {
            NotchUsageFilterPillView(title: $0)
        }
        super.init(frame: frameRect)
        wantsLayer = true
        [header, card, activity].forEach(addSubview)
        pills.forEach(addSubview)
        promptCard.isHidden = true
        activityCard.isHidden = true
        addSubview(activityCard)
        addSubview(promptCard)

        let menus: [() -> NSMenu] = [
            { [weak self] in self?.monthMenu() ?? NSMenu() },
            { [weak self] in self?.agentMenu() ?? NSMenu() },
            { [weak self] in self?.modelMenu() ?? NSMenu() },
            { [weak self] in self?.projectMenu() ?? NSMenu() },
        ]
        for (pill, menu) in zip(pills, menus) {
            pill.makeMenu = menu
            pill.onTitleChanged = { [weak self] in self?.needsLayout = true }
        }

        header.onSelect = { [weak self] provider in self?.select(provider, animated: true) }
        for provider in NotchUsageProvider.allCases { refresh(provider) }
        header.select(selectedProvider)
        updateActivity()
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

    func apply(agentPrompt event: AgentEvent?) {
        if let event { promptCard.apply(event) }
        isShowingPrompt = event != nil
        refreshTakeover()
    }

    func apply(agentActivity: AgentActivity?) {
        self.agentActivity = agentActivity
        if let agentActivity { activityCard.apply(agentActivity) }
        refreshTakeover()
    }

    /// Une demande ou une activité d'agent prend la place de la carte, des pastilles et de l'activité
    /// d'utilisation : la demande d'abord.
    private func refreshTakeover() {
        let showsActivity = !isShowingPrompt && agentActivity != nil
        let takeover = isShowingPrompt || showsActivity
        promptCard.isHidden = !isShowingPrompt
        activityCard.isHidden = !showsActivity
        card.isHidden = takeover
        pills.forEach { $0.isHidden = takeover }
        activity.isHidden = takeover
        needsLayout = true
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

    private func menuItem(title: String, isSelected: Bool, handler: @escaping () -> Void) -> NSMenuItem {
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
            menu.addItem(menuItem(title: title, isSelected: filter.monthOffset == offset) { [weak self] in
                guard let self else { return }
                filter = ActivityFilter(monthOffset: offset, agent: filter.agent)
                onLoadActivity?(offset)
                updateActivity()
            })
        }
        return menu
    }

    private func agentMenu() -> NSMenu {
        let menu = NSMenu()
        let choices: [(String, ActivityAgent?)] = [("All agents", nil)] + ActivityAgent.allCases.map { ($0.title, $0) }
        for (title, agent) in choices {
            menu.addItem(menuItem(title: title, isSelected: filter.agent == agent) { [weak self] in
                guard let self else { return }
                // Modèles et projets proposés dépendent de l'agent : on repart de zéro.
                filter = ActivityFilter(monthOffset: filter.monthOffset, agent: agent)
                updateActivity()
            })
        }
        return menu
    }

    private func modelMenu() -> NSMenu {
        valueMenu(allTitle: "All models", values: options().models, selected: filter.model) { $0.filter.model = $1 }
    }

    private func projectMenu() -> NSMenu {
        valueMenu(allTitle: "All projects", values: options().projects, selected: filter.project) { $0.filter.project = $1 }
    }

    private func valueMenu(
        allTitle: String, values: [String], selected: String?,
        assign: @escaping (NotchUsageTabView, String?) -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        let choices: [(String, String?)] = [(allTitle, nil)] + values.map { ($0, $0) }
        for (title, value) in choices {
            menu.addItem(menuItem(title: title, isSelected: selected == value) { [weak self] in
                guard let self else { return }
                assign(self, value)
                updateActivity()
            })
        }
        return menu
    }

    private func options() -> ActivityOptions {
        ActivityAggregator.options(records: activityRecords, filter: filter, now: Date(), calendar: calendar)
    }

    /// Recalcule les mesures et le libellé des pastilles à partir des requêtes déjà lues : changer
    /// un filtre ne relit rien.
    private func updateActivity() {
        let summary = isLoadingActivity && activityRecords.isEmpty
            ? nil
            : ActivityAggregator.summarize(records: activityRecords, filter: filter, now: Date(), calendar: calendar)
        activity.apply(summary: summary, period: monthStart(offset: filter.monthOffset))

        pills[0].title = filter.monthOffset == 0
            ? "Month" : Self.monthTitleFormatter.string(from: monthStart(offset: filter.monthOffset))
        pills[1].title = filter.agent?.title ?? "All agents"
        pills[2].title = filter.model ?? "All models"
        pills[3].title = filter.project ?? "All projects"
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

        if animated, OverlayAnimation.isEnabled {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = PanelFold.fadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.layer?.add(fade, forKey: "provider")
        }
        card.apply(reading, provider: provider)
    }

    // MARK: - Mise en page

    override func layout() {
        super.layout()

        var top = bounds.maxY
        header.frame = NSRect(
            x: 0, y: top - NotchUsageHeaderView.height, width: bounds.width,
            height: NotchUsageHeaderView.height)
        top = header.frame.minY - sectionGap

        card.frame = NSRect(x: 0, y: top - NotchUsageCardView.height, width: bounds.width, height: NotchUsageCardView.height)
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

        if isShowingPrompt || agentActivity != nil {
            let cardTop = header.frame.minY - sectionGap
            let takeover = NSRect(x: 0, y: bounds.minY, width: bounds.width, height: max(0, cardTop - bounds.minY))
            promptCard.frame = takeover
            activityCard.frame = takeover
        }

        activity.frame = NSRect(x: 0, y: bounds.minY, width: bounds.width, height: max(0, top - bounds.minY))
    }
}
