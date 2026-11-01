import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Racine de composition : une seule instance de `SettingsStorage` traverse toute l'app.
    /// C'est volontairement `.shared` et non une instance neuve — `SettingsWindowController`
    /// lit encore le singleton, et deux instances distinctes scinderaient silencieusement
    /// l'état des préférences entre la fenêtre de réglages et les widgets.
    private let settings = SettingsStorage.shared

    private var statusBarController: StatusBarController?
    private var edgeSliderController: EdgeSliderController?
    private var brightnessOverlayController: BrightnessOverlayController?
    private var volumeDialController: VolumeDialController?
    private var sidePanelController: SidePanelController?
    private var notchPanelController: NotchPanelController?
    private var clipboardHistoryViewModel: ClipboardHistoryViewModel?
    private var deviceStatusCoordinator: DeviceStatusCoordinator?
    private var nowPlayingViewModel: NowPlayingViewModel?
    private var playingNextViewModel: PlayingNextViewModel?
    private var claudeUsageViewModel: ClaudeUsageViewModel?
    private var copilotUsageViewModel: CopilotUsageViewModel?
    private var calendarAgendaViewModel: CalendarAgendaViewModel?
    private var codexUsageViewModel: CodexUsageViewModel?
    private var agentActivityViewModel: AgentActivityViewModel?
    private var overlayPaletteSettings: OverlayPaletteSettings?
    private var shortcutCancellable: AnyCancellable?
    private var knockController: KnockController?
    private var radialMenuController: RadialMenuController?
    private var radialMenuCancellable: AnyCancellable?
    private var knockCancellable: AnyCancellable?
    private var dockController: DockController?
    private var dockModel: DockModel?
    private var runningAppsProvider: RunningAppsProviding?
    private var systemDockService: SystemDockService?
    private var dockCancellables: Set<AnyCancellable> = []
    private let agentHookServer = AgentHookServer()
    private var claudeDesktopWatcher: ClaudeDesktopWatcher?
    private var mailCoordinator: MailNotificationCoordinator?
    private var mailCancellable: AnyCancellable?

    /// Vrai quand le processus est l'hôte d'un bundle de tests unitaires. Les tests sont
    /// *hosted* (`TEST_HOST`), donc l'app démarre pour de bon avant qu'ils ne tournent : sans
    /// ce garde-fou, une simple passe de tests brancherait les moniteurs de souris globaux,
    /// piloterait la luminosité par DDC et lirait le trousseau. On s'arrête donc avant toute
    /// composition — les tests n'ont besoin que des types, pas de l'app en marche.
    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnitTests else { return }

        // L'app est sombre et ne suit pas l'apparence système : replié, le panneau de l'encoche
        // doit se confondre avec le noir matériel de l'encoche, qu'une palette claire trahirait
        // immédiatement, et les autres surfaces de l'overlay sont dessinées pour aller avec.
        // Posée ici, avant la moindre fenêtre, elle est héritée par tous les panneaux comme par
        // les menus et les alertes : c'est le seul endroit qui décide de l'apparence.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Avant toute fenêtre : les vues de l'overlay résolvent la palette dès leur
        // construction, donc accent, translucidité et interrupteur d'animation doivent déjà
        // porter les valeurs de l'utilisateur.
        overlayPaletteSettings = OverlayPaletteSettings(storage: settings)

        // Son « pop » sur tous les boutons de l'app
        ButtonSound.shared.startClickMonitoring()

        // Icône dans la menu bar (en haut à droite de l'écran)
        statusBarController = StatusBarController()

        // Fenêtre flottante invisible qui gère le slider sur le bord de l'écran
        edgeSliderController = EdgeSliderController(storage: settings)
        edgeSliderController?.activate()

        // Overlay de luminosité sur le bord gauche de l'écran.
        // Remplacer par `FakeBrightnessService()` pour développer sans piloter l'écran réel.
        brightnessOverlayController = BrightnessOverlayController(
            controller: SystemBrightnessService(),
            storage: settings
        )
        brightnessOverlayController?.activate()

        // Cadran de volume : jaillit du curseur quand celui-ci entre dans le coin supérieur
        // gauche, et règle le volume de sortie à la molette. Il n'a pas de réglage dans les
        // Préférences — rien à lui passer, donc, que le fait de démarrer.
        volumeDialController = VolumeDialController()
        volumeDialController?.activate()

        // Panneau latéral : glisse depuis le bord droit quand le curseur entre dans la zone
        // sensible du coin supérieur droit, sur chacun des écrans connectés.
        sidePanelController = SidePanelController(storage: settings)
        sidePanelController?.activate()

        // Panneau de l'encoche : suspendu au haut de l'écran, replié sur l'encoche matérielle
        // (ou sur une pastille quand il n'y en a pas), il se déplie au survol. Placement
        // indépendant de la bande du bord droit, que le réglage Général permet de couper.
        notchPanelController = NotchPanelController(storage: settings)
        notchPanelController?.activate()

        // Pastille d'état d'un appareil audio Bluetooth qui se connecte, affichée sous l'encoche.
        // `--simulate-bluetooth-device=airpodsmax,82` en simule un (voir `DeviceStatus`).
        let deviceCoordinator = DeviceStatusCoordinator()
        deviceCoordinator.onStatus = { [weak self] status in
            self?.notchPanelController?.showDeviceStatus(status)
        }
        deviceCoordinator.activate()
        deviceStatusCoordinator = deviceCoordinator

        // Lecture en cours (navigateur, Spotify, Musique) : mêmes ailes que la pastille Bluetooth,
        // tenues tant que ça joue. `--now-playing=playing|paused` en simule une.
        let nowPlaying = NowPlayingViewModel(
            provider: MockNowPlayingProvider.fromLaunchArguments() ?? MediaRemoteNowPlayingProvider())
        nowPlaying.onStateChanged = { [weak self] state in
            self?.notchPanelController?.apply(nowPlayingState: state)
        }
        // Colonne « Playing Next » : Apple Musique (AppleScript) et Spotify (API web) savent donner la
        // suite, MediaRemote non. `--playing-next=mock` en simule une (voir `MockPlayingNextProvider`).
        let nextProviders: [any PlayingNextProviding] =
            MockPlayingNextProvider.fromLaunchArguments().map { [$0] } ?? [
                AppleMusicQueueProvider(),
                SpotifyQueueProvider(clientID: { SettingsStorage.shared.settings.spotify.clientID }),
            ]
        let playingNext = PlayingNextViewModel(providers: nextProviders)
        playingNext.onItemsChanged = { [weak self] items in
            self?.notchPanelController?.apply(playingNext: items)
        }
        notchPanelController?.onPanelExpanded = { [weak playingNext] in playingNext?.refresh() }
        playingNextViewModel = playingNext

        nowPlaying.onPlayerChanged = { [weak self] state in
            self?.notchPanelController?.apply(nowPlayingPlayer: state)
            self?.playingNextViewModel?.update(for: state)
        }
        notchPanelController?.onNowPlayingCommand = { [weak nowPlaying] command in
            nowPlaying?.send(command)
        }
        nowPlaying.activate()
        nowPlayingViewModel = nowPlaying

        // Historique du presse-papiers, affiché dans l'onglet Clipboard de l'encoche.
        // `--clipboard-history=sample` substitue quelques copies fixes à la vraie source.
        let clipboard = ClipboardHistoryViewModel(
            provider: MockClipboardProvider.fromLaunchArguments() ?? PasteboardClipboardProvider(),
            store: MockClipboardProvider.fromLaunchArguments() != nil
                ? ClipboardHistoryStore(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("whoa-stash-clipboard-sample"))
                : ClipboardHistoryStore())
        clipboard.onStateChanged = { [weak self] items in
            self?.notchPanelController?.apply(clipboardItems: items)
        }
        notchPanelController?.onClearClipboard = { [weak clipboard] in clipboard?.clear() }
        notchPanelController?.onSelectClipboardItem = { [weak clipboard] item in clipboard?.recopy(item) }
        notchPanelController?.clipboardImageURL = { [weak clipboard] item in clipboard?.store.imageURL(for: item) }
        clipboard.activate()
        clipboardHistoryViewModel = clipboard

        // Détection de coups sur le châssis par l'accéléromètre : une action par motif (simple,
        // double), réglée dans les Préférences. `--knock=single|double` en simule un (voir
        // `MockKnockSensor`).
        let knock = KnockController(sensor: MockKnockSensor.fromLaunchArguments() ?? SPUAccelerometerSensor())
        knock.onNowPlayingCommand = { [weak nowPlaying] command in nowPlaying?.send(command) }
        knockController = knock
        knockCancellable = settings.$settings
            .map(\.knock)
            .removeDuplicates()
            .sink { [weak knock] in knock?.apply(settings: $0) }

        // Notifications d'agents IA dans l'encoche : hooks Claude Code reçus sur un socket local, et
        // veille optionnelle de Claude Desktop. `--agent-event=stop|notify[,projet]` en simule une.
        let showAgentEvent: @MainActor (AgentEvent) -> Void = { [weak self] in
            self?.notchPanelController?.showAgentEvent($0)
        }
        agentHookServer.onEvent = showAgentEvent
        agentHookServer.onCancel = { [weak self] in self?.notchPanelController?.agentPromptEnded(replyID: $0) }
        notchPanelController?.onAgentDecision = { [weak self] event, decision in
            guard let id = event.replyID, let json = event.replyJSON(for: decision) else { return }
            self?.agentHookServer.reply(to: id, json: json)
        }
        agentHookServer.start()
        let desktopWatcher = ClaudeDesktopWatcher()
        desktopWatcher.onEvent = showAgentEvent
        desktopWatcher.bind(to: settings)
        claudeDesktopWatcher = desktopWatcher
        if let simulated = AgentEvent.fromLaunchArguments() {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                showAgentEvent(simulated)
            }
        }

        // Courrier entrant dans l'encoche : compte IMAP des Préférences ▸ Mail, derrière `MailSource`.
        // `--mail=sample` substitue un message fixe.
        let mail = MailNotificationCoordinator()
        mail.onMessage = { [weak self] in self?.notchPanelController?.showMailMessage($0) }
        if let mock = MockMailSource.fromLaunchArguments() { mail.start(mock, name: "mock") }
        mailCoordinator = mail
        mailCancellable = settings.$settings
            .map(\.mail)
            .removeDuplicates()
            .sink { [weak mail] in mail?.apply(settings: $0) }

        // Menu radial : un bouton de souris maintenu l'ouvre sous le curseur ; les éléments choisis
        // dans les Préférences s'appliquent à chaud.
        let radialMenu = RadialMenuController()
        radialMenu.activate()
        radialMenuController = radialMenu
        radialMenuCancellable = settings.$settings
            .map(\.radialMenu)
            .removeDuplicates()
            .sink { [weak radialMenu] in radialMenu?.apply(settings: $0) }

        // Dock personnalisé : une seule fenêtre, alimentée par un seul modèle (épingles copiées une
        // fois de `com.apple.dock`, applis lancées suivies par `NSWorkspace`). `--dock=sample`
        // substitue des applis lancées fixes.
        let pinnedStore = PinnedAppsStore(storage: settings)
        pinnedStore.seedIfNeeded()
        WorkspaceSeeder.seedIfNeeded(settings)
        let dockModel = DockModel()
        let dock = DockController(
            readAppearance: { [settings] in
                DockAppearance.read(from: SystemDockDefaults(), saved: settings.settings.dock.savedSystemDock)
            },
            onTogglePin: { [settings] item in
                settings.settings.dock.togglePin(DockPinnedApp(bundleID: item.bundleID, path: item.path))
            },
            onSelectWorkspace: { [settings] in settings.settings.dock.activeWorkspaceID = $0 },
            onPlaceApp: { [settings] app, index in settings.settings.dock.placeApp(app, at: index) },
            onRemoveApp: { [settings] item in settings.settings.dock.unpinApp(bundleID: item.bundleID) },
            onWidgetsChanged: { [settings] in settings.settings.dock.setVisibleWidgets($0) })
        dockModel.onStateChanged = { [weak dock] in dock?.apply(state: $0) }
        let runningProvider: RunningAppsProviding =
            MockRunningAppsProvider.fromLaunchArguments() ?? WorkspaceRunningAppsProvider()
        runningProvider.onChange = { [weak dockModel] in dockModel?.setRunning($0) }
        dock.activate()
        dockModel.setPinned(settings.settings.dock.visibleApps)
        dock.apply(workspaces: settings.settings.dock.workspaces, activeID: settings.settings.dock.activeWorkspaceID)
        dock.apply(widgets: settings.settings.dock.visibleWidgets)
        settings.$settings.map(\.dock.visibleWidgets).removeDuplicates()
            .sink { [weak dock] in dock?.apply(widgets: $0) }.store(in: &dockCancellables)
        runningProvider.activate()
        settings.$settings.map(\.dock.visibleApps).removeDuplicates()
            .sink { [weak dockModel] in dockModel?.setPinned($0) }.store(in: &dockCancellables)
        settings.$settings.map(\.dock.enabled).removeDuplicates()
            .sink { [weak dock] in dock?.apply(enabled: $0) }.store(in: &dockCancellables)
        settings.$settings.map { DockWorkspaceState(list: $0.dock.workspaces, activeID: $0.dock.activeWorkspaceID) }
            .removeDuplicates()
            .sink { [weak dock] in dock?.apply(workspaces: $0.list, activeID: $0.activeID) }.store(in: &dockCancellables)
        settings.$settings.map(\.dock.autoHide).removeDuplicates()
            .sink { [weak dock] in dock?.apply(autoHide: $0) }.store(in: &dockCancellables)
        // Raccourci du dock : montre/cache le dock en basculant « Show dock ».
        GlobalShortcutService.dock.onTrigger = { [settings] in settings.settings.dock.enabled.toggle() }
        settings.$settings.map(\.dock.toggleHotkey).removeDuplicates()
            .sink { GlobalShortcutService.dock.apply(keyCode: $0.keyCode, modifiers: $0.modifiers, name: $0.keyLabel) }
            .store(in: &dockCancellables)
        let systemDock = SystemDockService(storage: settings)
        settings.$settings.map(\.dock.hideSystemDock).removeDuplicates()
            .sink { [weak systemDock] in systemDock?.sync(hidden: $0) }.store(in: &dockCancellables)
        self.dockModel = dockModel
        dockController = dock
        runningAppsProvider = runningProvider
        systemDockService = systemDock

        // Raccourci global : même geste que le survol de l'encoche, au clavier. Branché après le
        // contrôleur, qui est sa cible, et réappliqué à chaque changement du réglage.
        GlobalShortcutService.shared.onTrigger = { [weak self] in
            self?.notchPanelController?.togglePinnedReveal()
        }
        shortcutCancellable = settings.$settings
            .map(\.general.togglePanelShortcut)
            .removeDuplicates()
            .sink { GlobalShortcutService.shared.apply($0) }

        // Utilisation Claude : le modèle de vue alimente la bande latérale, et un seul appel
        // réseau la sert.
        // `--claude-usage=73,7` substitue des valeurs fixes à la vraie source (voir
        // `MockClaudeUsageProvider`), pour développer et vérifier sans réseau ni trousseau.
        let usageProvider: ClaudeUsageProviding = MockClaudeUsageProvider.fromLaunchArguments() ?? ClaudeUsageService()
        let usageViewModel = ClaudeUsageViewModel(provider: usageProvider)
        claudeUsageViewModel = usageViewModel

        usageViewModel.onStateChanged = { [weak self] in
            guard let self, let state = self.claudeUsageViewModel?.state else { return }
            self.sidePanelController?.apply(usageState: state)
            self.notchPanelController?.apply(usageState: state)
        }

        usageViewModel.activate()

        let copilotProvider: CopilotUsageProviding =
            MockCopilotUsageProvider.fromLaunchArguments() ?? CopilotUsageService()
        let copilotViewModel = CopilotUsageViewModel(provider: copilotProvider)
        copilotUsageViewModel = copilotViewModel

        copilotViewModel.onStateChanged = { [weak self] in
            guard let self, let state = self.copilotUsageViewModel?.state else { return }
            self.sidePanelController?.apply(copilotUsageState: state)
            self.notchPanelController?.apply(copilotUsageState: state)
        }

        copilotViewModel.activate()

        notchPanelController?.onRefreshUsage = { [weak self] in
            self?.claudeUsageViewModel?.refresh()
            self?.copilotUsageViewModel?.refresh()
        }

        // Agenda du jour : une seule lecture des calendriers alimente tous les panneaux, il y en
        // a un par écran.
        // `--calendar-agenda=denied` substitue une journée fixe à la vraie source (voir
        // `MockCalendarAgendaProvider`), pour atteindre l'écriteau d'accès refusé sans révoquer
        // l'autorisation de l'app dans les Réglages Système.
        let calendarProvider: CalendarAgendaProviding =
            MockCalendarAgendaProvider.fromLaunchArguments() ?? EventKitCalendarService()
        let calendarViewModel = CalendarAgendaViewModel(provider: calendarProvider)
        calendarAgendaViewModel = calendarViewModel

        calendarViewModel.onStateChanged = { [weak self] in
        let codexProvider: CodexUsageProviding = MockCodexUsageProvider.fromLaunchArguments() ?? CodexUsageService()
        let codexViewModel = CodexUsageViewModel(provider: codexProvider)
        codexUsageViewModel = codexViewModel

        codexViewModel.onStateChanged = { [weak self] in
            guard let self, let state = self.codexUsageViewModel?.state else { return }
            self.notchPanelController?.apply(codexUsageState: state)
        }

        codexViewModel.activate()

        // Activité des agents : un seul modèle lit les journaux pour tous les panneaux ; les
        // filtres se recalculent dans la vue, sans relire.
        let activityProvider: AgentActivityProviding =
            MockAgentActivityProvider.fromLaunchArguments() ?? LocalAgentActivityService()
        let activityViewModel = AgentActivityViewModel(provider: activityProvider)
        agentActivityViewModel = activityViewModel
        activityViewModel.onChanged = { [weak self] in
            guard let self, let model = self.agentActivityViewModel else { return }
            self.notchPanelController?.apply(activityRecords: model.records, isLoading: model.isLoading)
        }
        notchPanelController?.onLoadActivity = { [weak self] offset in
            self?.agentActivityViewModel?.load(monthOffset: offset)
        }
        activityViewModel.load()

            guard let self, let state = self.calendarAgendaViewModel?.state else { return }
            self.notchPanelController?.apply(agendaState: state)
        }
            self?.codexUsageViewModel?.refresh()
            self?.agentActivityViewModel?.load()

        calendarViewModel.activate()

        // Ouvre la bande sans passer par le survol du coin — c'est ce qui la rend vérifiable
        // sur capture d'écran, au même titre que `--show-settings` pour les Préférences.
        if CommandLine.arguments.contains("--show-usage-panel") {
            sidePanelController?.togglePinnedReveal()
        }

        // Même usage pour le panneau de l'encoche : le déplier sans passer par le survol est ce
        // qui le rend vérifiable sur capture d'écran.
        if CommandLine.arguments.contains("--show-notch-panel") {
            notchPanelController?.togglePinnedReveal()
        }

        // Même usage pour le cadran de volume : l'ouvrir sans passer par le coin est ce qui le
        // rend vérifiable sur capture d'écran.
        if CommandLine.arguments.contains("--show-volume-dial") {
            volumeDialController?.togglePinnedReveal()
        }

        // Et le menu radial : l'ouvrir sous le curseur, sans le bouton de souris.
        if CommandLine.arguments.contains("--show-radial-menu") {
            radialMenuController?.openForDevelopment()
        }

        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--show-settings") }) {
            let categoryRaw = arg.split(separator: "=").last.map(String.init)
            let category = categoryRaw.flatMap { SettingsCategory(rawValue: $0) } ?? .general
            SettingsWindowController.shared.show(category)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Le Dock macOS doit revenir tel que l'utilisateur l'avait, même si le réglage reste actif :
        // au prochain lancement il sera masqué de nouveau.
        systemDockService?.restore()
        agentHookServer.stop()
    }
}
