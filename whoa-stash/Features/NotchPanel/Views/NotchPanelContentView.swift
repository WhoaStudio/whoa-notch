import AppKit

/// Contenu du panneau de l'encoche : une silhouette sombre suspendue au haut de l'écran, qui
/// passe de la forme de l'encoche (ou d'une pastille, sur un Mac sans encoche) à un panneau
/// large portant l'onglet choisi, surmonté d'une capsule de navigation détachée, posée sous lui
/// et qui n'est donc pas un morceau de sa silhouette. Global porte la semaine ; Calendar porte
/// l'agenda et la grille mensuelle ; AI
/// porte le bloc d'utilisation (`NotchUsageTabView`), plus haut que les autres : le panneau ne
/// grandit que pour lui ; Tray affiche le bac à fichiers, qui vit hors de la vue (`FileShelfStore`) et
/// retient donc ce qu'on y dépose d'un dépliage à l'autre, et d'un lancement à l'autre.
///
/// Les deux silhouettes sont décrites par la même recette de chemin, dans le même ordre de
/// segments : Core Animation peut donc interpoler l'une vers l'autre, et c'est ce qui constitue
/// le dépliage. Rien d'autre ne bouge — ni la fenêtre, ni le cadre de la vue.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay.
final class NotchPanelContentView: NSView {

    private let backgroundLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let contentMask = CAShapeLayer()

    /// Les colonnes vivent dans un conteneur à part pour n'avoir qu'un masque et qu'une opacité
    /// à piloter pendant le dépliage.
    private let contentContainer = NSView()

    /// Appelé au clic sur l'engrenage (capsule ou en-tête de l'onglet AI), relayé jusqu'au
    /// contrôleur.
    var onOpenSettings: (() -> Void)? {
        didSet { usageTab.onOpenSettings = onOpenSettings }
    }

    /// Appelé au clic sur « Launch all », relayé jusqu'au contrôleur.
    var onLaunchAll: (() -> Void)?

    /// Faux quand la liste d'applis est vide : le bouton est grisé.
    var canLaunchAll: Bool {
        get { launchButton.isEnabled }
        set { launchButton.isEnabled = newValue }
    }

    /// Appelé au clic sur « actualiser » de l'onglet AI.
    var onRefreshUsage: (() -> Void)? {
        didSet { usageTab.onRefresh = onRefreshUsage }
    }

    /// La capsule de navigation, posée sous le panneau et détachée de lui : elle vit donc hors
    /// de `contentContainer`, que la silhouette découpe.
    private let capsule = NotchTabCapsuleView(selectedTab: .global)

    /// Engrenage des Préférences, en haut à droite du panneau, à hauteur de l'encoche.
    private let gearButton = NotchGearButtonView()
    private let launchButton = NotchGearButtonView(symbolName: "square.grid.2x2", description: "Launch all")

    /// État d'un appareil Bluetooth qui vient de se connecter : l'encoche s'élargit de part et
    /// d'autre, sans changer de hauteur, et cette vue porte le glyphe à gauche et la batterie à
    /// droite, dans les deux ailes ainsi ouvertes.
    private let deviceStatusPill = DeviceStatusPillView()
    private var isShowingDeviceStatus = false

    /// Notification d'un agent IA (session Claude Code terminée ou en attente) : mêmes ailes, plus larges.
    private let agentEventPill = AgentEventPillView()
    private var isShowingAgentEvent = false

    /// Courrier arrivé : mêmes ailes, les plus larges, avec l'objet et le début du texte.
    private let mailMessagePill = MailMessagePillView()
    private var isShowingMailMessage = false

    /// Lecture en cours : mêmes ailes que la pastille Bluetooth, mais tenues tant que ça joue. La
    /// pastille Bluetooth passe devant le temps de son affichage.
    private let nowPlayingWings = NowPlayingWingsView()
    private var isShowingNowPlaying = false
    /// Ligne de pilotage, dans l'onglet Global déplié.
    private let nowPlayingRow = NowPlayingRowView()

    /// L'onglet Global : la semaine horizontale.
    private let globalTab = NSView()
    private let weekStrip = WeekStripView()
    /// L'onglet Calendar : l'agenda et la grille du mois.
    private let calendarTab = NSView()
    private let calendarWidget = CalendarWidgetView()
    private let fileTray = FileTrayView()
    private let transformView = ImageTransformView()
    /// L'onglet Clipboard : historique des copies, nourri par `apply(clipboardItems:)`.
    private let clipboardTab = ClipboardTabView()

    /// Relayés jusqu'au contrôleur : « Clear » et le clic sur une carte.
    var onClearClipboard: (() -> Void)? {
        didSet { clipboardTab.onClear = onClearClipboard }
    }
    var onSelectClipboardItem: ((ClipboardItem) -> Void)? {
        didSet { clipboardTab.onSelect = onSelectClipboardItem }
    }
    var clipboardImageURL: ((ClipboardItem) -> URL?)? {
        didSet { clipboardTab.imageURLProvider = clipboardImageURL }
    }

    /// L'onglet AI : en-tête, carte du fournisseur, filtres et activité.
    private let usageTab = NotchUsageTabView()

