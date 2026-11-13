import AppKit

/// Contenu de l'onglet AI du panneau de l'encoche : la demande de Claude en attente, ou ce que
/// fait l'agent. Vide tant qu'aucun des deux n'est là.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchUsageTabView: NSView {

  var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
    get { promptCard.onDecision }
    set {
      promptCard.onDecision = newValue
      sessionsView.onDecision = newValue
    }
  }

  /// Le contenu de la demande a changé : hauteur voulue ou champ de texte.
  var onPromptContentChanged: (() -> Void)? {
    get { promptCard.onContentChanged }
    set { promptCard.onContentChanged = newValue }
  }

  /// Hauteur dont la demande affichée a besoin, `nil` quand aucune ne l'est.
  func promptHeight(width: CGFloat) -> CGFloat? {
    isShowingPrompt ? promptCard.fittingHeight(width: width) : nil
  }

  /// Une demande à laquelle on peut répondre est affichée : la fenêtre peut prendre le clavier au clic.
  var showsAnswerablePrompt: Bool {
    (isShowingPrompt && promptCard.isAnswerable) || showsSessions
  }

  /// La liste des sessions est affichée : son champ de consigne peut prendre le clavier au clic.
  private var showsSessions: Bool { !isShowingPrompt && !sessionsView.sessions.isEmpty }

  var onAgentSteer: ((String, String) -> Void)? {
    get { sessionsView.onSteer }
    set { sessionsView.onSteer = newValue }
  }

  var onAgentSessionSelected: ((String) -> Void)? {
    get { sessionsView.onSelect }
    set { sessionsView.onSelect = newValue }
  }

  /// L'action de l'état vide : aller là où on lance un agent.
  var onStartAgent: (() -> Void)? {
    get { sessionsView.onStartAgent }
    set { sessionsView.onStartAgent = newValue }
  }

  /// Ouvre la demande d'une session sur la grande carte.
  var onAgentPromote: ((AgentEvent) -> Void)? {
    get { sessionsView.onPromote }
    set { sessionsView.onPromote = newValue }
  }

  /// Échap sur la carte : replier le panneau.
  var onPromptFoldRequested: (() -> Void)? {
    get { promptCard.onFoldRequested }
    set { promptCard.onFoldRequested = newValue }
  }

  /// Demande de Claude en attente.
  private let promptCard = AgentPromptCardView()
  private var isShowingPrompt = false
  /// Ce que fait l'agent : passe après une demande en attente.
  private let activityCard = AgentActivityCardView()
  /// Les sessions en parallèle : passe après une demande, avant la carte d'activité.
  private let sessionsView = AgentSessionsView()
  private var agentActivity: AgentActivity?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    promptCard.isHidden = true
    activityCard.isHidden = true
    sessionsView.isHidden = true
    addSubview(activityCard)
    addSubview(sessionsView)
    addSubview(promptCard)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - État

  func apply(agentPrompt event: AgentEvent?, queued: Int = 0) {
    if let event { promptCard.apply(event, queued: queued) }
    isShowingPrompt = event != nil
    refreshTakeover()
  }

  func apply(agentActivity: AgentActivity?) {
    self.agentActivity = agentActivity
    if let agentActivity { activityCard.apply(agentActivity) }
    refreshTakeover()
  }

  func apply(agentSessions: [AgentSession], selectedID: String?) {
    sessionsView.apply(sessions: agentSessions, selectedID: selectedID)
    refreshTakeover()
  }

  /// Une demande, les sessions ou une activité d'agent s'affichent, dans cet ordre.
  private func refreshTakeover() {
    let hasSessions = !sessionsView.sessions.isEmpty
    // Sans session ni activité, la vue des sessions montre son état vide.
    let showsActivity = !isShowingPrompt && !hasSessions && agentActivity != nil
    let showsSessions = !isShowingPrompt && !showsActivity
    let revealsPrompt = promptCard.isHidden && isShowingPrompt
    let revealsSessions = sessionsView.isHidden && showsSessions
    let revealsActivity = activityCard.isHidden && showsActivity
    promptCard.isHidden = !isShowingPrompt
    sessionsView.isHidden = !showsSessions
    activityCard.isHidden = !showsActivity
    if revealsPrompt { promptCard.layer?.springReveal() }
    if revealsSessions { sessionsView.layer?.springReveal() }
    if revealsActivity { activityCard.layer?.springReveal() }
    needsLayout = true
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    promptCard.frame = bounds
    activityCard.frame = bounds
    sessionsView.frame = bounds
  }
}
