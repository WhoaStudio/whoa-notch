import AppKit

/// Un espace de travail dans la pastille : son logo et son nom. Actif, il se pose sur un fond gris
/// clair avec un texte noir ; sinon il reste gris, sans fond.
private final class DockPillSegmentView: DockButtonView {

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private(set) var workspaceID = ""

    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let iconSide: CGFloat = 15
    private static let iconGap: CGFloat = 6
    static let horizontalPadding: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = Self.font
        addSubview(icon)
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(_ workspace: DockWorkspace, isActive: Bool) {
        workspaceID = workspace.id
        let ink = isActive ? NSColor.black : NSColor(white: 0.62, alpha: 1)
        layer?.backgroundColor = isActive ? NSColor(white: 0.85, alpha: 1).cgColor : NSColor.clear.cgColor
        icon.image = NSImage(systemSymbolName: workspace.symbol, accessibilityDescription: workspace.name)?
            .withSymbolConfiguration(.init(pointSize: Self.iconSide, weight: .semibold))
        icon.contentTintColor = ink
        label.stringValue = workspace.name
        label.textColor = ink
        label.sizeToFit()
        toolTip = workspace.name
    }

    var preferredWidth: CGFloat {
        Self.horizontalPadding * 2 + Self.iconSide + Self.iconGap + ceil(label.frame.width)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        icon.frame = NSRect(x: Self.horizontalPadding, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide, height: Self.iconSide)
        label.frame.origin = NSPoint(
            x: Self.horizontalPadding + Self.iconSide + Self.iconGap, y: (bounds.height - label.frame.height) / 2)
    }
}

/// La pastille des espaces de travail : un gris foncé uni, un fin liseré, les espaces côte à côte.
/// Volontairement sans verre, quel que soit le thème du dock.
final class DockWorkspacePillView: NSView {

    var onSelect: ((String) -> Void)?

    private var segments: [String: DockPillSegmentView] = [:]
    private var workspaces: [DockWorkspace] = []

    private static let inset: CGFloat = 4
    private static let segmentHeight: CGFloat = 32
    private static let segmentGap: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Taille voulue par le contenu ; nulle sans espace de travail.
    var contentSize: NSSize {
        guard !workspaces.isEmpty else { return .zero }
        let widths = workspaces.compactMap { segments[$0.id]?.preferredWidth }
        let gaps = CGFloat(max(0, widths.count - 1)) * Self.segmentGap
        return NSSize(width: widths.reduce(0, +) + gaps + Self.inset * 2, height: Self.segmentHeight + Self.inset * 2)
    }

    func apply(workspaces newWorkspaces: [DockWorkspace], activeID: String?) {
        let ids = Set(newWorkspaces.map(\.id))
        for (id, segment) in segments where !ids.contains(id) {
            segment.removeFromSuperview()
            segments[id] = nil
        }
        for workspace in newWorkspaces where segments[workspace.id] == nil {
            let segment = DockPillSegmentView()
            segment.onClick = { [weak self, id = workspace.id] in self?.onSelect?(id) }
            addSubview(segment)
            segments[workspace.id] = segment
        }
        workspaces = newWorkspaces
        for workspace in newWorkspaces {
            segments[workspace.id]?.apply(workspace, isActive: workspace.id == activeID)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        var x = Self.inset
        for workspace in workspaces {
            guard let segment = segments[workspace.id] else { continue }
            let width = segment.preferredWidth
            segment.frame = NSRect(x: x, y: Self.inset, width: width, height: Self.segmentHeight)
            x += width + Self.segmentGap
        }
    }
}

/// La fenêtre de la pastille, au-dessus du dock. Elle n'apparaît qu'au survol du dock (ou d'ellemême) ;
/// son fond est transparent, hors de la pastille les clics la traversent.
@MainActor
final class DockWorkspacePillPanel {

    let pill = DockWorkspacePillView()
    private let panel: NSPanel
    private(set) var isShown = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Comme le dock : sans cela, le survol de la pastille ne serait pas livré à l'app.
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = pill
        panel.alphaValue = 0
    }

    /// Montre la pastille dans `frame` (en coordonnées d'écran) ou la retire.
    func setShown(_ shown: Bool, frame: NSRect) {
        if shown {
            panel.setFrame(frame, display: true)
            guard !isShown else { return }
            isShown = true
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else if isShown {
            isShown = false
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isShown else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }
}
