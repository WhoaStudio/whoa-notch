import AppKit

/// Fenêtre unique du dock : un `NSPanel` sans bordure créé une seule fois. Les mises à jour ne
/// font que changer son cadre et son contenu. Elle est plus grande que la capsule (réserve de
/// l'agrandissement) ; son fond est transparent, donc les clics y traversent.
@MainActor
final class DockPanel {

    private let panel: NSPanel
    let content = DockContentView()
    private var presented = false
    private(set) var isRevealed = true

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 96),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Sans cela, aucun mouvement de souris n'est livré à l'app au-dessus de sa propre fenêtre — et les
        // moniteurs globaux ne voient pas les fenêtres de l'app : le survol resterait muet sur le dock.
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = content
    }

    func apply(items: [DockItem], overflow: [DockItem]) {
        content.apply(items: items, overflow: overflow)
        relayout(animated: true)
    }

    func apply(widgets: [DockWidgetPlacement]) {
        content.apply(widgets: widgets)
        relayout(animated: true)
    }

    func apply(theme: DockTheme) {
        content.apply(theme: theme)
    }

    func apply(appearance: DockAppearance) {
        content.apply(appearance: appearance)
        relayout(animated: false)
    }

    func apply(workspaces: [DockWorkspace], activeID: String?) {
        content.apply(workspaces: workspaces, activeID: activeID)
        relayout(animated: true)
    }

    /// Redimensionne la fenêtre à ce que demande le contenu, puis laisse les vues glisser de leur
    /// ancienne place à l'écran vers la nouvelle.
    private func relayout(animated: Bool) {
        let before = panel.frame.minX
        reposition()
        content.relayout(shiftingBy: before - panel.frame.minX, animated: animated)
    }

    /// L'écran où le dock s'affiche : celui du curseur. On retient son identifiant matériel, pas l'objet —
    /// il survit à un branchement ou débranchement d'écran ; s'il a disparu, retour à l'écran du curseur.
    private var targetDisplayID: CGDirectDisplayID?

    var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == targetDisplayID } ?? NSScreen.underCursor ?? NSScreen.screens.first
    }

    var displayID: CGDirectDisplayID? { targetDisplayID }

    /// Passe sur un autre écran. `reveal` dit s'il y arrive déployé (glissant depuis le bord) ou replié.
    func moveTo(_ screen: NSScreen, reveal: Bool) {
        targetDisplayID = screen.displayID
        content.setHover(nil)
        isRevealed = reveal
        guard presented else { return }
        if reveal {
            slideIn()
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 0
            panel.setFrame(hiddenFrame, display: false)
        }
    }

    /// Cadre de la fenêtre déployée : centré en bas de l'écran cible.
    var shownFrame: NSRect {
        guard let screen = targetScreen else { return panel.frame }
        let width = min(content.panelWidth(forIconCount: content.rowCount), screen.frame.width - 16)
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.minY + 8, width: width, height: content.panelHeight)
    }

    /// Zone que le curseur doit toucher : la capsule, en coordonnées d'écran.
    var capsuleScreenRect: NSRect {
        let shown = shownFrame
        let capsule = content.capsuleRect
        return NSRect(x: shown.minX + capsule.minX, y: shown.minY, width: capsule.width, height: capsule.height)
    }

    private var hiddenFrame: NSRect {
        var frame = shownFrame
        frame.origin.y = (targetScreen?.frame.minY ?? 0) - frame.height - 20
        return frame
    }

    func reposition() {
        guard presented else { return }
        let frame = isRevealed ? shownFrame : hiddenFrame
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Montre ou retire le dock (réglage « Show dock »). Il entre en glissant depuis le bord, en fondu.
    func setPresented(_ presented: Bool) {
        let wasPresented = self.presented
        self.presented = presented
        if presented {
            guard !wasPresented else { return }
            if isRevealed { slideIn() } else { panel.setFrame(hiddenFrame, display: true) }
        } else {
            panel.orderOut(nil)
        }
    }

    private func slideIn() {
        panel.alphaValue = 0
        panel.setFrame(hiddenFrame, display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(shownFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Glisse le dock dans ou hors du bord (masquage auto).
    func setRevealed(_ revealed: Bool, animated: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        guard presented else { return }
        if !revealed { content.setHover(nil) }
        guard animated else {
            panel.alphaValue = revealed ? 1 : 0
            panel.setFrame(revealed ? shownFrame : hiddenFrame, display: true)
            if revealed { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
            return
        }
        if revealed { slideIn(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isRevealed else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

/// Cible d'un item de menu : `NSMenuItem` ne retient pas sa cible, l'item garde donc l'action en `representedObject`.
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

@MainActor
private func menuItem(_ title: String, enabled: Bool = true, handler: @escaping () -> Void = {}) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    item.isEnabled = enabled
    return item
}

/// Possède le panneau du dock et le relie au modèle, à l'activation des fenêtres, au masquage
/// automatique et au menu contextuel. Les réglages d'aspect viennent du Dock macOS.
@MainActor
final class DockController {

    private let panel = DockPanel()
    private let activator: WindowActivator
    private let readAppearance: () -> DockAppearance
    private let onTogglePin: (DockItem) -> Void
    private let onSelectWorkspace: (String?) -> Void
    private let onPlaceApp: (DockPinnedApp, Int) -> Void
    private let onRemoveApp: (DockItem) -> Void
    private let onWidgetsChanged: ([DockWidgetPlacement]) -> Void
    private var appearance = DockAppearance()
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var pendingToggle: Task<Void, Never>?
    private var launching: Set<String> = []
    private var wasInside = false
    private var autoHide = true
    private var hotActive = false
    private var hideTask: Task<Void, Never>?

    init(
        activator: WindowActivator = WindowActivator(),
        readAppearance: @escaping () -> DockAppearance,
        onTogglePin: @escaping (DockItem) -> Void,
        onSelectWorkspace: @escaping (String?) -> Void,
        onPlaceApp: @escaping (DockPinnedApp, Int) -> Void,
        onRemoveApp: @escaping (DockItem) -> Void,
        onWidgetsChanged: @escaping ([DockWidgetPlacement]) -> Void = { _ in }
    ) {
        self.activator = activator
        self.readAppearance = readAppearance
        self.onTogglePin = onTogglePin
        self.onSelectWorkspace = onSelectWorkspace
        self.onPlaceApp = onPlaceApp
        self.onRemoveApp = onRemoveApp
        self.onWidgetsChanged = onWidgetsChanged
        panel.content.onWidgetsChanged = { [weak self] in self?.onWidgetsChanged($0) }
        panel.content.onActivate = { [weak self] in self?.activate($0) }
        panel.content.onSelectWorkspace = { [weak self] in self?.onSelectWorkspace($0) }
        panel.content.onPlaceApp = { [weak self] app, index in self?.onPlaceApp(app, index) }
        panel.content.onRemoveApp = { [weak self] item, point in
            // L'icône part en fumée sous le curseur, comme dans le vrai Dock.
            NSAnimationEffect.disappearingItemDefault.show(centeredAt: point, size: .zero)
            self?.onRemoveApp(item)
        }
        panel.content.onContextMenu = { [weak self] item, view, event in self?.showMenu(for: item, from: view, event: event) }
    }

    func activate() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.reposition() }
        }
        // Local pour les mouvements au-dessus du dock, global pour tout le reste de l'écran.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(global) }
        refreshAppearance()
        syncWithSystemDock()
    }

    func apply(state: DockState) {
        launching.subtract(state.items.filter(\.isRunning).map(\.id))
        panel.content.setBouncing(launching)
        panel.apply(items: state.items, overflow: state.overflow)
    }

    func apply(workspaces: [DockWorkspace], activeID: String?) {
        panel.apply(workspaces: workspaces, activeID: activeID)
    }

    func apply(widgets: [DockWidgetPlacement]) {
        panel.apply(widgets: widgets)
    }

    func apply(theme: DockTheme) {
        panel.apply(theme: theme)
    }

    func apply(enabled: Bool) {
        panel.setPresented(enabled)
    }

    /// Relit les réglages du Dock macOS ; appelé quand ils ont pu changer.
    func refreshAppearance() {
        let next = readAppearance()
        guard next != appearance else { return }
        appearance = next
        panel.apply(appearance: next)
    }

    // MARK: - Cohabitation avec le Dock macOS

    /// Le dock personnalisé n'est affiché que si le Dock macOS ne l'est pas.
    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        let inside = panel.capsuleScreenRect.insetBy(dx: -8, dy: -8).contains(location)
        if inside && !wasInside { refreshAppearance() }
        wasInside = inside
        followCursorScreen(at: location)
        updateHover(at: location)
        updateHotZone(at: location)
        // Le Dock macOS ne surgit qu'au contact du bord du bas : inutile de l'interroger ailleurs.
        if let screen = NSScreen.underCursor, location.y <= screen.frame.minY + 160 { syncWithSystemDock() }
    }

    /// Zone sensible du bord du bas, au milieu de l'écran, comme celles des bandes latérales : le dock
    /// n'y vient qu'au contact du bord.
    static func hotZone(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - 120, y: screen.frame.minY, width: 240, height: 12)
    }

    /// La zone où le curseur est « sur le dock » : la capsule et la réserve au-dessus d'elle, là où
    /// les icônes agrandies se dressent.
    private var dockZone: NSRect {
        let capsule = panel.capsuleScreenRect
        let zone = NSRect(
            x: capsule.minX - 10, y: capsule.minY - 8, width: capsule.width + 20,
            height: capsule.height + 8 + (appearance.magnification ? appearance.magnifiedSize - appearance.iconSize : 0))
        // Le panneau du dossier ouvert fait partie du dock : y rester ne le referme ni ne cache le dock.
        guard let popover = panel.content.expandedPopoverRect else { return zone }
        let shown = panel.shownFrame
        return zone.union(popover.offsetBy(dx: shown.minX, dy: shown.minY).insetBy(dx: -8, dy: -8))
    }

    func apply(autoHide: Bool) {
        self.autoHide = autoHide
        hotActive = false
        syncWithSystemDock()
    }

    /// Le dock suit le curseur d'un écran à l'autre. Tant que le curseur est encore sur le dock, il ne
    /// bouge pas (un glisser-déposer peut le frôler du bord d'un autre écran).
    private func followCursorScreen(at location: NSPoint) {
        guard let screen = NSScreen.underCursor, screen.displayID != panel.displayID,
              !(panel.isRevealed && dockZone.contains(location))
        else { return }
        hideTask?.cancel()
        hideTask = nil
        hotActive = false
        // Avec le masquage auto, il arrive replié et attend la zone sensible de ce nouvel écran.
        panel.moveTo(screen, reveal: !autoHide)
        syncWithSystemDock()
    }

    /// Le dock reste tant que le curseur est dans la zone sensible ou sur lui, puis se retire un
    /// instant après.
    private func updateHotZone(at location: NSPoint) {
        guard let screen = NSScreen.underCursor else { return }
        let over = Self.hotZone(on: screen).contains(location) || (panel.isRevealed && dockZone.contains(location))
        if over {
            hideTask?.cancel()
            hideTask = nil
            if !hotActive {
                hotActive = true
                syncWithSystemDock()
            }
        } else if hotActive, hideTask == nil {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                self.hideTask = nil
                self.hotActive = false
                self.syncWithSystemDock()
            }
        }
    }

    /// Agrandissement : le curseur est « sur le dock » dans la capsule et dans la réserve au-dessus
    /// d'elle, là où les icônes agrandies se dressent.
    private func updateHover(at location: NSPoint) {
        guard panel.isRevealed else {
            panel.content.setHover(nil)
            return
        }
        let shown = panel.shownFrame
        panel.content.setHover(dockZone.contains(location) ? NSPoint(x: location.x - shown.minX, y: location.y - shown.minY) : nil)
    }

    private func syncWithSystemDock() {
        // Sans Accessibilité on ne peut pas savoir : le dock personnalisé reste affiché.
        let systemVisible = panel.targetScreen.flatMap { SystemDockVisibility.isVisible(on: $0) } ?? false
        panel.setRevealed(!systemVisible && (!autoHide || hotActive), animated: true)
        if systemVisible {
            watchSystemDock()
        } else {
            pendingToggle?.cancel()
            pendingToggle = nil
        }
    }

    /// Tant que le Dock macOS est visible, regarde quand il se retire pour rendre la place.
    private func watchSystemDock() {
        guard pendingToggle == nil else { return }
        pendingToggle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.pendingToggle = nil
            self.syncWithSystemDock()
        }
    }

    // MARK: - Actions

    private func activate(_ item: DockItem) {
        if !item.isRunning && appearance.bounceOnLaunch {
            launching.insert(item.id)
            panel.content.setBouncing(launching)
            // Filet de sécurité : un lancement qui échoue ne doit pas faire rebondir l'icône à l'infini.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                self.launching.remove(item.id)
                self.panel.content.setBouncing(self.launching)
            }
        }
        activator.activate(item)
    }

    private func showMenu(for item: DockItem, from view: NSView, event: NSEvent) {
        let menu = NSMenu(title: item.name)
        menu.addItem(menuItem(item.name, enabled: false))

        let windows = activator.windows(for: item).filter { !$0.title.isEmpty }
        if !windows.isEmpty {
            menu.addItem(.separator())
            for window in windows {
                let title = window.isMinimized ? "\(window.title) (minimised)" : window.title
                menu.addItem(menuItem(title) { [activator] in activator.raise(window, of: item) })
            }
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(item.isPinned ? "Remove from Dock" : "Keep in Dock") { [onTogglePin] in onTogglePin(item) })
        menu.addItem(menuItem("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        })

        menu.addItem(.separator())
        if item.isRunning {
            menu.addItem(menuItem("Hide") { [activator] in activator.hide(item) })
            menu.addItem(menuItem("Quit") { [activator] in activator.quit(item) })
        } else {
            menu.addItem(menuItem("Open") { [weak self] in self?.activate(item) })
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
