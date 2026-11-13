import AppKit
import os

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

  private let panel: NotchKeyPanel
  private let contentView = NotchPanelContentView()

  init() {
    panel = NotchKeyPanel(
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
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    panel.contentView = contentView
    contentView.onKeyboardNeedChanged = { [weak self] in self?.updateKeyboard() }
  }

  /// Le shell partagé de l'onglet Terminal.
  var terminalSession: TerminalSession? {
    get { contentView.terminalSession }
    set { contentView.terminalSession = newValue }
  }

  /// Vrai tant que le clavier est dans le terminal ou l'éditeur de notes : le panneau ne doit pas
  /// se replier sous la main qui tape quand le curseur s'écarte.
  var holdsKeyboardFocus: Bool {
    (contentView.wantsKeyboard || contentView.cardAcceptsKeyboard) && panel.isKeyWindow
  }

  /// Le panneau ne prend le clavier que sur les onglets Terminal et Notes dépliés. `.nonactivatingPanel` :
  /// l'app de devant reste active, seules les touches viennent ici.
  private func updateKeyboard() {
    let wants = contentView.wantsKeyboard
    // Un champ de la carte d'agent peut prendre le clavier, mais seulement quand on clique dedans :
    // une demande qui s'ouvre toute seule ne doit pas détourner la frappe en cours ailleurs.
    let cardTyping = contentView.cardAcceptsKeyboard
    panel.acceptsKeyboard = wants || cardTyping
    if wants {
      panel.makeKey()
      contentView.focusKeyboardTarget()
    } else if panel.isKeyWindow && !cardTyping {
      panel.resignKey()
    }
  }

  var frame: NSRect { panel.frame }
  var isExpanded: Bool { contentView.isExpanded }

  /// Relayé jusqu'au contrôleur, qui ouvre les Préférences — ni la fenêtre ni la vue de contenu
  /// n'ont à connaître `SettingsWindowController`.
  var onFoldRequested: (() -> Void)? {
    get { contentView.onFoldRequested }
    set { contentView.onFoldRequested = newValue }
  }

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

  func apply(notes: [Note]) {
    contentView.apply(notes: notes)
  }

  var onCreateNote: (() -> Void)? {
    get { contentView.onCreateNote }
    set { contentView.onCreateNote = newValue }
  }

  var onEditNote: ((UUID, String) -> Void)? {
    get { contentView.onEditNote }
    set { contentView.onEditNote = newValue }
  }

  var onDeleteNote: ((UUID) -> Void)? {
    get { contentView.onDeleteNote }
    set { contentView.onDeleteNote = newValue }
  }

  func apply(colorPickerState: ColorPickerState) {
    contentView.apply(colorPickerState: colorPickerState)
  }

  var onColorPickerAction: ((ColorPickerAction) -> Void)? {
    get { contentView.onColorPickerAction }
    set { contentView.onColorPickerAction = newValue }
  }

  func apply(stayAwakeState: StayAwakeState) {
    contentView.apply(stayAwakeState: stayAwakeState)
  }

  var onStayAwakeAction: ((StayAwakeAction) -> Void)? {
    get { contentView.onStayAwakeAction }
    set { contentView.onStayAwakeAction = newValue }
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

  var onDeleteClipboardItem: ((ClipboardItem) -> Void)? {
    get { contentView.onDeleteClipboardItem }
    set { contentView.onDeleteClipboardItem = newValue }
  }

  var onTogglePinClipboardItem: ((ClipboardItem) -> Void)? {
    get { contentView.onTogglePinClipboardItem }
    set { contentView.onTogglePinClipboardItem = newValue }
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

  var onLoadActivity: ((Int) -> Void)? {
    get { contentView.onLoadActivity }
    set { contentView.onLoadActivity = newValue }
  }

  func apply(activityRecords: [ActivityRecord], isLoading: Bool) {
    contentView.apply(activityRecords: activityRecords, isLoading: isLoading)
  }

  func apply(codexUsageState: CodexUsageState) {
    contentView.apply(codexUsageState: codexUsageState)
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

  func showLaunchGreeting() {
    contentView.showLaunchGreeting()
  }

  func hideLaunchGreeting() {
    contentView.hideLaunchGreeting()
  }

  func showDeviceStatus(_ status: DeviceStatus) {
    contentView.showDeviceStatus(status)
  }

  func hideDeviceStatus() {
    contentView.hideDeviceStatus()
  }

  func showAgentEvent(_ event: AgentEvent, queued: Int = 0, deadline: Date? = nil) {
    contentView.showAgentEvent(event, queued: queued, deadline: deadline)
  }

  func hideAgentEvent() {
    contentView.hideAgentEvent()
  }

  var onAgentDecision: ((AgentEvent, AgentEvent.Decision) -> Void)? {
    get { contentView.onAgentDecision }
    set { contentView.onAgentDecision = newValue }
  }

  /// La demande que la carte de l'onglet AI affiche ; `nil` la retire.
  func apply(agentPrompt: AgentEvent?, queued: Int = 0) {
    contentView.apply(agentPrompt: agentPrompt, queued: queued)
  }

  /// Ce que fait l'agent ; `nil` retire la carte d'activité.
  func apply(agentActivity: AgentActivity?) {
    contentView.apply(agentActivity: agentActivity)
  }

  func apply(agentSessions: [AgentSession], selectedID: String?) {
    contentView.apply(agentSessions: agentSessions, selectedID: selectedID)
  }

  var onAgentSteer: ((String, String) -> Void)? {
    get { contentView.onAgentSteer }
    set { contentView.onAgentSteer = newValue }
  }

  var onAgentSessionSelected: ((String) -> Void)? {
    get { contentView.onAgentSessionSelected }
    set { contentView.onAgentSessionSelected = newValue }
  }

  var onAgentPromote: ((AgentEvent) -> Void)? {
    get { contentView.onAgentPromote }
    set { contentView.onAgentPromote = newValue }
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

  var onNowPlayingSeek: ((TimeInterval) -> Void)? {
    get { contentView.onNowPlayingSeek }
    set { contentView.onNowPlayingSeek = newValue }
  }

  var dayAgendaLoader: ((Date) async -> CalendarAgendaState)? {
    get { contentView.dayAgendaLoader }
    set { contentView.dayAgendaLoader = newValue }
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
    let hardwareNotch = NotchPanelGeometry.notchRect(on: screen)
    contentView.hasHardwareNotch = hardwareNotch != nil
    if let notch = hardwareNotch {
      Log.notchPanel.debug(
        "Encoche matérielle \(notch.width, privacy: .public) × \(notch.height, privacy: .public) pt, déplié \(frame.width, privacy: .public) pt"
      )
    } else {
      Log.notchPanel.debug(
        "Écran sans encoche, pastille, déplié \(frame.width, privacy: .public) pt")
    }
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

  /// Survol de la zone sensible en mode « clic » : la silhouette repliée grossit un peu.
  func setHoverPeek(_ peeking: Bool) {
    contentView.setHoverPeek(peeking)
  }

  func prepareForPointerOpen() {
    if FileShelfStore.shared.isEmpty { contentView.resetSelectionWhenFolded() }
  }

  func acceptsVerticalSwipe(at location: NSPoint) -> Bool {
    contentView.acceptsVerticalSwipe(at: NSPoint(
      x: location.x - panel.frame.minX, y: location.y - panel.frame.minY))
  }

  var isTrackingVerticalSwipe: Bool { contentView.isTrackingVerticalSwipe }

  func trackVerticalSwipe(_ event: NSEvent) -> Bool? { contentView.trackVerticalSwipe(event) }
  func cancelVerticalSwipe() { contentView.cancelVerticalSwipe() }

  func setExpanded(_ expanded: Bool, animated: Bool = true) {
    guard isExpanded != expanded else { return }
    if expanded {
      contentView.refreshWeek()
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

/// Panneau borderless qui ne peut devenir fenêtre clé que quand l'onglet Terminal le demande :
/// partout ailleurs il ne vole jamais le clavier à l'app de devant.
private final class NotchKeyPanel: NSPanel {
  var acceptsKeyboard = false
  override var canBecomeKey: Bool { acceptsKeyboard }
}
