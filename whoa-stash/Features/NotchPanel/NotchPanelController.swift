import AppKit
import Combine
import os

/// Gère, par écran connecté, le panneau suspendu au haut de l'écran. Replié il épouse l'encoche
/// matérielle — ou prend la forme d'une pastille sur les Macs qui n'en ont pas — et il se déplie
/// quand le curseur entre dans la zone sensible du haut, puis se replie dès qu'il la quitte sans
/// être passé sur le panneau. Reconstruit la liste des fenêtres à chaque changement de
/// configuration d'écrans.
///
/// Même grammaire que `SidePanelController`, qui pilote le placement du bord droit : les deux
/// panneaux coexistent, chacun avec ses fenêtres et sa géométrie.
@MainActor
final class NotchPanelController {

    // Suit aussi le curseur bouton enfoncé : un glisser de fichiers vers l'encoche doit
    // déplier le panneau comme un survol le ferait, sans quoi il n'y aurait rien pour recevoir
    // le dépôt (voir `handleCursor(at:)`).
    private let mouseMonitor = GlobalMouseMonitor(tracksDrags: true)
    private let storage: SettingsStorage
    private let appLauncher = AppLauncher()
    private var launchListCancellable: AnyCancellable?

    /// Indexés par `CGDirectDisplayID` et non par position dans `NSScreen.screens`, qui change
    /// dès qu'un écran est branché ou débranché.
    private var windows: [CGDirectDisplayID: NotchPanelWindow] = [:]
    private var expandedDisplay: CGDirectDisplayID?

    /// Dit si un glisser de fichiers est en cours — voir `isDraggingFiles()`.
    private var dragDetector = FileDragDetector()

    private var screenObserver: NSObjectProtocol?
    private var styleCancellable: AnyCancellable?
    private var notchlessStyle: NotchPanelStyle
    private var enabledCancellable: AnyCancellable?
    private var paletteObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    /// Écrans où une app est en plein écran : leur île est retirée. Mis à jour sur les signaux du
    /// système (changement de Space, app au premier plan, écrans), jamais par sondage.
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    /// Écrans en plein écran où une demande d'agent réaffiche l'île le temps de sa pastille.
    private var revealedDisplays: Set<CGDirectDisplayID> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var fullScreenSettleTask: Task<Void, Never>?

    private var usageState: ClaudeUsageState = .loading
    private var copilotUsageState: CopilotUsageState = .loading

    /// Dernier agenda connu, rejoué sur chaque panneau neuf : il y en a un par écran, et un
    /// écran branché après la première lecture ne doit pas rester sur un widget vide.
    private var agendaState: CalendarAgendaState = .loading
    private var clipboardItems: [ClipboardItem] = []

    var onClearClipboard: (() -> Void)? {
        didSet { windows.values.forEach { $0.onClearClipboard = onClearClipboard } }
    }
    var onSelectClipboardItem: ((ClipboardItem) -> Void)? {
        didSet { windows.values.forEach { $0.onSelectClipboardItem = onSelectClipboardItem } }
    }
    var clipboardImageURL: ((ClipboardItem) -> URL?)? {
        didSet { windows.values.forEach { $0.clipboardImageURL = clipboardImageURL } }
    }
    private var isActive = false

    /// Dernière lecture connue, rejouée sur chaque panneau neuf comme l'agenda.
    private var nowPlayingState: NowPlayingState?
    private var nowPlayingPlayer: NowPlayingState?
    private var playingNext: [QueueItem] = []

    /// Un panneau vient de se déplier — le lecteur en profite pour relire la suite du morceau.
    var onPanelExpanded: (() -> Void)?

    /// Boutons de la ligne « en lecture » ; posé avant ou après la construction des fenêtres.
    var onNowPlayingCommand: ((NowPlayingCommand) -> Void)? {
        didSet { windows.values.forEach { $0.onNowPlayingCommand = onNowPlayingCommand } }
    }

