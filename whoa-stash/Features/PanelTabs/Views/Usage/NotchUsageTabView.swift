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

    private var selectedProvider: NotchUsageProvider = .claude
    private var readings: [NotchUsageProvider: NotchUsageReading] = [
        .claude: .loading(windowLabel: "5H"),
        .codex: .codex,
        .copilot: .loading(windowLabel: "MO"),
    ]

    private let sectionGap: CGFloat = 12
    private let pillGap: CGFloat = 8

    override init(frame frameRect: NSRect) {
        // TODO: pastilles inertes tant qu'aucune source n'offre de période, d'agents, de modèles
        // ni de projets à filtrer.
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

        header.onSelect = { [weak self] provider in self?.select(provider, animated: true) }
        for provider in NotchUsageProvider.allCases { refresh(provider) }
        header.select(selectedProvider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - État

    func apply(claude state: ClaudeUsageState) {
        update(.claude, NotchUsageReading.claude(state))
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

    /// Remet le mois à jour — appelé à chaque dépliage.
    func refreshPeriod() {
        activity.refreshPeriod()
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