    /// L'onglet Mirror : la caméra n'est allumée que pendant qu'il est à l'écran (voir
    /// `updateCameraActivity()`).
    private let mirrorTab = CameraMirrorView(
        viewModel: CameraMirrorViewModel(
            provider: MockCameraMirrorProvider.fromLaunchArguments() ?? AVCameraMirrorService()))

    private var selectedTab: NotchTab = .global

    /// Balayage d'onglet en cours (trackpad ou glisser à la souris).
    private var swipe = TabSwipeTracker()

    /// Place de repos de la capsule, relevée à chaque mise en page : c'est de là qu'elle part
    /// en sortant, et c'est là qu'elle revient en entrant.
    private var capsuleRestingPosition: CGPoint = .zero

    /// Silhouette courante, retenue pour le test de contact : le cadre de la fenêtre vaut
    /// toujours le cadre déplié, donc la vue est bien plus large que ce qu'elle dessine, et
    /// seule la forme peinte doit répondre (voir `hitTest(_:)`).
    private var silhouette: CGPath?

    /// Taille de la silhouette repliée, décidée par l'écran : l'encoche matérielle n'a pas les
    /// mêmes dimensions d'un Mac à l'autre, et une pastille les remplace quand il n'y en a pas.
    var collapsedSize: NSSize = NotchPanelGeometry.pillSize {
        didSet {
            guard collapsedSize != oldValue else { return }
            needsLayout = true
        }
    }

    /// Écart entre le bord du haut et la silhouette repliée : non nul pour la pastille flottante
    /// d'un écran sans encoche (voir `NotchPanelGeometry.collapsedTopGap`).
    var collapsedTopGap: CGFloat = 0 {
        didSet {
            guard collapsedTopGap != oldValue else { return }
            needsLayout = true
        }
    }

    private(set) var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        // Clic droit : le menu partagé par tous les panneaux de l'overlay. Posé ici plutôt que
        // sur chaque enfant — AppKit remonte la chaîne des responders jusqu'à la première vue
        // qui porte un menu.
        menu = OverlayContextMenu.shared.menu

        // Fond plein et non `NSVisualEffectView` : sur un Mac à encoche la silhouette repliée
        // doit se confondre avec du noir matériel, qu'aucun matériau translucide n'imite.
        layer?.addSublayer(backgroundLayer)

        strokeLayer.fillColor = nil
        strokeLayer.lineWidth = PanelGeometry.strokeWidth
        layer?.addSublayer(strokeLayer)

        contentContainer.wantsLayer = true
        // Le contenu est découpé par la silhouette elle-même : pendant le dépliage il ne doit
        // rien dépasser de la forme, qui est encore plus étroite que lui.
        contentContainer.layer?.mask = contentMask
        contentContainer.layer?.opacity = 0
        addSubview(contentContainer)

        contentContainer.addSubview(usageTab)
        contentContainer.addSubview(mirrorTab)

        globalTab.addSubview(weekStrip)
        // Le lecteur se range sous la semaine dans l'onglet Global, et y reste : au repos il
        // montre « Nothing playing ».
        nowPlayingRow.apply(nil)
        nowPlayingRow.onCommand = { [weak self] command in self?.onNowPlayingCommand?(command) }
        globalTab.addSubview(nowPlayingRow)
        contentContainer.addSubview(globalTab)

        calendarTab.addSubview(calendarWidget)
        contentContainer.addSubview(calendarTab)
        contentContainer.addSubview(fileTray)
        transformView.isHidden = true
        transformView.onClose = { [weak self] in self?.closeTransform(animated: true) }
        contentContainer.addSubview(transformView)
        contentContainer.addSubview(clipboardTab)
        gearButton.onClick = { [weak self] in self?.onOpenSettings?() }
        contentContainer.addSubview(gearButton)
        launchButton.onClick = { [weak self] in self?.onLaunchAll?() }
        contentContainer.addSubview(launchButton)

        // Hors du conteneur de contenu, et donc hors du masque de la silhouette : la capsule est
        // justement ce qui se trouve en dehors d'elle. Elle part invisible et suit le dépliage en
        // fondu, comme le contenu.
        capsule.onSelect = { [weak self] tab in self?.select(tab, animated: true) }
        capsule.layer?.opacity = 0
        addSubview(capsule)
        nowPlayingWings.layer?.opacity = 0
        addSubview(nowPlayingWings)
        deviceStatusPill.layer?.opacity = 0
        addSubview(deviceStatusPill)
        agentEventPill.layer?.opacity = 0
        addSubview(agentEventPill)
        mailMessagePill.layer?.opacity = 0
        addSubview(mailMessagePill)
        applySelection(animated: false)

        // Le panneau tout entier est la cible de dépôt, et pas le rectangle du bac : un fichier
        // se lâche sur l'encoche — en haut, là où la silhouette repliée se voit —, alors que le
        // bac occupe le bas du panneau déplié. Viser le bac demanderait de traverser tout le
        // panneau avant de relâcher. Le bac reste seul à savoir quoi faire du dépôt.
        registerForDraggedTypes([.fileURL])