    /// Dépliage forcé, hors survol (`--show-notch-panel`) : le curseur est alors n'importe où,
    /// donc le suivi normal replierait le panneau au premier mouvement. L'épinglage suspend
    /// cette logique jusqu'à ce que l'utilisateur soit venu sur le panneau puis en soit ressorti.
    private var isPinned = false
    private var hasVisitedPinnedPanel = false

    /// Pastille d'appareil Bluetooth : visible `deviceStatusDuration`, puis elle se retire.
    private let deviceStatusDuration: Duration = .seconds(3)
    private var deviceStatusTask: Task<Void, Never>?
    private var deviceStatusDisplay: CGDirectDisplayID?

    /// Notification d'agent IA : visible `agentEventDuration`, puis elle se retire.
    private let agentEventDuration: Duration = .seconds(4)
    private var agentEventTask: Task<Void, Never>?
    private var agentEventDisplay: CGDirectDisplayID?
    /// Réponse donnée depuis l'encoche (Allow, Deny, un choix) : à rendre au hook qui l'attend.
    var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)?

    /// Demandes de Claude sans réponse : l'encoche montre la plus récente, et le survol ouvre l'onglet AI.
    private var agentPrompts = AgentPromptStore()
    /// Une demande dont la session a disparu sans prévenir (processus tué) expire après ce délai.
    private let agentPromptLifetime: Duration = .seconds(600)
    private var agentPromptExpiryTask: Task<Void, Never>?
    /// Ce que fait chaque session ; l'onglet AI montre la plus récente quand aucune demande n'attend.
    private var agentActivities = AgentActivityStore()
    private var agentActivityExpiryTask: Task<Void, Never>?

    /// Courrier arrivé : visible `mailMessageDuration`, puis il se retire.
    private let mailMessageDuration: Duration = .seconds(6)
    private var mailMessageTask: Task<Void, Never>?
    private var mailMessageDisplay: CGDirectDisplayID?

    /// Les moniteurs d'événements ne se déclenchent qu'au mouvement : si le curseur est
    /// téléporté, ou qu'il quitte la zone pendant un changement de Space, plus aucun événement
    /// n'arrive et le panneau resterait déplié. Ce rafraîchissement ne tourne que pendant qu'un
    /// panneau est déplié.
    private let pollInterval: TimeInterval = 0.25

    init(storage: SettingsStorage = .shared) {
        self.storage = storage
        self.notchlessStyle = storage.settings.notchPanel.notchlessStyle
    }

    func activate() {
        // Le réglage décide à lui seul de l'existence des fenêtres : désactivé, le panneau ne
        // doit pas même laisser sa silhouette repliée en haut de l'écran.
        enabledCancellable = storage.$settings
            .map(\.notchPanel.enabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.start() : self?.stop()
            }

        launchListCancellable = storage.$settings
            .map(\.dock.launchApps)
            .removeDuplicates()
            .sink { [weak self] apps in
                self?.windows.values.forEach { $0.canLaunchAll = !apps.isEmpty }
            }

        // La forme sur écran sans encoche se règle à chaud : les fenêtres existantes sont
        // simplement recadrées, sans être reconstruites.
        styleCancellable = storage.$settings
            .map(\.notchPanel.notchlessStyle)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] style in
                // `$settings` publie avant l'écriture : on retient la valeur reçue.
                guard let self else { return }
                self.notchlessStyle = style
                if self.isActive { self.rebuildWindows() }
            }

        // Accent et translucidité ne passent pas par `NSAppearance` : la palette les porte, et
        // c'est à nous de demander la repeinte des fenêtres déjà construites.
        paletteObserver = NotificationCenter.default.addObserver(
            forName: OverlayPalette.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windows.values.forEach { $0.refreshPalette() } }
        }
    }

    private func start() {
        guard !isActive else { return }
        isActive = true

        rebuildWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fullScreenSignalReceived() }
            })
        }
        refreshFullScreen()

        // Aucune permission d'accessibilité requise : seuls les événements clavier et
        // synthétiques en demandent, pas le suivi des déplacements de souris.
        mouseMonitor.onMove = { [weak self] location in
            self?.handleCursor(at: location)
        }
        mouseMonitor.start()
    }

    private func stop() {
        guard isActive else { return }
        isActive = false

        mouseMonitor.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        stopPolling()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        fullScreenSettleTask?.cancel()
        fullScreenSettleTask = nil
        fullScreenDisplays = []
        revealedDisplays = []
        deviceStatusTask?.cancel()
        deviceStatusTask = nil
        deviceStatusDisplay = nil
        agentEventTask?.cancel()
        agentEventTask = nil
        agentEventDisplay = nil
        agentPrompts = AgentPromptStore()
        agentPromptExpiryTask?.cancel()
        agentPromptExpiryTask = nil
        agentActivityExpiryTask?.cancel()
        agentActivityExpiryTask = nil
        agentActivities = AgentActivityStore()
        mailMessageTask?.cancel()
        mailMessageTask = nil
        mailMessageDisplay = nil

        windows.values.forEach { $0.close() }
        windows.removeAll()
        expandedDisplay = nil
        isPinned = false
    }

    /// Diffuse le dernier instantané à toutes les fenêtres, y compris celles qui sont repliées :
    /// elles doivent être déjà à jour au moment où elles se déplient, pas se remplir après coup.
    func apply(agendaState newState: CalendarAgendaState) {
        agendaState = newState
        windows.values.forEach { $0.apply(agendaState: newState) }
    }

    func apply(clipboardItems newItems: [ClipboardItem]) {
        clipboardItems = newItems
        windows.values.forEach { $0.apply(clipboardItems: newItems) }
    }

    /// Relance les sources d'utilisation, depuis le bouton « actualiser » de l'onglet AI.
    var onRefreshUsage: (() -> Void)? {
        didSet { windows.values.forEach { $0.onRefreshUsage = onRefreshUsage } }
    }

    /// Diffuse la lecture en cours (ou `nil`) à toutes les fenêtres : le panneau d'un écran
    /// branché plus tard doit la montrer aussi.
    func apply(nowPlayingState newState: NowPlayingState?) {
        nowPlayingState = newState
        windows.values.forEach { $0.showNowPlaying(newState) }
    }

    /// Dernier morceau connu pour le lecteur de l'onglet Global, qui ne disparaît pas à l'arrêt.
    func apply(nowPlayingPlayer newState: NowPlayingState?) {
        nowPlayingPlayer = newState
        windows.values.forEach { $0.updateNowPlayingPlayer(newState) }
    }

    /// Les prochains titres du morceau en cours, rejoués sur chaque panneau neuf comme le lecteur.
    func apply(playingNext items: [QueueItem]) {
        playingNext = items
        windows.values.forEach { $0.apply(playingNext: items) }
    }

    func apply(copilotUsageState newState: CopilotUsageState) {
        copilotUsageState = newState
        windows.values.forEach { $0.apply(copilotUsageState: newState) }
    }

    func apply(usageState newState: ClaudeUsageState) {
        usageState = newState
        windows.values.forEach { $0.apply(usageState: newState, animated: true) }
    }

    /// Montre la pastille d'un appareil qui vient de se connecter, sur l'écran principal. Une
    /// nouvelle connexion remplace la précédente et relance le délai.
    func showDeviceStatus(_ status: DeviceStatus) {
        guard
            isActive,
            let displayID = NSScreen.main?.displayID ?? NSScreen.screens.first?.displayID,
            let window = windows[displayID],
            !isHiddenByFullScreen(displayID)
        else { return }

        deviceStatusTask?.cancel()
        if let previous = deviceStatusDisplay, previous != displayID {
            windows[previous]?.hideDeviceStatus()
        }
        deviceStatusDisplay = displayID
        window.showDeviceStatus(status)

        deviceStatusTask = Task { [weak self, duration = deviceStatusDuration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            window.hideDeviceStatus()
            self?.deviceStatusDisplay = nil
        }
    }

    /// Montre la notification d'un agent IA sur l'écran principal, avec le son de clic. Une nouvelle
    /// notification remplace la précédente et relance le délai.
    ///
    /// Une demande (permission, question) ne se retire pas d'elle-même : elle reste dans
    /// `agentPrompts` jusqu'à ce que sa session signale autre chose, et la pastille revient après
    /// toute autre notification ou tout repli du panneau.
    func showAgentEvent(_ event: AgentEvent) {
        guard
            isActive,
            let displayID = NSScreen.main?.displayID ?? NSScreen.screens.first?.displayID,
            let window = windows[displayID]
        else { return }

        // La carte d'activité suit chaque événement ; un outil qui démarre n'a pas de pastille.
        if agentActivities.apply(event) {
            windows.values.forEach { $0.apply(agentActivity: agentActivities.current) }
            scheduleAgentActivityExpiry()
        }
        if event.kind == .toolStart { return }

        let previous = agentPrompts.current
        let changed = agentPrompts.apply(event)
        if changed {
            windows.values.forEach { $0.apply(agentPrompt: agentPrompts.current) }
            scheduleAgentPromptExpiry()
        }

        if event.kind.resolvesPrompt {
            // Rien à montrer pour un « clear » ; si la demande affichée vient de partir, on la retire
            // ou on laisse place à la précédente.
            guard changed, previous != agentPrompts.current else { return }
            if let remaining = agentPrompts.current {
                presentAgentEvent(remaining, on: displayID, window: window, sound: false)
            } else {
                dismissAgentEvent(on: displayID, window: window)
            }
            return
        }
        // Une notification de permission qui double la demande détaillée : rien de neuf à montrer.
        if event.prompt != nil, !changed { return }

        // Île retirée par un plein écran : seule une demande en attente (`needsInput`) la
        // réaffiche, le temps de sa pastille ; une fin de session peut attendre.
        if isHiddenByFullScreen(displayID) {
            guard event.kind == .needsInput else { return }
            revealedDisplays.insert(displayID)
            applyFullScreen()
        }
        presentAgentEvent(event, on: displayID, window: window, sound: true)
    }

    private func presentAgentEvent(
        _ event: AgentEvent, on displayID: CGDirectDisplayID, window: NotchPanelWindow, sound: Bool
    ) {
        if sound { ButtonSound.shared.playClick() }
        agentEventTask?.cancel()
        if let previous = agentEventDisplay, previous != displayID {
            windows[previous]?.hideAgentEvent()
        }
        agentEventDisplay = displayID
        window.showAgentEvent(event)

        // Une demande reste affichée ; les autres se retirent, puis la demande en attente revient.
        guard event.prompt == nil else { return }
        agentEventTask = Task { [weak self, duration = agentEventDuration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            if let pending = self.agentPrompts.current {
                self.presentAgentEvent(pending, on: displayID, window: window, sound: false)
            } else {
                self.dismissAgentEvent(on: displayID, window: window)
            }
        }
    }

    /// La demande n'attend plus : elle a reçu sa réponse, ou son hook a été annulé. La pastille
    /// disparaît ou laisse place à la demande précédente.
    func agentPromptEnded(replyID: String) {
        guard agentPrompts.remove(replyID: replyID) else { return }
        windows.values.forEach { $0.apply(agentPrompt: agentPrompts.current) }
        scheduleAgentPromptExpiry()
        guard let displayID = agentEventDisplay, let window = windows[displayID] else { return }
        if let remaining = agentPrompts.current {
            presentAgentEvent(remaining, on: displayID, window: window, sound: false)
        } else {
            dismissAgentEvent(on: displayID, window: window)
        }
    }

    /// Une activité sans nouvelle (session plantée, tour fini) disparaît : on regarde chaque
    /// 30 s, tant qu'il en reste une.
    private func scheduleAgentActivityExpiry() {
        agentActivityExpiryTask?.cancel()
        agentActivityExpiryTask = nil
        guard agentActivities.current != nil else { return }
        agentActivityExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            if self.agentActivities.expire() {
                self.windows.values.forEach { $0.apply(agentActivity: self.agentActivities.current) }
            }
            self.scheduleAgentActivityExpiry()
        }
    }

    private func scheduleAgentPromptExpiry() {
        agentPromptExpiryTask?.cancel()
        agentPromptExpiryTask = nil
        guard agentPrompts.current != nil else { return }
        agentPromptExpiryTask = Task { [weak self, lifetime = agentPromptLifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self else { return }
            let cutoff = Date().addingTimeInterval(-Double(lifetime.components.seconds) + 1)
            guard self.agentPrompts.expire(before: cutoff) else { return self.scheduleAgentPromptExpiry() }
            self.windows.values.forEach { $0.apply(agentPrompt: self.agentPrompts.current) }
            if let displayID = self.agentEventDisplay, let window = self.windows[displayID] {
                if let remaining = self.agentPrompts.current {
                    self.presentAgentEvent(remaining, on: displayID, window: window, sound: false)
                } else {
                    self.dismissAgentEvent(on: displayID, window: window)
                }
            }
            self.scheduleAgentPromptExpiry()
        }
    }

    private func dismissAgentEvent(on displayID: CGDirectDisplayID, window: NotchPanelWindow) {
        agentEventTask?.cancel()
        agentEventTask = nil
        window.hideAgentEvent()
        agentEventDisplay = nil
        revealedDisplays.remove(displayID)
        applyFullScreen()
    }

    /// Montre un courrier arrivé sur l'écran principal, avec le son de clic. Un nouveau courrier
    /// remplace le précédent et relance le délai ; une demande d'agent passe devant (voir
    /// `showAgentEvent`). Sur un écran occupé par une app en plein écran, l'île reste retirée.
    func showMailMessage(_ message: MailMessage) {
        guard
            isActive,
            let displayID = NSScreen.main?.displayID ?? NSScreen.screens.first?.displayID,
            let window = windows[displayID],
            !isHiddenByFullScreen(displayID)
        else { return }

        ButtonSound.shared.playClick()
        mailMessageTask?.cancel()
        if let previous = mailMessageDisplay, previous != displayID {
            windows[previous]?.hideMailMessage()
        }
        mailMessageDisplay = displayID
        window.showMailMessage(message)

        mailMessageTask = Task { [weak self, duration = mailMessageDuration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            window.hideMailMessage()
            self?.mailMessageDisplay = nil
        }
    }

    // MARK: - Plein écran

    private func isHiddenByFullScreen(_ displayID: CGDirectDisplayID) -> Bool {
        fullScreenDisplays.contains(displayID) && !revealedDisplays.contains(displayID)
    }

    /// Le plein écran s'installe après la notification de changement de Space : on relit tout de
    /// suite, puis une fois l'animation passée.
    private func fullScreenSignalReceived() {
        refreshFullScreen()
        fullScreenSettleTask?.cancel()
        fullScreenSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.refreshFullScreen()
        }
    }

    private func refreshFullScreen() {
        var insets: [CGDirectDisplayID: CGFloat] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID { insets[id] = screen.safeAreaInsets.top }
        }
        let updated = FullScreenDetector.fullScreenDisplays(topInsets: insets)
        guard updated != fullScreenDisplays else { return }
        fullScreenDisplays = updated
        revealedDisplays.formIntersection(updated)
        Log.notchPanel.debug("Plein écran sur \(updated.count, privacy: .public) écran(s)")
        applyFullScreen()
    }

    /// Retire ou remet chaque fenêtre selon l'état courant ; replie le panneau d'un écran retiré.
    private func applyFullScreen() {
        for (displayID, window) in windows {
            let hidden = isHiddenByFullScreen(displayID)
            if hidden, expandedDisplay == displayID { collapseActive() }
            window.setSuppressed(hidden)
        }
    }

    /// Onglet demandé par `--notch-tab=<global|calendar|tray|clipboard|mirror|ai>`, `nil` sans le drapeau ou
    /// avec un nom inconnu.
    private static func launchTab(_ arguments: [String] = CommandLine.arguments) -> NotchTab? {
        guard let argument = arguments.first(where: { $0.hasPrefix("--notch-tab=") }) else { return nil }
        let name = argument.dropFirst("--notch-tab=".count)
        return NotchTab.allCases.first { $0.title.lowercased() == name.lowercased() }
    }

    /// Déplie (ou replie) le panneau de l'écran qui contient le curseur — appelé par
    /// `--show-notch-panel`.
    func togglePinnedReveal() {
        guard !isPinned else {
            isPinned = false
            collapseActive()
            return
        }

        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main,
            let displayID = screen.displayID,
            let window = windows[displayID]
        else { return }

        if expandedDisplay != displayID {
            collapseActive()
            expandedDisplay = displayID
        }

        isPinned = true
        hasVisitedPinnedPanel = false
        window.apply(usageState: usageState, animated: false)
        window.apply(copilotUsageState: copilotUsageState)
        window.apply(agendaState: agendaState)
        if let tab = Self.launchTab() { window.select(tab) }
        window.setExpanded(true)
        startPolling()
    }

    // MARK: - Suivi du curseur

    private func handleCursor(at location: NSPoint) {
        // Calculé avant les gardes : le détecteur doit voir chaque relâchement, même quand le
        // suivi est gelé plus bas, sans quoi il garderait un compteur périmé.
        let draggingFiles = isDraggingFiles()

        // Menu contextuel ouvert : le suivi est gelé. Le pointeur descend dans le menu, hors du
        // cadre du panneau, et celui-ci se replierait sous un menu encore ouvert.
        guard !OverlayContextMenu.shared.isPresenting else { return }

        // Un fichier en train d'être sorti du bac : le suivi est gelé pour la même raison. Le
        // curseur emmène le fichier loin du panneau, qui se refermerait sous la main.
        // Le panneau reste en revanche sous l'image du fichier glissé : à son niveau de repos il
        // la masquerait, et on ne verrait plus le fichier au moment de viser la zone AirDrop.
        guard !FileShelfStore.shared.isDraggingOut else {
            windows.values.forEach { $0.setFileDragActive(true) }
            return
        }

        // Tous les écrans, et pas seulement celui du curseur : un glisser traverse les écrans, et
        // le panneau qu'il survolera ensuite doit déjà être prêt à le recevoir.
        windows.values.forEach { $0.setFileDragActive(draggingFiles) }

        // Un seul écran est testé, celui qui contient le curseur : avec plusieurs écrans
        // accolés, les zones sensibles du haut se touchent et tester toutes les zones déplierait
        // le panneau du mauvais écran.
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
            let displayID = screen.displayID,
            let window = windows[displayID]
        else {
            collapseActive()
            return
        }

        // Plein écran sur cet écran : pas de zone sensible, l'île n'est pas là.
        guard !window.isSuppressed else {
            collapseActive()
            return
        }

        let inHotZone = NotchPanelGeometry.hotZone(on: screen, style: notchlessStyle).contains(location)
        // Le panneau reste déplié tant que le curseur est dessus : c'est ce qui permet d'aller
        // lire la carte sans que tout se referme en chemin.
        let overPanel = expandedDisplay == displayID && window.isExpanded && window.interactiveFrameContains(location)

        if isPinned {
            // Le panneau épinglé ne se replie qu'une fois le curseur venu dessus puis reparti —
            // sinon il disparaîtrait avant même que le pointeur l'ait atteint.
            if overPanel {
                hasVisitedPinnedPanel = true
                if draggingFiles { window.revealFileShelf() }
            } else if hasVisitedPinnedPanel {
                isPinned = false
                collapseActive()
            }
            return
        }

        guard inHotZone || overPanel else {
            collapseActive()
            return
        }

        if expandedDisplay != displayID {
            collapseActive()
            expandedDisplay = displayID
        }
        window.apply(usageState: usageState, animated: false)
        window.apply(copilotUsageState: copilotUsageState)
        window.apply(agendaState: agendaState)
        // Une demande attend : le panneau s'ouvre sur l'onglet AI, où elle est lisible. Seulement à
        // l'ouverture, pour ne pas ramener l'onglet à chaque mouvement du curseur.
        if !window.isExpanded, agentPrompts.current != nil { window.select(.ai) }
        window.setExpanded(true)
        startPolling()

        // Le panneau vient de s'ouvrir sous un glisser de fichiers : c'est le bac qu'on veut
        // voir, et c'est lui qui doit être là pour recevoir le dépôt. Le reste du dépôt est au
        // `FileTrayView` de l'onglet Tray — il n'y a pas d'autre cible de dépôt.
        if draggingFiles { window.revealFileShelf() }
    }

    /// Un glisser de fichiers est-il en cours sous le curseur ? Le bouton gauche enfoncé ne
    /// suffit pas — déplacer une fenêtre lèverait le même drapeau —, et le contenu du
    /// presse-papiers de glisser ne suffit pas non plus : il survit au glisser précédent. Voir
    /// `FileDragDetector`, qui exige un changement du presse-papiers pendant le bouton enfoncé.
    private func isDraggingFiles() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return dragDetector.isDragging(
            buttonDown: NSEvent.pressedMouseButtons & 1 != 0,
            changeCount: pasteboard.changeCount,
            carriesFiles: pasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
        )
    }

    private func collapseActive() {
        isPinned = false
        guard let expandedDisplay else { return }
        windows[expandedDisplay]?.setExpanded(false)
        // La demande en attente reprend sa pastille, sans le son.
        if let pending = agentPrompts.current, let window = windows[expandedDisplay] {
            presentAgentEvent(pending, on: expandedDisplay, window: window, sound: false)
        }
        self.expandedDisplay = nil
        stopPolling()
    }

    // MARK: - Écrans

    private func rebuildWindows() {
        var connected: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            connected.insert(displayID)

            let window: NotchPanelWindow
            if let existing = windows[displayID] {
                window = existing
            } else {
                window = NotchPanelWindow()
                // L'engrenage de la capsule ouvre les Préférences. Leur fenêtre active
                // l'app, donc le curseur a quitté le haut de l'écran et le suivi repliera le
                // panneau de lui-même.
                window.onOpenSettings = { SettingsWindowController.shared.show() }
                // La liste est relue au clic : `$settings` publie avant l'écriture.
                window.onLaunchAll = { [weak self] in
                    guard let self else { return }
                    self.appLauncher.launchAll(self.storage.settings.dock.launchApps)
                }
                window.canLaunchAll = !storage.settings.dock.launchApps.isEmpty
                window.apply(usageState: usageState, animated: false)
                window.apply(copilotUsageState: copilotUsageState)
                window.onRefreshUsage = onRefreshUsage
                window.apply(agendaState: agendaState)
                window.onClearClipboard = onClearClipboard
                window.onSelectClipboardItem = onSelectClipboardItem
                window.clipboardImageURL = clipboardImageURL
                window.apply(clipboardItems: clipboardItems)
                window.onNowPlayingCommand = onNowPlayingCommand
                window.showNowPlaying(nowPlayingState)
                window.updateNowPlayingPlayer(nowPlayingPlayer)
                window.apply(playingNext: playingNext)
                window.apply(agentPrompt: agentPrompts.current)
                window.apply(agentActivity: agentActivities.current)
                window.onAgentDecision = { [weak self] event, decision in
                    self?.onAgentDecision?(event, decision)
                    if let id = event.replyID { self?.agentPromptEnded(replyID: id) }
                }
                window.onExpanded = { [weak self] in self?.onPanelExpanded?() }
                windows[displayID] = window
            }

            // Un écran déjà connu a pu changer de taille, de position ou de barre de menus : le
            // panneau est visible en permanence, donc tous sont recadrés, pas seulement l'actif.
            window.place(on: screen, style: notchlessStyle)
        }
        refreshFullScreen()
        applyFullScreen()

        for (displayID, window) in windows where !connected.contains(displayID) {
            window.close()
            windows.removeValue(forKey: displayID)
            if expandedDisplay == displayID {
                expandedDisplay = nil
                stopPolling()
            }
        }
    }

    // MARK: - Rafraîchissement pendant le dépliage

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleCursor(at: NSEvent.mouseLocation) }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
