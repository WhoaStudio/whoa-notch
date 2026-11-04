import AppKit

/// Contenu de l'onglet AI du panneau de l'encoche : la demande de Claude en attente, ou ce que
/// fait l'agent. Vide tant qu'aucun des deux n'est là.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchUsageTabView: NSView {

    var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
        get { promptCard.onDecision }
        set { promptCard.onDecision = newValue }
    }

    /// Demande de Claude en attente.
    private let promptCard = AgentPromptCardView()
    private var isShowingPrompt = false
    /// Ce que fait l'agent : passe après une demande en attente.
    private let activityCard = AgentActivityCardView()
    private var agentActivity: AgentActivity?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        promptCard.isHidden = true
        activityCard.isHidden = true
        addSubview(activityCard)
        addSubview(promptCard)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - État

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

    /// Une demande ou une activité d'agent s'affiche : la demande d'abord.
    private func refreshTakeover() {
        let showsActivity = !isShowingPrompt && agentActivity != nil
        promptCard.isHidden = !isShowingPrompt
        activityCard.isHidden = !showsActivity
        needsLayout = true
    }

    // MARK: - Mise en page

    override func layout() {
        super.layout()
        promptCard.frame = bounds
        activityCard.frame = bounds
    }
}
