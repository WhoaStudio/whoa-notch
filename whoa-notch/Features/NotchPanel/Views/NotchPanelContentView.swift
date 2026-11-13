import AppKit

/// Contenu du panneau de l'encoche : une silhouette sombre suspendue au haut de l'écran, qui
/// passe de la forme de l'encoche (ou d'une pastille, sur un Mac sans encoche) à un panneau
/// large portant l'onglet choisi, surmonté d'une capsule de navigation détachée, posée sous lui
/// et qui n'est donc pas un morceau de sa silhouette. Global porte la semaine ; Calendar porte
/// l'agenda et la grille mensuelle ; AI
/// porte les demandes et l'activité des agents (`NotchUsageTabView`) ; Analytics porte le bloc
/// d'utilisation (`NotchAnalyticsTabView`), plus haut que les autres : le panneau ne grandit que
/// pour lui ; Tray affiche le bac à fichiers, qui vit hors de la vue (`FileShelfStore`) et
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

  /// Appelé au clic sur l'engrenage (capsule ou en-tête de l'onglet Analytics), relayé jusqu'au
  /// contrôleur.
  var onOpenSettings: (() -> Void)? {
    didSet { analyticsTab.onOpenSettings = onOpenSettings }
  }

  /// Appelé au clic sur « Launch all », relayé jusqu'au contrôleur.
  var onLaunchAll: (() -> Void)?

  /// Faux quand la liste d'applis est vide : le bouton est grisé.
  var canLaunchAll: Bool {
    get { launchButton.isEnabled }
    set { launchButton.isEnabled = newValue }
  }

  /// Appelé au clic sur « actualiser » de l'onglet Analytics.
  var onRefreshUsage: (() -> Void)? {
    didSet { analyticsTab.onRefresh = onRefreshUsage }
  }

  /// La capsule de navigation, posée sous le panneau et détachée de lui : elle vit donc hors
  /// de `contentContainer`, que la silhouette découpe.
  private let capsule = NotchTabCapsuleView(selectedTab: .global)

  /// Engrenage des Préférences, en haut à droite du panneau, à hauteur de l'encoche.
  private let gearButton = NotchGearButtonView()
  private let launchButton = NotchGearButtonView(
    symbolName: "square.grid.2x2", description: "Launch all")

  /// Tasse de l'en-tête, à gauche de « Launch all » : ouvre l'onglet Stay Awake, et s'allume
  /// tant que le Mac est tenu éveillé.
  private let stayAwakeButton = NotchGearButtonView(
    symbolName: "cup.and.saucer", description: "Stay awake")
  /// Jetons et coût du mois, à gauche de la tasse : ouvre l'onglet Analytics.
  private let usageChip = NotchUsageChipView()
  private var monthSummary: ActivitySummary?
  private let analyticsTab = NotchAnalyticsTabView()
  /// L'onglet que la pastille a quitté, où un second clic ramène (comme `tabBeforeStayAwake`).
  private var tabBeforeAnalytics: NotchTab = .global
  private let stayAwakeTab = StayAwakeTabView()
  private let stayAwakeIdleIndicator = StayAwakeIdleIndicator()
  private var stayAwakeState = StayAwakeState()

  /// L'onglet que la tasse a quitté, où un second clic ramène : Stay Awake n'a pas de bulle
  /// dans la capsule pour en repartir.
  private var tabBeforeStayAwake: NotchTab = .global

  /// Relayé jusqu'au contrôleur : durée, portée, « Turn Off ».
  var onStayAwakeAction: ((StayAwakeAction) -> Void)? {
    didSet { stayAwakeTab.onAction = onStayAwakeAction }
  }

  /// État d'un appareil Bluetooth qui vient de se connecter : l'encoche s'élargit de part et
  /// d'autre, sans changer de hauteur, et cette vue porte le glyphe à gauche et la batterie à
  /// droite, dans les deux ailes ainsi ouvertes.
  private let launchGreeting = LaunchGreetingView()
  private var isShowingLaunchGreeting = false
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
  /// Doublures de la pochette et du visualiseur : elles font le trajet entre les ailes et le
  /// lecteur de l'onglet Global pendant le dépliage, hors du fondu du contenu. Leur cadre est
  /// le cadre entier et ne reçoit aucun clic.
  private let nowPlayingFlight = NowPlayingFlightView()
  private let flightArtwork = ArtworkView()
  private let flightVisualizer = AudioVisualizerView()
  /// Numéro du trajet en cours : la fin d'un trajet interrompu ne doit rien rendre visible.
  private var flightGeneration = 0

  /// L'onglet Global : la semaine horizontale.
  private let globalTab = NSView()
  private let weekRow = WeekAgendaRowView()
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
  var onDeleteClipboardItem: ((ClipboardItem) -> Void)? {
    didSet { clipboardTab.onDelete = onDeleteClipboardItem }
  }
  var onTogglePinClipboardItem: ((ClipboardItem) -> Void)? {
    didSet { clipboardTab.onTogglePin = onTogglePinClipboardItem }
  }
  var clipboardImageURL: ((ClipboardItem) -> URL?)? {
    didSet { clipboardTab.imageURLProvider = clipboardImageURL }
  }

  /// L'onglet Notes, nourri par `apply(notes:)`.
  private let notesTab = NotesTabView()

  /// Relayés jusqu'au contrôleur : création, édition et suppression d'une note.
  var onCreateNote: (() -> Void)? {
    didSet { notesTab.onCreate = onCreateNote }
  }
  var onEditNote: ((UUID, String) -> Void)? {
    didSet { notesTab.onEdit = onEditNote }
  }
  var onDeleteNote: ((UUID) -> Void)? {
    didSet { notesTab.onDelete = onDeleteNote }
  }

  /// L'onglet AI : en-tête, carte du fournisseur, filtres et activité.
  private let usageTab = NotchUsageTabView()

  /// L'onglet Mirror : la caméra n'est allumée que pendant qu'il est à l'écran (voir
  /// `updateCameraActivity()`).
  private let mirrorTab = CameraMirrorView(
    viewModel: CameraMirrorViewModel(
      provider: MockCameraMirrorProvider.fromLaunchArguments() ?? AVCameraMirrorService()))

  /// L'onglet Terminal : le cadre qui reçoit la vue de la session partagée.
  private let terminalTab = TerminalTabView()

  /// L'onglet Color : aperçu, trois écritures et couleurs récentes.
  private let colorPickerTab = ColorPickerTabView()

  /// Relayé jusqu'au contrôleur : « Pick », une récente choisie, « Clear ».
  var onColorPickerAction: ((ColorPickerAction) -> Void)? {
    didSet { colorPickerTab.onAction = onColorPickerAction }
  }

  /// Le shell partagé par toutes les fenêtres du panneau (voir `TerminalSession`).
  var terminalSession: TerminalSession?

  /// Vrai quand le panneau est déplié sur l'onglet Terminal ou Notes : c'est alors lui qui doit avoir le clavier.
  var wantsKeyboard: Bool {
    isExpanded && (selectedTab == .terminal || selectedTab == .notes)
  }

  /// Une demande à laquelle on peut répondre est affichée sur l'onglet AI : la fenêtre peut prendre le
  /// clavier au clic (sans le voler à l'ouverture), pour les touches de la carte et ses champs.
  var cardAcceptsKeyboard: Bool { isExpanded && selectedTab == .ai && usageTab.showsAnswerablePrompt }

  /// Échap sur la carte : le contrôleur replie le panneau.
  var onFoldRequested: (() -> Void)? {
    get { usageTab.onPromptFoldRequested }
    set { usageTab.onPromptFoldRequested = newValue }
  }

  /// Appelé quand `wantsKeyboard` a pu changer ; la fenêtre en tire le focus clavier.
  var onKeyboardNeedChanged: (() -> Void)?

  private(set) var selectedTab: NotchTab = .global

  /// Balayage d'onglet en cours (trackpad ou glisser à la souris).
  private var swipe = TabSwipeTracker()

  /// Place de repos de la capsule, relevée à chaque mise en page : c'est de là qu'elle part
  /// en sortant, et c'est là qu'elle revient en entrant.
  private var capsuleRestingPosition: CGPoint = .zero

  /// Silhouette courante, retenue pour le test de contact : le cadre de la fenêtre vaut
  /// toujours le cadre déplié, donc la vue est bien plus large que ce qu'elle dessine, et
  /// seule la forme peinte doit répondre (voir `hitTest(_:)`).
  private var silhouette: CGPath?
  private var shapeBounds: CGRect = .zero
  private var transitionGeneration = 0
  private var shapeGeneration = 0
  private var waitingForShape = false
  private var waitingForFade = false
  private var verticalStart: CGPath?
  private var verticalTarget: CGPath?
  private var verticalSwipe = TabSwipeTracker()
  private var verticalReleaseVelocity: CGFloat = 0
  var isTrackingVerticalSwipe: Bool { verticalSwipe.isSwiping }
  private let peekTitle = NSTextField(labelWithString: "")

  /// Taille de la silhouette repliée, décidée par l'écran : l'encoche matérielle n'a pas les
  /// mêmes dimensions d'un Mac à l'autre, et une pastille les remplace quand il n'y en a pas.
  var collapsedSize: NSSize = NotchPanelGeometry.pillSize {
    didSet {
      guard collapsedSize != oldValue else { return }
      shapeBounds = .zero
      needsLayout = true
    }
  }

  /// Écart entre le bord du haut et la silhouette repliée : non nul pour la pastille flottante
  /// d'un écran sans encoche (voir `NotchPanelGeometry.collapsedTopGap`).
  var collapsedTopGap: CGFloat = 0 {
    didSet {
      guard collapsedTopGap != oldValue else { return }
      shapeBounds = .zero
      needsLayout = true
    }
  }

  var hasHardwareNotch = false {
    didSet {
      guard hasHardwareNotch != oldValue else { return }
      shapeBounds = .zero
      needsLayout = true
    }
  }

  private var stayAwakeNotchExtension: CGFloat {
    hasHardwareNotch && stayAwakeState.isActive ? StayAwakeIdleIndicator.notchExtension : 0
  }

  private(set) var isExpanded = false

  /// Curseur sur la zone sensible en mode « clic » : la silhouette repliée grossit un peu.
  private(set) var isHoverPeeking = false

  func setHoverPeek(_ peeking: Bool) {
    guard peeking != isHoverPeeking else { return }
    isHoverPeeking = peeking
    guard !isExpanded else { return }
    layoutNowPlaying()
    applyShape(expanded: false, animated: true)
  }

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
    usageTab.onPromptContentChanged = { [weak self] in self?.promptContentChanged() }
    usageTab.onStartAgent = { [weak self] in self?.select(.terminal, animated: true) }
    contentContainer.addSubview(mirrorTab)

    globalTab.addSubview(weekRow)
    // Le lecteur se range sous la semaine dans l'onglet Global, et y reste : au repos il
    // montre « Nothing playing ».
    nowPlayingRow.apply(nil)
    nowPlayingRow.onCommand = { [weak self] command in self?.onNowPlayingCommand?(command) }
    nowPlayingRow.onSeek = { [weak self] seconds in self?.onNowPlayingSeek?(seconds) }
    globalTab.addSubview(nowPlayingRow)
    contentContainer.addSubview(globalTab)

    calendarTab.addSubview(calendarWidget)
    contentContainer.addSubview(calendarTab)
    contentContainer.addSubview(fileTray)
    transformView.isHidden = true
    transformView.onClose = { [weak self] in self?.closeTransform(animated: true) }
    contentContainer.addSubview(transformView)
    contentContainer.addSubview(clipboardTab)
    contentContainer.addSubview(notesTab)
    contentContainer.addSubview(terminalTab)
    contentContainer.addSubview(colorPickerTab)
    contentContainer.addSubview(stayAwakeTab)
    contentContainer.addSubview(analyticsTab)
    stayAwakeButton.onClick = { [weak self] in self?.toggleStayAwakeTab() }
    contentContainer.addSubview(stayAwakeButton)
    usageChip.isHidden = true
    usageChip.onClick = { [weak self] in self?.toggleAnalyticsTab() }
    analyticsTab.onMonthSummaryChanged = { [weak self] summary in
      self?.monthSummary = summary
      self?.updateUsageChip()
    }
    contentContainer.addSubview(usageChip)
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
    peekTitle.font = .systemFont(ofSize: 12, weight: .medium)
    peekTitle.textColor = .white
    peekTitle.lineBreakMode = .byTruncatingTail
    peekTitle.maximumNumberOfLines = 1
    peekTitle.alignment = .center
    peekTitle.wantsLayer = true
    peekTitle.layer?.opacity = 0
    addSubview(peekTitle)
    // Réglées comme la pochette du lecteur, qui est l'état d'arrivée du dépliage.
    flightArtwork.badgeScale = 0.36
    flightArtwork.badgeInset = 4
    nowPlayingFlight.wantsLayer = true
    nowPlayingFlight.addSubview(flightArtwork)
    nowPlayingFlight.addSubview(flightVisualizer)
    nowPlayingFlight.isHidden = true
    addSubview(nowPlayingFlight)
    launchGreeting.layer?.opacity = 0
    addSubview(launchGreeting)
    deviceStatusPill.layer?.opacity = 0
    addSubview(deviceStatusPill)
    agentEventPill.layer?.opacity = 0
    addSubview(agentEventPill)
    mailMessagePill.layer?.opacity = 0
    addSubview(mailMessagePill)
    addSubview(stayAwakeIdleIndicator)
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
    stayAwakeButton.applyPalette(palette)
    usageChip.applyPalette(palette)
    stayAwakeTab.applyPalette(palette)
    colorPickerTab.applyPalette(palette)
    strokeLayer.strokeColor = palette.strokeColor
  }

  func apply(stayAwakeState: StayAwakeState) {
    let toggled = self.stayAwakeState.isActive != stayAwakeState.isActive
    self.stayAwakeState = stayAwakeState
    stayAwakeTab.apply(stayAwakeState)
    if toggled {
      updateStayAwakeButton()
      if !isExpanded, hasHardwareNotch {
        layoutNowPlaying()
        applyShape(expanded: false, animated: true)
      }
      updateStayAwakeIdleIndicator(animated: true)
    }
  }

  private func updateStayAwakeIdleIndicator(animated: Bool, shapeSettled: Bool = false) {
    let revealingNotch = hasHardwareNotch && !shapeSettled
      && backgroundLayer.animation(forKey: "path") != nil && stayAwakeIdleIndicator.layer?.opacity == 0
    stayAwakeIdleIndicator.apply(
      active: stayAwakeState.isActive && !revealingNotch,
      expanded: isExpanded || waitingForFade,
      animated: animated)
  }

  /// Jaune tant que le Mac est tenu éveillé ; sinon, clair quand l'onglet est ouvert.
  private func updateStayAwakeButton() {
    if stayAwakeState.isActive {
      stayAwakeButton.tintOverride = StayAwakeStyle.accent
    } else if selectedTab == .stayAwake {
      stayAwakeButton.tintOverride =
        OverlayPalette.resolved(for: effectiveAppearance).tabActiveContent
    } else {
      stayAwakeButton.tintOverride = nil
    }
  }

  /// Montre la pastille tant que le mois est lu et que la vue Transform n'a pas pris la place des
  /// boutons ; allumée quand l'onglet Analytics est ouvert.
  private func updateUsageChip() {
    usageChip.isActive = selectedTab == .analytics
    guard let monthSummary else {
      usageChip.isHidden = true
      return
    }
    usageChip.text = ActivityFormatting.chip(monthSummary)
    usageChip.isHidden = transformSourceURL != nil
    layoutUsageChip()
  }

  private func toggleAnalyticsTab() {
    if selectedTab == .analytics {
      select(tabBeforeAnalytics, animated: true)
    } else {
      // Depuis Stay Awake, c'est l'onglet d'avant la tasse qu'un second clic doit ramener.
      tabBeforeAnalytics = selectedTab == .stayAwake ? tabBeforeStayAwake : selectedTab
      select(.analytics, animated: true)
    }
  }

  /// Posée au bord gauche du panneau, sur la marge du contenu (le glyphe tombe sur ce bord, comme
  /// l'engrenage à droite), centrée sur la hauteur des boutons.
  private func layoutUsageChip() {
    let width = usageChip.fittingWidth
    let height = NotchUsageChipView.fittingHeight
    usageChip.frame = NSRect(
      x: panelRect.minX + NotchPanelGeometry.contentInsetX - NotchUsageChipView.edgePadding,
      y: stayAwakeButton.frame.midY - height / 2,
      width: width, height: height)
  }

  private func toggleStayAwakeTab() {
    if selectedTab == .stayAwake {
      select(tabBeforeStayAwake, animated: true)
    } else {
      tabBeforeStayAwake = selectedTab
      select(.stayAwake, animated: true)
    }
  }

  // MARK: - État

  func apply(usageState: ClaudeUsageState, animated: Bool) {
    analyticsTab.apply(claude: usageState)
  }

  var onLoadActivity: ((Int) -> Void)? {
    didSet { analyticsTab.onLoadActivity = onLoadActivity }
  }

  func apply(activityRecords: [ActivityRecord], isLoading: Bool) {
    analyticsTab.apply(activityRecords: activityRecords, isLoading: isLoading)
  }

  func apply(codexUsageState: CodexUsageState) {
    analyticsTab.apply(codex: codexUsageState)
  }

  func apply(copilotUsageState: CopilotUsageState) {
    analyticsTab.apply(copilot: copilotUsageState)
  }

  /// Ce que le curseur doit encore toucher pour garder le panneau déplié : le panneau de
  /// l'onglet affiché et la capsule, et non le cadre entier de la fenêtre, qui est plus haut
  /// que les onglets courts.
  var interactiveFrame: NSRect {
    // Le cadre visé ne suffit pas pendant le glissement d'un onglet à l'autre : la capsule
    // est encore peinte à son ancienne place, et le curseur posé dessus ne doit pas
    // refermer le panneau.
    NotchPanelGeometry.panelRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
      .union(
        NotchPanelGeometry.capsuleRect(in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
      )
      .union(capsuleOnScreenFrame)
  }

  /// Cadre où la capsule est réellement peinte, glissement compris — celui du modèle n'est
  /// atteint qu'à la fin du ressort.
  private var capsuleOnScreenFrame: CGRect {
    capsule.layer?.presentation()?.frame ?? capsule.frame
  }

  // MARK: - Onglets

  private var tabContentViews: [NSView] {
    [
      globalTab, calendarTab, fileTray, clipboardTab, notesTab, mirrorTab, usageTab, terminalTab,
      colorPickerTab, stayAwakeTab, analyticsTab,
    ]
  }

  private func contentView(for tab: NotchTab) -> NSView {
    switch tab {
    case .global: globalTab
    case .calendar: calendarTab
    case .tray: fileTray
    case .clipboard: clipboardTab
    case .notes: notesTab
    case .mirror: mirrorTab
    case .ai: usageTab
    case .terminal: terminalTab
    case .colorPicker: colorPickerTab
    case .stayAwake: stayAwakeTab
    case .analytics: analyticsTab
    }
  }

  func apply(clipboardItems: [ClipboardItem]) {
    clipboardTab.apply(items: clipboardItems)
  }

  func apply(notes: [Note]) {
    notesTab.apply(notes: notes)
  }

  func apply(colorPickerState: ColorPickerState) {
    colorPickerTab.apply(colorPickerState)
  }

  func apply(agendaState: CalendarAgendaState) {
    calendarWidget.apply(agendaState)
    // Le magasin a pu changer : le jour choisi de la bande se relit avec le reste.
    weekRow.reloadSelectedDay()
  }

  /// Remet la semaine et le calendrier à la bonne date — appelé à chaque dépliage,
  /// le panneau restant en mémoire d'un survol à l'autre et parfois d'un jour à l'autre.
  func refreshWeek() {
    weekRow.refresh()
    clipboardTab.refreshAges()
    calendarWidget.refresh()
  }

  func select(_ tab: NotchTab, animated: Bool) {
    guard tab != selectedTab else { return }
    closeTransform(animated: false)
    cancelNowPlayingFlight()
    let outgoing = contentView(for: selectedTab)
    let travel: CGFloat = tab.rawValue > selectedTab.rawValue ? 12 : -12
    selectedTab = tab
    capsule.select(tab, animated: animated)
    applySelection(animated: animated, travel: travel, outgoing: outgoing)
    // Seuls les onglets AI et Mirror sont plus hauts : la silhouette et la capsule suivent leur hauteur.
    layoutTabBodies()
    moveCapsuleToSelectedTab(animated: animated)
    if isExpanded { applyShape(expanded: true, animated: animated) }
    updateCameraActivity()
    updateTerminal()
    updateStayAwakeButton()
    updateUsageChip()
  }

  /// Le shell n'est rattaché à cette fenêtre — et lancé — que panneau déplié sur l'onglet
  /// Terminal. Replié, la vue reste où elle est : la session ne dépend pas de l'affichage.
  private func updateTerminal() {
    if wantsKeyboard, let terminalSession { terminalTab.attach(terminalSession) }
    onKeyboardNeedChanged?()
  }

  /// Met le clavier dans le terminal, ou dans l'éditeur de l'onglet Notes.
  func focusKeyboardTarget() {
    if selectedTab == .notes {
      notesTab.focusEditor()
    } else {
      terminalTab.focusTerminal()
    }
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
  private func applySelection(animated: Bool, travel: CGFloat = 0, outgoing: NSView? = nil) {
    let active = contentView(for: selectedTab)

    for view in tabContentViews {
      let isActive = view === active
      if animated, OverlayAnimation.allowsMotion, isExpanded, view === outgoing,
        let layer = view.layer {
        let shift = layer.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat ?? 0
        CATransaction.begin()
        PanelFold.fade(layer, to: 0)
        layer.springAnimate(keyPath: "transform.translation.x", to: shift - travel)
        CATransaction.setCompletionBlock { [weak self, weak view] in
          MainActor.assumeIsolated {
            guard let self, let view, view !== self.contentView(for: self.selectedTab),
              view.layer?.animation(forKey: "opacity") == nil else { return }
            view.isHidden = true
          }
        }
        CATransaction.commit()
        continue
      }
      resetSwipeOffset(of: view, animated: false)
      view.isHidden = !isActive
      view.layer?.removeAnimation(forKey: "contentReveal")
      view.layer?.opacity = isActive ? 1 : 0
      if animated, isActive {
        view.layer?.springReveal(x: travel, y: 0)
      }
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
    let visibleShape = backgroundLayer.presentation()?.path ?? silhouette
    guard visibleShape.contains(local) ||
      (isExpanded && capsuleShape().contains(local) && isContentVisible)
    else {
      return nil
    }
    if !isExpanded || !isContentVisible { return self }
    let hit = super.hitTest(point)
    if hit === peekTitle { return self }
    if let hit, tabContentViews.contains(where: {
      $0 !== contentView(for: selectedTab) && (hit === $0 || hit.isDescendant(of: $0))
    }) { return self }
    return hit
  }

  /// Le contour de la capsule, pour le test de contact : son cadre est un rectangle, mais ses
  /// extrémités sont arrondies et ce qui les déborde doit passer dessous.
  private func capsuleShape() -> CGPath {
    let frame = capsuleOnScreenFrame
    let radius = frame.height / 2
    return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  /// Seul le centre libre de l'en-tête démarre un geste vertical.
  func resetSelectionWhenFolded() {
    guard !waitingForFade, verticalStart == nil,
      backgroundLayer.animation(forKey: "path") == nil else { return }
    select(.global, animated: false)
  }

  func acceptsVerticalSwipe(at point: NSPoint) -> Bool {
    let path = backgroundLayer.presentation()?.path ?? silhouette
    return path?.contains(point) == true &&
      abs(point.x - bounds.midX) <= collapsedSize.width / 2 &&
      point.y >= bounds.maxY - collapsedTopGap - collapsedSize.height
  }

  func trackVerticalSwipe(_ event: NSEvent) -> Bool? {
    if event.phase.contains(.began) { cancelVerticalSwipe() }
    if event.phase.contains(.cancelled) {
      cancelVerticalSwipe()
      return nil
    }
    if event.phase.contains(.ended) {
      let velocity = verticalSwipe.releaseVelocity(at: event.timestamp)
      let offset = verticalSwipe.offset
      let direction = verticalSwipe.end(velocity: velocity)
      let commits = direction == (isExpanded ? .previous : .next)
      if commits {
        let travel = max(1, panelRect.height - collapsedSize.height - abs(offset))
        verticalReleaseVelocity = min(8, abs(velocity) / travel)
      } else {
        cancelVerticalSwipe()
      }
      return commits ? !isExpanded : nil
    }

    let dy = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
    guard verticalSwipe.move(dx: -dy, dy: event.scrollingDeltaX, timestamp: event.timestamp) else { return nil }
    let travel = verticalSwipe.offset * (isExpanded ? 1 : -1)
    guard OverlayAnimation.allowsMotion, travel > 0 || verticalStart != nil else { return nil }

    if verticalStart == nil {
      verticalStart = backgroundLayer.presentation()?.path ?? silhouette
      verticalTarget = isExpanded ? foldedPath : expandedPath()
    }
    guard let verticalStart, let verticalTarget else { return nil }
    let progress = min(1, max(0, travel / max(1, panelRect.height - collapsedSize.height)))
    guard let path = Self.interpolate(from: verticalStart, to: verticalTarget, progress: progress)
    else { return nil }
    PanelFold.apply(path: path, to: [backgroundLayer, strokeLayer, contentMask], in: bounds,
                    to: 0, animated: false)
    if let layer = contentContainer.layer { PanelFold.fade(layer, to: 0) }
    if let layer = capsule.layer { PanelFold.fade(layer, to: 0) }
    return nil
  }

  private var isContentVisible: Bool {
    guard let layer = contentContainer.layer else { return false }
    return (layer.presentation()?.opacity ?? layer.opacity) > 0.1
  }

  func cancelVerticalSwipe() {
    verticalSwipe.cancel()
    verticalReleaseVelocity = 0
    guard verticalStart != nil else { return }
    verticalStart = nil
    verticalTarget = nil
    waitingForShape = isExpanded
    applyShape(expanded: isExpanded, animated: true, force: true)
    if isExpanded {
      GlassReveal.play(on: contentContainer)
      applyCapsuleReveal(animated: true)
    }
  }

  private static func interpolate(from: CGPath, to: CGPath, progress: CGFloat) -> CGPath? {
    func elements(_ path: CGPath) -> [(CGPathElementType, [CGPoint])] {
      var result: [(CGPathElementType, [CGPoint])] = []
      path.applyWithBlock { pointer in
        let element = pointer.pointee
        let count: Int
        switch element.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        default: count = 0
        }
        result.append((element.type, Array(UnsafeBufferPointer(start: element.points, count: count))))
      }
      return result
    }

    let start = elements(from)
    let end = elements(to)
    guard start.count == end.count else { return nil }
    let path = CGMutablePath()
    for (first, last) in zip(start, end) {
      guard first.0 == last.0 else { return nil }
      let points = zip(first.1, last.1).map { a, b in
        CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
      }
      switch first.0 {
      case .moveToPoint: path.move(to: points[0])
      case .addLineToPoint: path.addLine(to: points[0])
      case .addQuadCurveToPoint: path.addQuadCurve(to: points[1], control: points[0])
      case .addCurveToPoint: path.addCurve(to: points[2], control1: points[0], control2: points[1])
      case .closeSubpath: path.closeSubpath()
      @unknown default: return nil
      }
    }
    return path
  }

  // MARK: - Balayage d'onglets

  /// Balayage à deux doigts. Les vues qui défilent d'elles-mêmes (la semaine, le presse-papiers)
  /// consomment leurs événements et ne les relaient pas ici ; ne reste que le fond du panneau
  /// et ce que ces vues ne savent pas défiler. Les molettes sans phase (souris) sont ignorées :
  /// à la souris, on glisse.
  override func scrollWheel(with event: NSEvent) {
    guard isExpanded, isContentVisible, event.hasPreciseScrollingDeltas, !event.phase.isEmpty else {
      super.scrollWheel(with: event)
      return
    }
    if event.phase.contains(.began) { swipe.cancel() }
    if event.phase.contains(.cancelled) {
      swipe.cancel()
      settleSwipe(direction: nil)
      return
    }

    if swipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, timestamp: event.timestamp) {
      followSwipe()
    } else if !swipe.isSwiping {
      super.scrollWheel(with: event)
    }
    if event.phase.contains(.ended) {
      let velocity = swipe.releaseVelocity(at: event.timestamp)
      settleSwipe(direction: swipe.end(velocity: velocity), velocity: velocity)
    }
  }

  override func mouseDown(with event: NSEvent) {
    swipe.cancel()
  }

  override func mouseDragged(with event: NSEvent) {
    guard isExpanded, isContentVisible else { return }
    if swipe.move(dx: event.deltaX, dy: -event.deltaY, timestamp: event.timestamp) { followSwipe() }
  }

  override func mouseUp(with event: NSEvent) {
    guard swipe.isSwiping else {
      swipe.cancel()
      return
    }
    let velocity = swipe.releaseVelocity(at: event.timestamp)
    settleSwipe(direction: swipe.end(velocity: velocity), velocity: velocity)
  }

  /// L'onglet affiché suit le doigt, atténué pour qu'on sente qu'il va partir. La résistance
  /// croît aux deux bouts de la rangée, où il n'y a pas d'onglet voisin.
  private func followSwipe() {
    guard OverlayAnimation.allowsMotion, let layer = contentView(for: selectedTab).layer else { return }
    let direction: TabSwipeTracker.Direction = swipe.offset < 0 ? .next : .previous
    let resistance: CGFloat = selectedTab.neighbor(direction) == nil ? 0.25 : 1
    let shift = swipe.offset * resistance
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.removeAnimation(forKey: "transform.translation.x")
    layer.removeAnimation(forKey: "contentReveal")
    layer.removeAnimation(forKey: "opacity")
    layer.transform = CATransform3DMakeTranslation(shift, 0, 0)
    layer.opacity = Float(max(0.3, 1 - abs(shift) / 300))
    CATransaction.commit()
  }

  /// Fin du geste : change d'onglet si un voisin existe, sinon ramène l'onglet à sa place.
  private func settleSwipe(direction: TabSwipeTracker.Direction?, velocity: CGFloat = 0) {
    let current = contentView(for: selectedTab)
    guard let direction, let target = selectedTab.neighbor(direction) else {
      resetSwipeOffset(of: current, animated: true, velocity: velocity)
      return
    }
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    select(target, animated: true)
  }

  private func resetSwipeOffset(of view: NSView, animated: Bool, velocity: CGFloat = 0) {
    guard let layer = view.layer else { return }
    let hadOffset = !CATransform3DIsIdentity(layer.transform) || layer.opacity != 1
    let shift = layer.presentation()?.value(forKeyPath: "transform.translation.x")
      ?? layer.value(forKeyPath: "transform.translation.x")
    if animated, hadOffset, OverlayAnimation.allowsMotion {
      PanelFold.fade(layer, to: 1)
      let distance = -(shift as? CGFloat ?? 0)
      let relativeVelocity = abs(distance) > 1 ? max(-8, min(8, velocity / distance)) : 0
      layer.springAnimate(
        keyPath: "transform.translation.x", to: 0, from: shift, preset: .gentle,
        velocity: relativeVelocity)
    } else {
      layer.removeAnimation(forKey: "transform.translation.x")
      layer.removeAnimation(forKey: "opacity")
      layer.transform = CATransform3DIdentity
      layer.opacity = 1
    }
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

    if shapeBounds != bounds {
      shapeBounds = bounds
      applyShape(expanded: isExpanded, animated: false, force: true)
    }

    // Le panneau n'occupe pas tout le cadre : la bande basse revient à la capsule. Le
    // conteneur, lui, garde le cadre entier — son masque est la silhouette, qui est décrite
    // dans ce repère-là.
    let panel = panelRect
    contentContainer.frame = bounds
    nowPlayingFlight.frame = bounds

    capsule.frame = NotchPanelGeometry.capsuleRect(
      in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
    // La place de repos est relevée ici, une fois le cadre posé et avant que l'entrée ou la
    // sortie ne décale le calque : c'est le point d'arrivée de la course, et il ne peut pas
    // être lu plus tard, quand la capsule est justement ailleurs.
    capsuleRestingPosition = capsule.layer?.position ?? .zero
    if capsule.layer?.animation(forKey: "position") == nil {
      applyCapsuleReveal(animated: false)
    }

    let wingsY = panel.maxY - collapsedTopGap - collapsedSize.height
    let stayAwakeIndicatorSize = StayAwakeIdleIndicator.size
    let stayAwakeIndicatorY = hasHardwareNotch
      ? wingsY - StayAwakeIdleIndicator.notchExtension / 2
      : wingsY + collapsedSize.height / 2
    stayAwakeIdleIndicator.frame = NSRect(
      x: bounds.midX - stayAwakeIndicatorSize / 2,
      y: stayAwakeIndicatorY - stayAwakeIndicatorSize / 2,
      width: stayAwakeIndicatorSize, height: stayAwakeIndicatorSize)
    launchGreeting.frame = NSRect(
      x: bounds.midX - collapsedSize.width / 2 - DeviceStatusPillView.wingWidth,
      y: wingsY, width: DeviceStatusPillView.wingWidth, height: collapsedSize.height)
    let deviceWidth = collapsedSize.width + 2 * DeviceStatusPillView.wingWidth
    deviceStatusPill.frame = NSRect(
      x: bounds.midX - deviceWidth / 2, y: wingsY, width: deviceWidth, height: collapsedSize.height)
    let agentWidth = collapsedSize.width + 2 * AgentEventPillView.wingWidth
    agentEventPill.frame = NSRect(
      x: bounds.midX - agentWidth / 2, y: wingsY, width: agentWidth, height: collapsedSize.height)
    let mailWidth = collapsedSize.width + 2 * MailMessagePillView.wingWidth
    mailMessagePill.frame = NSRect(
      x: bounds.midX - mailWidth / 2, y: wingsY, width: mailWidth, height: collapsedSize.height)
    layoutNowPlaying()
    layoutTabBodies()
  }

  private func layoutNowPlaying() {
    let media = nowPlayingSize
    nowPlayingWings.lift = collapsedTopGap > 0 ? 0 : NowPlayingWingsView.extraHeight / 2
    nowPlayingWings.frame = NSRect(
      x: bounds.midX - media.width / 2,
      y: bounds.maxY - collapsedTopGap - media.height,
      width: media.width, height: media.height)
    peekTitle.frame = NSRect(
      x: bounds.midX - (media.width - 36) / 2,
      y: nowPlayingWings.frame.minY - 19 - stayAwakeNotchExtension,
      width: media.width - 36, height: 16)
    if let layer = peekTitle.layer, !shouldShowPeekTitle {
      PanelFold.fade(layer, to: 0)
    }
  }

  private var shouldShowPeekTitle: Bool {
    isHoverPeeking && !isExpanded && showsNowPlayingWingsWhenFolded
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

  /// Hauteur de l'onglet AI quand il montre une demande : celle de la carte, bornée par la fenêtre.
  private var aiPromptExtraHeight: CGFloat {
    guard let height = usageTab.promptHeight(width: usageTab.bounds.width > 0
      ? usageTab.bounds.width : NotchPanelGeometry.contentWidth(for: .ai))
    else { return 0 }
    let clamped = min(max(height, 150), NotchPanelGeometry.tabContentHeight)
    return clamped - NotchPanelGeometry.aiTabHeight
  }

  /// La carte d'agent a changé de contenu : le panneau suit sa hauteur, au même ressort qu'un
  /// changement d'onglet, et la fenêtre reprend ou rend le clavier.
  private func promptContentChanged() {
    if selectedTab == .ai { refreshPanelHeight(animated: isExpanded) }
    onKeyboardNeedChanged?()
  }

  private var panelExtraHeight: CGFloat {
    if selectedTab == .ai { return aiPromptExtraHeight }
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
    transformView.layer?.springReveal()
  }

  private func closeTransform(animated: Bool) {
    guard transformSourceURL != nil else { return }
    transformSourceURL = nil
    applyTransformVisibility()
    refreshPanelHeight(animated: animated)
    if animated { fileTray.layer?.springReveal(y: 8) }
  }

  private func applyTransformVisibility() {
    let open = transformSourceURL != nil
    transformView.isHidden = !open
    fileTray.isHidden = open || selectedTab != .tray
    gearButton.isHidden = open
    launchButton.isHidden = open
    stayAwakeButton.isHidden = open
    capsule.isHidden = open
    updateUsageChip()
  }

  /// Corps des onglets : tout l'intérieur du panneau. Les onglets l'occupent en entier et se
  /// relaient dedans. Séparé de `layout()` pour qu'un changement d'onglet puisse le refaire sans
  /// poser sèchement la silhouette, qui s'anime.
  private func layoutTabBodies() {
    let inset = NotchPanelGeometry.contentInsetX
    let panel = panelRect
    let island = collapsedTopGap > 0
    let body = NotchPanelGeometry.tabBodyRect(
      in: panel, collapsedHeight: collapsedSize.height, island: island)
    for view in tabContentViews {
      view.frame = body
    }
    transformView.frame = NotchPanelGeometry.transformBodyRect(
      in: panel, collapsedHeight: collapsedSize.height, island: island)

    // Dans le repère de `globalTab` : la rangée de la semaine occupe toute la largeur.
    let weekHeight = NotchPanelGeometry.weekStripHeight
    weekRow.frame = NSRect(
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
      y: panel.maxY - collapsedSize.height / 2 - gearSize / 2
        - (collapsedTopGap > 0 ? NotchPanelGeometry.islandGearDrop : NotchPanelGeometry.gearDrop),
      width: gearSize,
      height: gearSize
    )
    launchButton.frame = gearButton.frame.offsetBy(dx: -gearSize, dy: 0)
    stayAwakeButton.frame = launchButton.frame.offsetBy(dx: -gearSize, dy: 0)
    layoutUsageChip()

    // Mirror pose son cercle lui-même, contre le bas du panneau : il a donc tout le cadre du
    // panneau Mirror, quel que soit l'onglet affiché.
    mirrorTab.frame = NotchPanelGeometry.panelRect(in: bounds, tab: .mirror)
  }

  /// Descend ou remonte la capsule sous le panneau de l'onglet affiché. Au ressort du
  /// dépliage, puisque la silhouette se redimensionne en même temps.
  private func moveCapsuleToSelectedTab(animated: Bool) {
    guard let layer = capsule.layer else { return }
    let previous = layer.position
    capsule.frame = NotchPanelGeometry.capsuleRect(
      in: bounds, tab: selectedTab, extraHeight: panelExtraHeight)
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

    let target =
      isExpanded
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

  // MARK: - Accueil au lancement

  func showLaunchGreeting() {
    guard !isExpanded, !isShowingDeviceStatus, !isShowingAgentEvent, !isShowingMailMessage else {
      return
    }
    isShowingLaunchGreeting = true
    layoutSubtreeIfNeeded()
    launchGreeting.start()
    applyShape(expanded: false, animated: true)
    if let layer = launchGreeting.layer {
      layer.opacity = 1
      layer.springReveal(y: 6)
    }
    updateNowPlayingWingsOpacity(animated: true)
  }

  func hideLaunchGreeting(animated: Bool = true) {
    guard isShowingLaunchGreeting else { return }
    isShowingLaunchGreeting = false
    launchGreeting.stop()
    if let layer = launchGreeting.layer {
      layer.removeAnimation(forKey: "contentReveal")
      if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
    }
    applyShape(expanded: isExpanded, animated: animated)
    updateNowPlayingWingsOpacity(animated: animated)
  }

  // MARK: - Pastille d'appareil

  func showDeviceStatus(_ status: DeviceStatus) {
    // Dépliée, la silhouette occupe déjà toute la place.
    guard !isExpanded else { return }
    hideLaunchGreeting(animated: false)
    deviceStatusPill.apply(status)
    deviceStatusPill.layoutSubtreeIfNeeded()
    isShowingDeviceStatus = true
    applyShape(expanded: false, animated: true)
    if let layer = deviceStatusPill.layer {
      layer.opacity = 1
      layer.springReveal(y: 6)
    }
    updateNowPlayingWingsOpacity(animated: true)
  }

  func hideDeviceStatus(animated: Bool = true) {
    guard isShowingDeviceStatus else { return }
    isShowingDeviceStatus = false
    applyShape(expanded: isExpanded, animated: animated)
    if let layer = deviceStatusPill.layer {
      layer.removeAnimation(forKey: "contentReveal")
      if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
    }
    updateNowPlayingWingsOpacity(animated: animated)
  }

  // MARK: - Notification d'agent

  var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
    get { usageTab.onAgentDecision }
    set { usageTab.onAgentDecision = newValue }
  }

  func apply(agentPrompt: AgentEvent?, queued: Int = 0) {
    usageTab.apply(agentPrompt: agentPrompt, queued: queued)
    promptContentChanged()
  }

  func apply(agentActivity: AgentActivity?) {
    usageTab.apply(agentActivity: agentActivity)
  }

  func apply(agentSessions: [AgentSession], selectedID: String?) {
    usageTab.apply(agentSessions: agentSessions, selectedID: selectedID)
    onKeyboardNeedChanged?()
  }

  var onAgentSteer: ((String, String) -> Void)? {
    get { usageTab.onAgentSteer }
    set { usageTab.onAgentSteer = newValue }
  }

  var onAgentSessionSelected: ((String) -> Void)? {
    get { usageTab.onAgentSessionSelected }
    set { usageTab.onAgentSessionSelected = newValue }
  }

  var onAgentPromote: ((AgentEvent) -> Void)? {
    get { usageTab.onAgentPromote }
    set { usageTab.onAgentPromote = newValue }
  }

  func showAgentEvent(_ event: AgentEvent, queued: Int = 0, deadline: Date? = nil) {
    guard !isExpanded else { return }
    hideDeviceStatus(animated: false)
    hideMailMessage(animated: false)
    hideLaunchGreeting(animated: false)
    agentEventPill.apply(
      event, notchWidth: collapsedSize.width, queued: queued, deadline: deadline)
    agentEventPill.layoutSubtreeIfNeeded()
    isShowingAgentEvent = true
    applyShape(expanded: false, animated: true)
    if let layer = agentEventPill.layer {
      layer.opacity = 1
      layer.springReveal(y: 6)
    }
    updateNowPlayingWingsOpacity(animated: true)
  }

  func hideAgentEvent(animated: Bool = true) {
    guard isShowingAgentEvent else { return }
    isShowingAgentEvent = false
    applyShape(expanded: isExpanded, animated: animated)
    if let layer = agentEventPill.layer {
      layer.removeAnimation(forKey: "contentReveal")
      if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
    }
    updateNowPlayingWingsOpacity(animated: animated)
  }

  // MARK: - Courrier

  func showMailMessage(_ message: MailMessage) {
    guard !isExpanded else { return }
    hideDeviceStatus(animated: false)
    hideAgentEvent(animated: false)
    hideLaunchGreeting(animated: false)
    mailMessagePill.apply(message, notchWidth: collapsedSize.width)
    mailMessagePill.layoutSubtreeIfNeeded()
    isShowingMailMessage = true
    applyShape(expanded: false, animated: true)
    if let layer = mailMessagePill.layer {
      layer.opacity = 1
      layer.springReveal(y: 6)
    }
    updateNowPlayingWingsOpacity(animated: true)
  }

  func hideMailMessage(animated: Bool = true) {
    guard isShowingMailMessage else { return }
    isShowingMailMessage = false
    applyShape(expanded: isExpanded, animated: animated)
    if let layer = mailMessagePill.layer {
      layer.removeAnimation(forKey: "contentReveal")
      if animated { PanelFold.fade(layer, to: 0) } else { layer.opacity = 0 }
    }
    updateNowPlayingWingsOpacity(animated: animated)
  }

  // MARK: - Lecture en cours

  /// Appelé par la ligne de pilotage : précédent, lecture/pause, suivant.
  var onNowPlayingCommand: ((NowPlayingCommand) -> Void)?
  /// Position choisie sur la barre de progression du lecteur, en secondes.
  var onNowPlayingSeek: ((TimeInterval) -> Void)?

  /// Lit les événements d'un jour pour la rangée de la semaine.
  var dayAgendaLoader: ((Date) async -> CalendarAgendaState)? {
    get { weekRow.dayLoader }
    set {
      weekRow.dayLoader = newValue
      calendarWidget.dayLoader = newValue
    }
  }

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
      cancelNowPlayingFlight()
      applyShape(expanded: isExpanded, animated: true)
      updateNowPlayingWingsOpacity(animated: true)
      return
    }

    peekTitle.stringValue = state.title
    nowPlayingWings.apply(state)
    flightArtwork.setArtwork(state.artwork)
    flightArtwork.setSource(bundleIdentifier: state.bundleIdentifier)
    flightVisualizer.setAnimating(state.isPlaying)
    guard !isShowingNowPlaying else { return }
    isShowingNowPlaying = true
    applyShape(expanded: isExpanded, animated: true)
    updateNowPlayingWingsOpacity(animated: true)
  }

  /// Les ailes de lecture ne se voient que repliées et sans pastille Bluetooth par-dessus.
  private func updateNowPlayingWingsOpacity(animated: Bool) {
    if !shouldShowPeekTitle, let layer = peekTitle.layer {
      PanelFold.fade(layer, to: 0)
    }
    guard let layer = nowPlayingWings.layer else { return }
    let visible = showsNowPlayingWingsWhenFolded && !isExpanded
    let opacity: Float = visible ? 1 : 0
    let travel: CGFloat = visible ? 0 : 6
    if animated, layer.opacity != opacity {
      layer.springAnimate(keyPath: "opacity", to: opacity)
      layer.springAnimate(keyPath: "transform.translation.y", to: travel)
    } else if !animated {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.removeAnimation(forKey: "opacity")
      layer.removeAnimation(forKey: "transform.translation.y")
      layer.opacity = opacity
      layer.setValue(travel, forKeyPath: "transform.translation.y")
      CATransaction.commit()
    }
  }

  /// Vrai quand, replié, le panneau montrerait les ailes de lecture : aucune pastille par-dessus.
  private var showsNowPlayingWingsWhenFolded: Bool {
    isShowingNowPlaying && !isShowingLaunchGreeting && !isShowingDeviceStatus
      && !isShowingAgentEvent && !isShowingMailMessage
  }

  // MARK: - Trajet de la lecture

  /// Fait passer pochette et visualiseur des ailes au lecteur de l'onglet Global (`opening`), ou
  /// l'inverse, au ressort de la silhouette. Ce sont des doublures qui voyagent : les vraies vues
  /// sont cachées aux deux bouts le temps du trajet, si bien qu'aucune pochette n'apparaît en
  /// double. Un trajet interrompu repart de là où ses doublures se trouvent à l'écran.
  private func flyNowPlaying(opening: Bool) {
    nowPlayingWings.layoutSubtreeIfNeeded()
    nowPlayingRow.layoutSubtreeIfNeeded()
    let wingArt = nowPlayingFlight.convert(nowPlayingWings.artworkFrame, from: nowPlayingWings)
    let wingViz = nowPlayingFlight.convert(nowPlayingWings.visualizerFrame, from: nowPlayingWings)
    let rowArt = nowPlayingFlight.convert(nowPlayingRow.artworkFrame, from: nowPlayingRow)
    let rowViz = nowPlayingFlight.convert(nowPlayingRow.visualizerFrame, from: nowPlayingRow)
    guard wingArt.width > 0, rowArt.width > 0 else {
      cancelNowPlayingFlight()
      return
    }

    let inFlight = !nowPlayingFlight.isHidden
    let artStart = inFlight ? presentedFrame(of: flightArtwork) : (opening ? wingArt : rowArt)
    let vizStart = inFlight ? presentedFrame(of: flightVisualizer) : (opening ? wingViz : rowViz)
    let artEnd = opening ? rowArt : wingArt
    let vizEnd = opening ? rowViz : wingViz

    flightGeneration += 1
    let generation = flightGeneration
    nowPlayingWings.setSharedElementsHidden(true)
    nowPlayingRow.setSharedElementsHidden(true)
    nowPlayingFlight.isHidden = false
    if let layer = nowPlayingFlight.layer { PanelFold.fade(layer, to: 1) }

    fly(flightArtwork, from: artStart, to: artEnd) { [weak self] in
      self?.endNowPlayingFlight(generation)
    }
    // Le rayon visible reste celui des deux bouts : le rayon du modèle compense l'échelle.
    let scale = artStart.width / artEnd.width
    if scale > 0 { flightArtwork.animateCornerRadius(from: flightArtwork.cornerRadius / scale) }
    fly(flightVisualizer, from: vizStart, to: vizEnd, completion: nil)
  }

  /// Pose `view` à son cadre d'arrivée et fait partir son calque, par une transformation, du
  /// cadre de départ : l'image est dessinée à sa taille finale et seulement réduite en route.
  private func fly(_ view: NSView, from start: NSRect, to end: NSRect, completion: (() -> Void)?) {
    guard let layer = view.layer, end.width > 0, end.height > 0 else {
      completion?()
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.removeAnimation(forKey: "transform")
    view.frame = end
    layer.transform = CATransform3DIdentity
    CATransaction.commit()
    view.layoutSubtreeIfNeeded()

    // La transformation s'applique autour du point d'ancrage : on fait coïncider celui du
    // cadre d'arrivée avec celui du cadre de départ, à l'échelle de ce dernier.
    let anchor = layer.anchorPoint
    let dx = (start.minX + anchor.x * start.width) - (end.minX + anchor.x * end.width)
    let dy = (start.minY + anchor.y * start.height) - (end.minY + anchor.y * end.height)
    let from = CATransform3DConcat(
      CATransform3DMakeScale(start.width / end.width, start.height / end.height, 1),
      CATransform3DMakeTranslation(dx, dy, 0))
    layer.springAnimate(
      keyPath: "transform",
      to: NSValue(caTransform3D: CATransform3DIdentity),
      from: NSValue(caTransform3D: from),
      preset: .gentle,
      completion: completion)
  }

  /// Cadre affiché d'une doublure, transformation en cours comprise.
  private func presentedFrame(of view: NSView) -> NSRect {
    view.layer?.presentation()?.frame ?? view.frame
  }

  /// Fin du trajet : les vraies vues reprennent la main. Ignorée si un autre trajet a commencé.
  private func endNowPlayingFlight(_ generation: Int) {
    guard generation == flightGeneration, !waitingForShape else { return }
    cancelNowPlayingFlight()
  }

  /// Retire les doublures et rend leurs vues aux ailes et au lecteur.
  private func cancelNowPlayingFlight() {
    flightGeneration += 1
    guard !nowPlayingFlight.isHidden else { return }
    for view in [flightArtwork, flightVisualizer] {
      view.layer?.removeAnimation(forKey: "transform")
      view.layer?.transform = CATransform3DIdentity
    }
    nowPlayingFlight.isHidden = true
    nowPlayingFlight.layer?.removeAnimation(forKey: "opacity")
    nowPlayingFlight.layer?.opacity = 1
    nowPlayingWings.setSharedElementsHidden(false)
    nowPlayingRow.setSharedElementsHidden(false)
  }

  // MARK: - Silhouette

  /// Les deux états, tirés de la même recette que les bandes de flanc
  /// (`PanelGeometry.silhouette`), ici suspendue au bord du **haut** : deux raccords concaves
  /// qui évasent le panneau dans ce bord comme un onglet s'évase dans sa barre, et deux coins
  /// convexes en bas. Seuls la taille et les rayons les distinguent, donc les deux chemins ont
  /// le même nombre de segments dans le même ordre — c'est cette identité de structure qui rend
  /// le dépliage animable d'un seul `CASpringAnimation` sur `path`.

  private func collapsedPath() -> CGPath {
    let growth = NotchPanelGeometry.hoverPeekGrowth
    var size =
      isHoverPeeking
      ? NSSize(
        width: collapsedSize.width + growth.width, height: collapsedSize.height + growth.height)
      : collapsedSize
    if collapsedTopGap > 0 {
      return PanelGeometry.islandSilhouette(in: bounds, size: size, topGap: collapsedTopGap)
    }
    size.height += stayAwakeNotchExtension
    return PanelGeometry.silhouette(
      in: bounds,
      anchoredTo: .top,
      size: size,
      shoulderRadius: NotchPanelGeometry.collapsedShoulderRadius,
      farRadius: NotchPanelGeometry.collapsedBottomRadius
    )
  }

  /// L'encoche élargie par ses deux ailes — même hauteur, mêmes rayons.
  private func wingedPath() -> CGPath {
    // La pastille Bluetooth impose sa largeur et garde la hauteur de l'encoche ; sinon la
    // lecture donne sa taille (`nowPlayingSize`).
    var size =
      isShowingMailMessage
      ? NSSize(
        width: collapsedSize.width + 2 * MailMessagePillView.wingWidth,
        height: collapsedSize.height)
      : isShowingAgentEvent
        ? NSSize(
          width: collapsedSize.width + 2 * AgentEventPillView.wingWidth,
          height: collapsedSize.height)
        : (isShowingDeviceStatus || isShowingLaunchGreeting)
          ? NSSize(
            width: collapsedSize.width + 2 * DeviceStatusPillView.wingWidth,
            height: collapsedSize.height)
          : nowPlayingSize
    if shouldShowPeekTitle { size.height += 23 }
    if collapsedTopGap > 0 {
      return PanelGeometry.islandSilhouette(in: bounds, size: size, topGap: collapsedTopGap)
    }
    size.height += stayAwakeNotchExtension
    return PanelGeometry.silhouette(
      in: bounds,
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
    let motion = animated && OverlayAnimation.allowsMotion
    let wingsShown = showsNowPlayingWingsWhenFolded
    transitionGeneration += 1
    let generation = transitionGeneration
    isExpanded = expanded
    stayAwakeTab.setPanelExpanded(expanded)
    waitingForShape = expanded && motion
    let content = contentContainer.layer
    let visibleOpacity = content?.presentation()?.opacity ?? content?.opacity ?? 0
    waitingForFade = !expanded && motion && visibleOpacity > 0.01
    if expanded || waitingForFade { updateStayAwakeIdleIndicator(animated: motion) }
    verticalStart = nil
    verticalTarget = nil
    verticalSwipe.cancel()
    swipe.cancel()
    resetSwipeOffset(of: contentView(for: selectedTab), animated: false)


    if expanded {
      hideLaunchGreeting(animated: animated)
      hideDeviceStatus(animated: animated)
      hideMailMessage(animated: animated)
      hideAgentEvent(animated: animated)
      nowPlayingRow.refreshVolume()
      onExpanded?()
    }

    layoutNowPlaying()
    let fly = motion && wingsShown && selectedTab == .global
    if !fly { cancelNowPlayingFlight() }
    if fly { flyNowPlaying(opening: expanded) }
    applyCapsuleReveal(animated: motion)

    if expanded && motion {
      GlassReveal.play(on: contentContainer)
    } else if let content {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      if waitingForFade {
        CATransaction.setCompletionBlock { [weak self] in
          MainActor.assumeIsolated {
            guard let self, self.transitionGeneration == generation else { return }
            self.waitingForFade = false
            GlassReveal.cancel(on: self.contentContainer)
            self.applyShape(expanded: false, animated: true)
            self.updateStayAwakeIdleIndicator(animated: true)
            self.updateNowPlayingWingsOpacity(animated: true)
            self.closeTransform(animated: false)
          }
        }
        // Un balayage peut déjà viser zéro alors que le contenu reste visible.
        if content.opacity == 0 { content.opacity = visibleOpacity }
        PanelFold.fade(content, to: 0)
      } else {
        GlassReveal.cancel(on: contentContainer)
        content.removeAnimation(forKey: "opacity")
        content.opacity = expanded ? 1 : 0
      }
      CATransaction.commit()
    }
    if !waitingForFade {
      applyShape(expanded: expanded, animated: motion, force: true)
      updateStayAwakeIdleIndicator(animated: motion)
      updateNowPlayingWingsOpacity(animated: motion)
      if !expanded { closeTransform(animated: false) }
    }
    updateCameraActivity()
    updateTerminal()
  }

  private var foldedPath: CGPath {
    isShowingLaunchGreeting || isShowingDeviceStatus || isShowingAgentEvent
      || isShowingMailMessage || isShowingNowPlaying ? wingedPath() : collapsedPath()
  }

  private func applyShape(expanded: Bool, animated: Bool, force: Bool = false) {
    guard bounds.width > 0, bounds.height > 0, !waitingForFade, verticalStart == nil else { return }
    let path = expanded ? expandedPath() : foldedPath
    guard force || silhouette != path else { return }
    silhouette = path
    shapeGeneration += 1
    let generation = shapeGeneration
    let visiblePath = backgroundLayer.presentation()?.path ?? backgroundLayer.path
    let moves = animated && visiblePath != path
    let velocity = verticalReleaseVelocity
    verticalReleaseVelocity = 0
    PanelFold.apply(
      path: path, to: [backgroundLayer, strokeLayer, contentMask], in: bounds,
      to: expanded ? 1 : 0, animated: moves, velocity: velocity
    ) { [weak self] in
      guard let self, self.shapeGeneration == generation, self.verticalStart == nil else { return }
      self.updateStayAwakeIdleIndicator(animated: animated, shapeSettled: true)
      if let layer = self.peekTitle.layer {
        PanelFold.fade(layer, to: self.shouldShowPeekTitle ? 1 : 0)
      }
      guard self.isExpanded, self.waitingForShape else { return }
      self.waitingForShape = false
      self.revealPlayerAfterFlight()
    }
  }

  private func revealPlayerAfterFlight() {
    guard !nowPlayingFlight.isHidden, let layer = nowPlayingFlight.layer else { return }
    let generation = flightGeneration
    nowPlayingRow.setSharedElementsHidden(false)
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.endNowPlayingFlight(generation) }
    }
    PanelFold.fade(layer, to: 0)
    CATransaction.commit()
  }
}

/// Cadre des doublures de la lecture : il couvre tout le panneau mais ne doit avaler aucun clic.
private final class NowPlayingFlightView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