        // Aucune ombre portée : la silhouette se détache par sa teinte et son filet, et la
        // fenêtre est elle aussi sans ombre (`NotchPanelWindow`).
        layer?.masksToBounds = false

        applyPalette()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        let palette = OverlayPalette.resolved(for: effectiveAppearance)
        backgroundLayer.fillColor = palette.panelBackground
        gearButton.applyPalette(palette)
        launchButton.applyPalette(palette)
        strokeLayer.strokeColor = palette.strokeColor
    }

    // MARK: - État

    func apply(usageState: ClaudeUsageState, animated: Bool) {
        usageTab.apply(claude: usageState)
    }

    func apply(copilotUsageState: CopilotUsageState) {
        usageTab.apply(copilot: copilotUsageState)
    }

    /// Ce que le curseur doit encore toucher pour garder le panneau déplié : le panneau de
    /// l'onglet affiché et la capsule, et non le cadre entier de la fenêtre, qui est plus haut
    /// que les onglets courts.
    var interactiveFrame: NSRect {
        // Le cadre visé ne suffit pas pendant le glissement d'un onglet à l'autre : la capsule
        // est encore peinte à son ancienne place, et le curseur posé dessus ne doit pas
        // refermer le panneau.
        NotchPanelGeometry.panelRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
            .union(NotchPanelGeometry.capsuleRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight))
            .union(capsuleOnScreenFrame)
    }

    /// Cadre où la capsule est réellement peinte, glissement compris — celui du modèle n'est
    /// atteint qu'à la fin du ressort.
    private var capsuleOnScreenFrame: CGRect {
        capsule.layer?.presentation()?.frame ?? capsule.frame
    }

    // MARK: - Onglets

    private var tabContentViews: [NSView] { [globalTab, calendarTab, fileTray, clipboardTab, mirrorTab, usageTab] }

    private func contentView(for tab: NotchTab) -> NSView {
        switch tab {
        case .global: globalTab
        case .calendar: calendarTab
        case .tray: fileTray
        case .clipboard: clipboardTab
        case .mirror: mirrorTab
        case .ai: usageTab
        }
    }

    func apply(clipboardItems: [ClipboardItem]) {
        clipboardTab.apply(items: clipboardItems)
    }

    func apply(agendaState: CalendarAgendaState) {
        calendarWidget.apply(agendaState)
    }

    /// Remet la semaine et le calendrier à la bonne date — appelé à chaque dépliage,
    /// le panneau restant en mémoire d'un survol à l'autre et parfois d'un jour à l'autre.
    func refreshWeek() {
        weekStrip.refresh()
        clipboardTab.refreshAges()
        calendarWidget.refresh()
    }

    func select(_ tab: NotchTab, animated: Bool) {
        guard tab != selectedTab else { return }
        closeTransform(animated: false)
        selectedTab = tab
        capsule.select(tab, animated: animated)
        applySelection(animated: animated)
        // Seuls les onglets AI et Mirror sont plus hauts : la silhouette et la capsule suivent leur hauteur.
        layoutTabBodies()
        moveCapsuleToSelectedTab(animated: animated)
        if isExpanded { applyShape(expanded: true, animated: animated) }
        updateCameraActivity()
    }

    /// La caméra ne tourne que panneau déplié et onglet Mirror choisi : c'est ce qui éteint le
    /// voyant dès que le panneau se replie ou qu'on change d'onglet.
    private func updateCameraActivity() {
        mirrorTab.setActive(isExpanded && selectedTab == .mirror)
    }

    /// Éteint la caméra sans condition — la fenêtre est retirée, pas seulement repliée.
    func stopCamera() {
        mirrorTab.setActive(false)
    }

    /// Montre l'onglet choisi et retire les autres. Les vues inactives sont réellement masquées
    /// et pas seulement transparentes : le bac à fichiers ne doit pas capter un glisser pendant
    /// qu'un autre onglet est affiché.
    private func applySelection(animated: Bool) {
        let active = contentView(for: selectedTab)

        for view in tabContentViews {
            let isActive = view === active
            view.isHidden = !isActive
            guard animated, isActive else {
                view.layer?.opacity = isActive ? 1 : 0
                continue
            }
            // Fondu d'entrée seul : l'onglet qui s'en va est retiré d'un coup, donc les deux ne
            // se superposent jamais.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = PanelFold.fadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.layer?.opacity = 1
            view.layer?.add(fade, forKey: "opacity")
        }
    }

    // MARK: - Contact

    /// Seule la silhouette peinte répond ; le reste du cadre laisse passer ce qui est dessous.
    ///
    /// Sans cela, un glisser de fichiers destiné à un autre coin du haut de l'écran — une icône
    /// de la barre de menus, par exemple — serait avalé par le grand rectangle invisible de la
    /// fenêtre dès que celle-ci accepte les glissers (`setFileDragActive(_:)`).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let silhouette else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        // La capsule est hors de la silhouette — c'est tout l'objet de sa forme détachée — donc
        // elle répond pour elle-même, et seulement dépliée : repliée elle est invisible, et rien
        // d'invisible ne doit avaler un clic.
        guard silhouette.contains(local) || (isExpanded && capsuleShape().contains(local)) else { return nil }
        return super.hitTest(point)
    }

    /// Le contour de la capsule, pour le test de contact : son cadre est un rectangle, mais ses
    /// extrémités sont arrondies et ce qui les déborde doit passer dessous.
    private func capsuleShape() -> CGPath {
        let frame = capsuleOnScreenFrame
        let radius = frame.height / 2
        return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // MARK: - Balayage d'onglets

    /// Balayage à deux doigts. Les vues qui défilent d'elles-mêmes (la semaine, le presse-papiers)
    /// consomment leurs événements et ne les relaient pas ici ; ne reste que le fond du panneau
    /// et ce que ces vues ne savent pas défiler. Les molettes sans phase (souris) sont ignorées :
    /// à la souris, on glisse.
    override func scrollWheel(with event: NSEvent) {
        guard isExpanded, event.hasPreciseScrollingDeltas, !event.phase.isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.began) { swipe.cancel() }
        if event.phase.contains(.cancelled) {
            swipe.cancel()
            settleSwipe(direction: nil)
            return
        }

        if swipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) {
            followSwipe()
        } else if !swipe.isSwiping {
            super.scrollWheel(with: event)
        }
        if event.phase.contains(.ended) {
            settleSwipe(direction: swipe.end())
        }
    }

    override func mouseDown(with event: NSEvent) {
        swipe.cancel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isExpanded else { return }
        if swipe.move(dx: event.deltaX, dy: -event.deltaY) { followSwipe() }
    }

    override func mouseUp(with event: NSEvent) {
        guard swipe.isSwiping else {
            swipe.cancel()
            return
        }
        settleSwipe(direction: swipe.end())
    }

    /// L'onglet affiché suit le doigt, atténué pour qu'on sente qu'il va partir. La résistance
    /// croît aux deux bouts de la rangée, où il n'y a pas d'onglet voisin.
    private func followSwipe() {
        guard let layer = contentView(for: selectedTab).layer else { return }
        let direction: TabSwipeTracker.Direction = swipe.offset < 0 ? .next : .previous
        let resistance: CGFloat = selectedTab.neighbor(direction) == nil ? 0.25 : 1
        let shift = swipe.offset * resistance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(shift, 0, 0)
        layer.opacity = Float(max(0.3, 1 - abs(shift) / 300))
        CATransaction.commit()
    }

    /// Fin du geste : change d'onglet si un voisin existe, sinon ramène l'onglet à sa place.
    private func settleSwipe(direction: TabSwipeTracker.Direction?) {
        let current = contentView(for: selectedTab)
        resetSwipeOffset(of: current, animated: true)
        guard let direction, let target = selectedTab.neighbor(direction) else { return }
        current.layer?.removeAllAnimations()
        current.layer?.transform = CATransform3DIdentity
        select(target, animated: true)
    }

    private func resetSwipeOffset(of view: NSView, animated: Bool) {
        guard let layer = view.layer else { return }
        let hadOffset = !CATransform3DIsIdentity(layer.transform)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        guard animated, hadOffset, OverlayAnimation.isEnabled else { return }
        layer.springAnimate(keyPath: "transform.translation.x", to: 0, preset: .gentle)
    }

    // MARK: - Dépôt

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard fileTray.canAccept(sender) else { return [] }
        // Un nouveau glisser ferme la vue Transform : c'est de nouveau le bac qui reçoit.
        closeTransform(animated: true)
        // Un glisser qui arrive sur le panneau vient pour le bac : il passe devant, quel que
        // soit l'onglet affiché jusque-là. C'est aussi ce qui garantit qu'il est bien là, et
        // visible, au moment où le fichier tombe.
        select(.tray, animated: true)
        return updateTrayDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard fileTray.canAccept(sender) else { return [] }
        return updateTrayDrag(sender)
    }

    /// Montre les zones du bac et allume celle sous le curseur.
    private func updateTrayDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let target = fileTray.dropTarget(for: sender, in: self)
        fileTray.setDragActive(
            true,
            fromTray: fileTray.isFromTray(sender),
            hovered: target,
            imageFormat: fileTray.imageFormat(of: sender)
        )
        setConversionRowVisible(fileTray.hasConversionRow)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        fileTray.setDragActive(false)
        setConversionRowVisible(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        fileTray.setDragActive(false)
        setConversionRowVisible(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let target = fileTray.dropTarget(for: sender, in: self)
        fileTray.setDragActive(false)
        if target == .transform {
            guard let url = fileTray.transformSource(sender) else {
                setConversionRowVisible(false)
                return false
            }
            showTransform(url)
            return true
        }
        setConversionRowVisible(false)
        return switch target {
        case .keep: fileTray.accept(sender)
        case .airDrop: fileTray.airDrop(sender)
        case .transform: false
        }
    }

    // MARK: - Mise en page

    override func layout() {
        super.layout()

        applyShape(expanded: isExpanded, animated: false)

        // Le panneau n'occupe pas tout le cadre : la bande basse revient à la capsule. Le
        // conteneur, lui, garde le cadre entier — son masque est la silhouette, qui est décrite
        // dans ce repère-là.
        let panel = panelRect
        contentContainer.frame = bounds

        capsule.frame = NotchPanelGeometry.capsuleRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
        // La place de repos est relevée ici, une fois le cadre posé et avant que l'entrée ou la
        // sortie ne décale le calque : c'est le point d'arrivée de la course, et il ne peut pas
        // être lu plus tard, quand la capsule est justement ailleurs.
        capsuleRestingPosition = capsule.layer?.position ?? .zero
        applyCapsuleReveal(animated: false)

        let wingsY = panel.maxY - collapsedTopGap - collapsedSize.height
        let deviceWidth = collapsedSize.width + 2 * DeviceStatusPillView.wingWidth
        deviceStatusPill.frame = NSRect(
            x: bounds.midX - deviceWidth / 2, y: wingsY, width: deviceWidth, height: collapsedSize.height)
        let agentWidth = collapsedSize.width + 2 * AgentEventPillView.wingWidth
        agentEventPill.frame = NSRect(
            x: bounds.midX - agentWidth / 2, y: wingsY, width: agentWidth, height: collapsedSize.height)
        let mailWidth = collapsedSize.width + 2 * MailMessagePillView.wingWidth
        mailMessagePill.frame = NSRect(
            x: bounds.midX - mailWidth / 2, y: wingsY, width: mailWidth, height: collapsedSize.height)
        let media = nowPlayingSize
        let mediaExtra = media.height - collapsedSize.height
        nowPlayingWings.lift = collapsedTopGap > 0 ? 0 : NowPlayingWingsView.extraHeight / 2
        // Un peu plus haute que l'encoche : c'est ce qui signale la lecture, repliée.
        nowPlayingWings.frame = NSRect(
            x: bounds.midX - media.width / 2, y: wingsY - mediaExtra, width: media.width,
            height: media.height)

        layoutTabBodies()
    }

    /// Taille de la silhouette pendant la lecture : l'encoche élargie de ses ailes et un peu plus
    /// haute ; en mode île, plus étroite et plus haute (voir `NowPlayingWingsView.islandWingWidth`).
    private var nowPlayingSize: NSSize {
        if collapsedTopGap > 0 {
            return NSSize(
                width: NowPlayingWingsView.islandCenterWidth + 2 * NowPlayingWingsView.islandWingWidth,
                height: collapsedSize.height + NowPlayingWingsView.islandExtraHeight)
        }
        return NSSize(
            width: collapsedSize.width + 2 * NowPlayingWingsView.wingWidth,
            height: collapsedSize.height + NowPlayingWingsView.extraHeight)
    }

    /// Le panneau de l'onglet affiché, dans le repère de cette vue.
    private var panelRect: CGRect {
        NotchPanelGeometry.panelRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
    }

    /// Vrai le temps qu'une image du bac est glissée : le panneau Tray grandit pour montrer la
    /// rangée de conversion, et reprend sa hauteur quand le glisser finit ou s'annule.
    private var isShowingConversionRow = false

    /// L'image que la vue Transform est en train de traiter, `nil` quand elle est fermée. Elle
    /// prend la place du bac, et le panneau grandit pour elle.
    private var transformSourceURL: URL?

    private var panelExtraHeight: CGFloat {
        guard selectedTab == .tray else { return 0 }
        if transformSourceURL != nil { return NotchPanelGeometry.transformExtraHeight }
        return isShowingConversionRow ? NotchPanelGeometry.trayConversionExtraHeight : 0
    }

    /// Fait grandir ou rétrécir le panneau pour la rangée de conversion, avec la même animation
    /// qu'un changement d'onglet.
    private func setConversionRowVisible(_ visible: Bool) {
        guard visible != isShowingConversionRow else { return }
        isShowingConversionRow = visible
        refreshPanelHeight(animated: true)
    }

    private func refreshPanelHeight(animated: Bool) {
        layoutTabBodies()
        moveCapsuleToSelectedTab(animated: animated)
        if isExpanded { applyShape(expanded: true, animated: animated) }
    }

    /// Ouvre la vue Transform sur une image du bac : elle remplace le bac, et masque l'engrenage
    /// et la capsule, qu'elle recouvrirait.
    private func showTransform(_ url: URL) {
        isShowingConversionRow = false
        transformSourceURL = url
        transformView.show(url: url)
        applyTransformVisibility()
        refreshPanelHeight(animated: true)
    }

    private func closeTransform(animated: Bool) {
        guard transformSourceURL != nil else { return }
        transformSourceURL = nil
        applyTransformVisibility()
        refreshPanelHeight(animated: animated)
    }

    private func applyTransformVisibility() {
        let open = transformSourceURL != nil
        transformView.isHidden = !open
        fileTray.isHidden = open || selectedTab != .tray
        gearButton.isHidden = open
        launchButton.isHidden = open
        capsule.isHidden = open
    }

    /// Corps des onglets : tout l'intérieur du panneau. Les onglets l'occupent en entier et se
    /// relaient dedans. Séparé de `layout()` pour qu'un changement d'onglet puisse le refaire sans
    /// poser sèchement la silhouette, qui s'anime.
    private func layoutTabBodies() {
        let inset = NotchPanelGeometry.contentInsetX
        let panel = panelRect
        let bodyTop = panel.maxY - NotchPanelGeometry.contentInsetTop(forCollapsedHeight: collapsedSize.height)
        let bodyBottom = panel.minY + NotchPanelGeometry.contentInsetBottom
        let body = NSRect(
            x: panel.minX,
            y: bodyBottom,
            width: panel.width,
            height: max(0, bodyTop - bodyBottom)
        ).insetBy(dx: inset, dy: 0)
        // Le bac déborde un peu sur les marges latérales : ses vignettes gagnent de la place.
        let trayBleed: CGFloat = 4
        for view in tabContentViews {
            view.frame = view === fileTray ? body.insetBy(dx: -trayBleed, dy: 0) : body
        }
        transformView.frame = body

        // Dans le repère de `globalTab`, la semaine prend toute la largeur utile.
        let weekHeight = NotchPanelGeometry.weekStripHeight
        weekStrip.frame = NSRect(
            x: globalTab.bounds.minX,
            y: globalTab.bounds.maxY - weekHeight,
            width: globalTab.bounds.width,
            height: weekHeight
        )

        nowPlayingRow.frame = NSRect(
            x: globalTab.bounds.minX,
            y: globalTab.bounds.minY,
            width: globalTab.bounds.width,
            height: max(0, globalTab.bounds.height - weekHeight - NotchPanelGeometry.weekToPlayerGap)
        )

        calendarWidget.frame = calendarTab.bounds

        // Engrenage : coin haut droit du panneau, à hauteur de la bande de l'encoche, abaissé de `gearDrop`, dans la
        // marge latérale des onglets.
        let gearSize = TabBarMetrics.bubbleSize
        gearButton.frame = NSRect(
            x: panel.maxX - inset - gearSize - NotchPanelGeometry.gearInsetX,
            y: panel.maxY - collapsedSize.height / 2 - gearSize / 2 - NotchPanelGeometry.gearDrop,
            width: gearSize,
            height: gearSize
        )
        launchButton.frame = gearButton.frame.offsetBy(dx: -gearSize, dy: 0)

        // Mirror pose son cercle lui-même, contre le bas du panneau : il a donc tout le cadre du
        // panneau Mirror, quel que soit l'onglet affiché.
        mirrorTab.frame = NotchPanelGeometry.panelRect(in: bounds, tab: .mirror)
    }

    /// Descend ou remonte la capsule sous le panneau de l'onglet affiché. Au ressort du
    /// dépliage, puisque la silhouette se redimensionne en même temps.
    private func moveCapsuleToSelectedTab(animated: Bool) {
        guard let layer = capsule.layer else { return }
        let previous = layer.position
        capsule.frame = NotchPanelGeometry.capsuleRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
        let target = layer.position
        capsuleRestingPosition = target
        guard isExpanded else { return }
        if animated {
            layer.position = previous
            layer.springAnimate(keyPath: "position", to: target, preset: .gentle)
        }
    }

    // MARK: - Entrée et sortie de la capsule

    /// Course de la capsule : ce dont elle est décalée, repliée, sous sa place de repos.
    ///
    /// Elle sort par le **bas** et non vers le panneau : glisser de dessous lui demanderait
    /// qu'elle soit derrière lui dans l'ordre d'affichage, alors qu'elle est posée par-dessus —
    /// elle lui passerait sur le ventre au lieu d'en sortir.
    private static let capsuleTravel: CGFloat = 14

    /// Fait monter la capsule à sa place, ou l'en fait redescendre. Le ressort est celui du
    /// dépliage (`SpringPreset.gentle`) et le fondu celui du contenu : les deux gestes sont
    /// simultanés et doivent se lire comme un seul.
    ///
    /// Posée sèchement quand il n'y a rien à animer — une mise en page doit déjà trouver la
    /// capsule dans son état courant à la première image.
    private func applyCapsuleReveal(animated: Bool) {
        guard let layer = capsule.layer, capsuleRestingPosition != .zero else { return }

        let target = isExpanded
            ? capsuleRestingPosition
            : CGPoint(x: capsuleRestingPosition.x, y: capsuleRestingPosition.y - Self.capsuleTravel)
        let opacity: Float = isExpanded ? 1 : 0

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = target
            layer.opacity = opacity
            CATransaction.commit()
            return
        }

        layer.springAnimate(keyPath: "position", to: target, preset: .gentle)
        PanelFold.fade(layer, to: opacity)
    }

    // MARK: - Pastille d'appareil

    func showDeviceStatus(_ status: DeviceStatus) {
        // Dépliée, la silhouette occupe déjà toute la place.
        guard !isExpanded else { return }
        deviceStatusPill.apply(status)
        deviceStatusPill.layoutSubtreeIfNeeded()
        isShowingDeviceStatus = true
        applyShape(expanded: false, animated: true)
        PanelFold.fade(deviceStatusPill.layer!, to: 1)
        updateNowPlayingWingsOpacity(animated: true)
    }

    func hideDeviceStatus(animated: Bool = true) {
        guard isShowingDeviceStatus else { return }
        isShowingDeviceStatus = false
        applyShape(expanded: isExpanded, animated: animated)
        if let layer = deviceStatusPill.layer {
            if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
        }
        updateNowPlayingWingsOpacity(animated: animated)
    }

    // MARK: - Notification d'agent

    var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
        get { usageTab.onAgentDecision }
        set { usageTab.onAgentDecision = newValue }
    }

    func apply(agentPrompt: AgentEvent?) {
        usageTab.apply(agentPrompt: agentPrompt)
    }

    func apply(agentActivity: AgentActivity?) {
        usageTab.apply(agentActivity: agentActivity)
    }

    func showAgentEvent(_ event: AgentEvent) {
        guard !isExpanded else { return }
        hideDeviceStatus(animated: false)
        hideMailMessage(animated: false)
        agentEventPill.apply(event, notchWidth: collapsedSize.width)
        agentEventPill.layoutSubtreeIfNeeded()
        isShowingAgentEvent = true
        applyShape(expanded: false, animated: true)
        PanelFold.fade(agentEventPill.layer!, to: 1)
        updateNowPlayingWingsOpacity(animated: true)
    }

    func hideAgentEvent(animated: Bool = true) {
        guard isShowingAgentEvent else { return }
        isShowingAgentEvent = false
        applyShape(expanded: isExpanded, animated: animated)
        if let layer = agentEventPill.layer {
            if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
        }
        updateNowPlayingWingsOpacity(animated: animated)
    }

    // MARK: - Courrier

    func showMailMessage(_ message: MailMessage) {
        guard !isExpanded else { return }
        hideDeviceStatus(animated: false)
        hideAgentEvent(animated: false)
        mailMessagePill.apply(message, notchWidth: collapsedSize.width)
        mailMessagePill.layoutSubtreeIfNeeded()
        isShowingMailMessage = true
        applyShape(expanded: false, animated: true)
        PanelFold.fade(mailMessagePill.layer!, to: 1)
        updateNowPlayingWingsOpacity(animated: true)
    }

    func hideMailMessage(animated: Bool = true) {
        guard isShowingMailMessage else { return }
        isShowingMailMessage = false
        applyShape(expanded: isExpanded, animated: animated)
        if let layer = mailMessagePill.layer {
            if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
        }
        updateNowPlayingWingsOpacity(animated: animated)
    }

    // MARK: - Lecture en cours

    /// Appelé par la ligne de pilotage : précédent, lecture/pause, suivant.
    var onNowPlayingCommand: ((NowPlayingCommand) -> Void)?

    /// Appelé quand le panneau vient de se déplier : le lecteur relit alors la suite du morceau.
    var onExpanded: (() -> Void)?

    /// Les prochains titres du morceau en cours ; vide referme la colonne « Playing Next ».
    func apply(playingNext items: [QueueItem]) {
        nowPlayingRow.apply(queue: items)
    }

    /// Met à jour le lecteur de l'onglet Global : dernier morceau connu, ou « rien » si aucun.
    func updateNowPlayingPlayer(_ state: NowPlayingState?) {
        nowPlayingRow.apply(state)
    }

    /// Montre (ou met à jour) les ailes de la lecture en cours ; `nil` les retire.
    func showNowPlaying(_ state: NowPlayingState?) {
        guard let state else {
            guard isShowingNowPlaying else { return }
            isShowingNowPlaying = false
            applyShape(expanded: isExpanded, animated: true)
            updateNowPlayingWingsOpacity(animated: true)
            return
        }

        nowPlayingWings.apply(state)
        guard !isShowingNowPlaying else { return }
        isShowingNowPlaying = true
        applyShape(expanded: isExpanded, animated: true)
        updateNowPlayingWingsOpacity(animated: true)
    }

    /// Les ailes de lecture ne se voient que repliées et sans pastille Bluetooth par-dessus.
    private func updateNowPlayingWingsOpacity(animated: Bool) {
        guard let layer = nowPlayingWings.layer else { return }
        let visible = isShowingNowPlaying && !isShowingDeviceStatus && !isShowingAgentEvent && !isShowingMailMessage && !isExpanded
        if animated { PanelFold.fade(layer, to: visible ? 1 : 0) } else { layer.opacity = visible ? 1 : 0 }
    }

    // MARK: - Silhouette

    /// Les deux états, tirés de la même recette que les bandes de flanc
    /// (`PanelGeometry.silhouette`), ici suspendue au bord du **haut** : deux raccords concaves
    /// qui évasent le panneau dans ce bord comme un onglet s'évase dans sa barre, et deux coins
    /// convexes en bas. Seuls la taille et les rayons les distinguent, donc les deux chemins ont
    /// le même nombre de segments dans le même ordre — c'est cette identité de structure qui rend
    /// le dépliage animable d'un seul `CASpringAnimation` sur `path`.

    private func collapsedPath() -> CGPath {
        if collapsedTopGap > 0 {
            return PanelGeometry.islandSilhouette(in: panelRect, size: collapsedSize, topGap: collapsedTopGap)
        }
        return PanelGeometry.silhouette(
            in: panelRect,
            anchoredTo: .top,
            size: collapsedSize,
            shoulderRadius: NotchPanelGeometry.collapsedShoulderRadius,
            farRadius: NotchPanelGeometry.collapsedBottomRadius
        )
    }

    /// L'encoche élargie par ses deux ailes — même hauteur, mêmes rayons.
    private func wingedPath() -> CGPath {
        // La pastille Bluetooth impose sa largeur et garde la hauteur de l'encoche ; sinon la
        // lecture donne sa taille (`nowPlayingSize`).
        let size = isShowingMailMessage
            ? NSSize(
                width: collapsedSize.width + 2 * MailMessagePillView.wingWidth,
                height: collapsedSize.height)
            : isShowingAgentEvent
            ? NSSize(
                width: collapsedSize.width + 2 * AgentEventPillView.wingWidth,
                height: collapsedSize.height)
            : isShowingDeviceStatus
            ? NSSize(
                width: collapsedSize.width + 2 * DeviceStatusPillView.wingWidth,
                height: collapsedSize.height)
            : nowPlayingSize
        if collapsedTopGap > 0 {
            return PanelGeometry.islandSilhouette(in: panelRect, size: size, topGap: collapsedTopGap)
        }
        return PanelGeometry.silhouette(
            in: panelRect,
            anchoredTo: .top,
            size: size,
            shoulderRadius: NotchPanelGeometry.collapsedShoulderRadius,
            farRadius: NotchPanelGeometry.collapsedBottomRadius
        )
    }

    private func expandedPath() -> CGPath {
        // Mode île : une pastille détachée du bord, arrondie sur ses quatre coins, qui garde
        // la même suite de segments que la pastille repliée.
        if collapsedTopGap > 0 {
            // Mirror : sans raccords concaves, le corps épouse le cercle de l'aperçu.
            let isMirror = selectedTab == .mirror
            let width = isMirror ? NotchPanelGeometry.mirrorBodyWidth : panelRect.width
            return PanelGeometry.islandSilhouette(
                in: panelRect,
                size: CGSize(width: width, height: panelRect.height),
                topGap: collapsedTopGap,
                cornerRadius: NotchPanelGeometry.expandedBottomRadius,
                bottomCornerRadius: isMirror ? width / 2 : NotchPanelGeometry.expandedBottomRadius)
        }
        // Mirror : un U plus étroit que les autres onglets, dont le fond est le cercle de l'aperçu.
        // Un rayon de la moitié du corps joint les deux coins du bas en demi-cercle, sans changer
        // le nombre de segments : le passage d'un onglet à l'autre reste animable.
        guard selectedTab == .mirror else {
            return PanelGeometry.silhouette(
                in: panelRect,
                anchoredTo: .top,
                shoulderRadius: NotchPanelGeometry.expandedShoulderRadius,
                farRadius: NotchPanelGeometry.expandedBottomRadius
            )
        }
        return PanelGeometry.silhouette(
            in: panelRect,
            anchoredTo: .top,
            size: CGSize(width: NotchPanelGeometry.mirrorSilhouetteWidth, height: panelRect.height),
            shoulderRadius: NotchPanelGeometry.expandedShoulderRadius,
            farRadius: NotchPanelGeometry.mirrorBodyWidth / 2
        )
    }

    // MARK: - Dépliage

    /// Replie ou déplie le panneau. Seule la silhouette s'anime : la fenêtre garde en
    /// permanence le cadre déplié (voir `NotchPanelGeometry.windowFrame`).
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if !expanded { closeTransform(animated: false) }
        if expanded {
            hideDeviceStatus(animated: animated)
            hideMailMessage(animated: animated)
            hideAgentEvent(animated: animated)
            nowPlayingRow.refreshVolume()
            onExpanded?()
        }
        applyShape(expanded: expanded, animated: animated)
        updateNowPlayingWingsOpacity(animated: animated)
        updateCameraActivity()
    }

    private func applyShape(expanded: Bool, animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let path = expanded ? expandedPath() : (isShowingDeviceStatus || isShowingAgentEvent || isShowingMailMessage || isShowingNowPlaying ? wingedPath() : collapsedPath())
        // La forme visée, et non celle de l'image en cours : pendant le dépliage, c'est déjà sur
        // le panneau déplié qu'on vient cliquer ou déposer.
        silhouette = path

        // Le contenu suit le dépliage en fondu plutôt qu'au ressort, et il est découpé par la
        // silhouette elle-même (`contentMask`) : pendant le dépliage il ne doit rien dépasser de
        // la forme, qui est encore plus étroite que lui.
        // La capsule ne se contente pas de suivre le fondu du contenu : elle monte à sa place et
        // y redescend, puisqu'elle est la seule surface à ne pas être portée par la silhouette.
        applyCapsuleReveal(animated: animated)

        PanelFold.apply(
            path: path,
            to: [backgroundLayer, strokeLayer, contentMask],
            in: bounds,
            fading: contentContainer.layer.map { [$0] } ?? [],
            to: expanded ? 1 : 0,
            animated: animated
        )
    }
}
