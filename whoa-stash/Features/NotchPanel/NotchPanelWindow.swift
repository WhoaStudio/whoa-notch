import AppKit

/// Fenêtre flottante du panneau de l'encoche, une par écran. Jumelle de `SidePanelWindow` : elle
/// ne prend jamais le focus et n'apparaît pas dans le Dock (l'app est déjà `LSUIElement`). Le
/// survol reste déduit de la position globale du curseur par `NotchPanelController`.
///
/// Elle ne prend les clics que **dépliée**, le temps que ses onglets soient là pour les recevoir.
/// Contrairement à la bande du bord droit, qui n'est à l'écran que révélée, celle-ci y est en
/// permanence : les accepter tout le temps lui ferait avaler, repliée, les clics du haut de
/// l'écran — ceux de la barre de menus comprise.
///
/// Deux choses la distinguent de la bande du bord droit :
///
/// - elle reste **affichée en permanence**, parce que l'état replié se voit : il épouse
///   l'encoche sur les Macs qui en ont une, et prend la forme d'une pastille sur les autres ;
/// - son cadre ne change jamais — il vaut toujours le cadre déplié — et c'est la silhouette
///   dessinée à l'intérieur qui s'anime.
@MainActor
final class NotchPanelWindow {

    private let panel: NSPanel
    private let contentView = NotchPanelContentView()

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Voir `NotchPanelContentView` : l'ombre est portée par le calque du contenu.
        panel.hasShadow = false
        // Repliée, la fenêtre laisse tout passer ; `setExpanded(_:animated:)` ouvre et referme
        // ce robinet. `.nonactivatingPanel` fait que recevoir un clic n'active pas l'app pour
        // autant : celle de devant garde le focus clavier.
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = Self.restingLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = contentView
    }

    var frame: NSRect { panel.frame }
    var isExpanded: Bool { contentView.isExpanded }

    /// Relayé jusqu'au contrôleur, qui ouvre les Préférences — ni la fenêtre ni la vue de contenu
    /// n'ont à connaître `SettingsWindowController`.
    var onOpenSettings: (() -> Void)? {
        get { contentView.onOpenSettings }
        set { contentView.onOpenSettings = newValue }
    }

    var onLaunchAll: (() -> Void)? {
        get { contentView.onLaunchAll }
        set { contentView.onLaunchAll = newValue }
    }

    var canLaunchAll: Bool {
        get { contentView.canLaunchAll }
        set { contentView.canLaunchAll = newValue }
    }

    func apply(clipboardItems: [ClipboardItem]) {
        contentView.apply(clipboardItems: clipboardItems)
    }

    var onClearClipboard: (() -> Void)? {
        get { contentView.onClearClipboard }
        set { contentView.onClearClipboard = newValue }
    }

    var onSelectClipboardItem: ((ClipboardItem) -> Void)? {
        get { contentView.onSelectClipboardItem }
        set { contentView.onSelectClipboardItem = newValue }
    }

    var clipboardImageURL: ((ClipboardItem) -> URL?)? {
        get { contentView.clipboardImageURL }
        set { contentView.clipboardImageURL = newValue }
    }

    func apply(agendaState: CalendarAgendaState) {
        contentView.apply(agendaState: agendaState)
    }

    func apply(usageState: ClaudeUsageState, animated: Bool) {
        contentView.apply(usageState: usageState, animated: animated)
    }

    /// Repeint depuis la palette courante — appelé quand l'accent ou la translucidité change
    /// dans les Préférences, et non quand l'apparence système bascule (AppKit s'en charge).
    func refreshPalette() {
        contentView.refreshOverlayPalette()
    }

    /// Relayé jusqu'au contrôleur, qui relance les deux sources d'utilisation.
    var onRefreshUsage: (() -> Void)? {
        get { contentView.onRefreshUsage }
        set { contentView.onRefreshUsage = newValue }
    }

    func apply(copilotUsageState: CopilotUsageState) {
        contentView.apply(copilotUsageState: copilotUsageState)
    }

    /// Le curseur est-il sur ce que le panneau déplié peint — panneau de l'onglet affiché et
    /// capsule ? Le cadre de la fenêtre est plus haut que les onglets courts : s'y fier laisserait
    /// le panneau déplié sous un curseur qui ne touche plus rien.
    func interactiveFrameContains(_ location: NSPoint) -> Bool {
        contentView.interactiveFrame
            .offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
            .contains(location)
    }

    func showDeviceStatus(_ status: DeviceStatus) {
        contentView.showDeviceStatus(status)
    }

    func hideDeviceStatus() {
        contentView.hideDeviceStatus()
    }

    func showAgentEvent(_ event: AgentEvent) {
        contentView.showAgentEvent(event)
    }

    func hideAgentEvent() {
        contentView.hideAgentEvent()
    }

    var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
        get { contentView.onAgentDecision }
        set { contentView.onAgentDecision = newValue }
    }

    /// La demande que la carte de l'onglet AI affiche ; `nil` la retire.
    func apply(agentPrompt: AgentEvent?) {
        contentView.apply(agentPrompt: agentPrompt)
    }

    /// Ce que fait l'agent ; `nil` retire la carte d'activité.
    func apply(agentActivity: AgentActivity?) {
        contentView.apply(agentActivity: agentActivity)
    }

    func showMailMessage(_ message: MailMessage) {
        contentView.showMailMessage(message)
    }

    func hideMailMessage() {
        contentView.hideMailMessage()
    }

    func showNowPlaying(_ state: NowPlayingState?) {
        contentView.showNowPlaying(state)
    }

    func updateNowPlayingPlayer(_ state: NowPlayingState?) {
        contentView.updateNowPlayingPlayer(state)
    }

    func apply(playingNext items: [QueueItem]) {
        contentView.apply(playingNext: items)
    }

    /// Relayé jusqu'au contrôleur : le panneau vient de se déplier.
    var onExpanded: (() -> Void)? {
        get { contentView.onExpanded }
        set { contentView.onExpanded = newValue }
    }

    /// Relayé jusqu'au contrôleur : boutons de la ligne « en lecture ».
    var onNowPlayingCommand: ((NowPlayingCommand) -> Void)? {
        get { contentView.onNowPlayingCommand }
        set { contentView.onNowPlayingCommand = newValue }
    }

    /// Montre l'onglet Tray — appelé quand un glisser de fichiers arrive sur le panneau, quel
    /// que soit l'onglet affiché jusque-là.
    func revealFileShelf() {
        contentView.select(.tray, animated: true)
    }

    /// Niveau de repos : au-dessus de tout, y compris la barre de menus sous laquelle le panneau
    /// est suspendu.
    private static let restingLevel = NSWindow.Level.screenSaver

    /// Juste **sous** la fenêtre dans laquelle le système dessine le fichier qu'on glisse. Au
    /// niveau de repos, le panneau passe devant elle : on voit le curseur disparaître derrière
    /// l'encoche au moment précis où il faut viser. Reste très au-dessus de la barre de menus
    /// (niveau 24), donc le panneau ne plonge pas sous elle pendant le glisser.
    private static let belowDragImageLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.draggingWindow)) - 1
    )

    /// Prépare (ou non) la fenêtre à recevoir un glisser de fichiers : elle laisse passer devant
    /// elle l'image du fichier glissé, et accepte les événements même repliée — sinon il n'y
    /// aurait rien pour recevoir le dépôt avant qu'elle se déplie.
    func setFileDragActive(_ active: Bool) {
        let level = active ? Self.belowDragImageLevel : Self.restingLevel
        if panel.level != level {
            panel.level = level
        }
        panel.ignoresMouseEvents = active ? false : !isExpanded
    }

    /// Pose la fenêtre sur son écran et l'affiche repliée. Appelé à la construction et à chaque
    /// changement de configuration d'écrans.
    func place(on screen: NSScreen, style: NotchPanelStyle) {
        let frame = NotchPanelGeometry.windowFrame(on: screen, style: style)
        panel.setFrame(frame, display: true)
        contentView.frame = NSRect(origin: .zero, size: frame.size)
        contentView.collapsedSize = NotchPanelGeometry.collapsedSize(on: screen, style: style)
        contentView.collapsedTopGap = NotchPanelGeometry.collapsedTopGap(on: screen, style: style)
        contentView.layoutSubtreeIfNeeded()
        if !isSuppressed { panel.orderFrontRegardless() }
    }

    /// Vrai tant qu'une app est en plein écran sur cet écran : la fenêtre est retirée de l'écran.
    private(set) var isSuppressed = false

    /// Retire la fenêtre (ou la remet) sans toucher à son contenu, pour ne pas couvrir un plein écran.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Choisit l'onglet affiché, hors clic — `--notch-tab=`.
    func select(_ tab: NotchTab) {
        contentView.select(tab, animated: false)
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        if expanded {
            contentView.refreshWeek()
        } else {
            // Le panneau rouvre sur Global — sauf si le bac retient des fichiers : ils doivent
            // être là à la réouverture, pas derrière un clic sur l'onglet. Sans animation, le
            // repli étant déjà en cours.
            if FileShelfStore.shared.isEmpty {
                contentView.select(.global, animated: false)
            }
        }
        // Les onglets ne sont cliquables que dépliés — voir la note en tête de type.
        panel.ignoresMouseEvents = !expanded
        contentView.setExpanded(expanded, animated: animated)
    }

    /// Retrait immédiat : l'écran correspondant vient de disparaître.
    func close() {
        contentView.stopCamera()
        panel.orderOut(nil)
    }
}
