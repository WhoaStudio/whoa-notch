import AppKit

/// Bouton des Préférences, en haut à droite du panneau de l'encoche. Un simple glyphe qui
/// s'éclaircit au survol.
final class NotchGearButtonView: NSView {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private var palette = OverlayPalette.resolved(for: .currentDrawing())
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private let symbolName: String
    private let symbolDescription: String

    /// Grisé et sans effet au clic quand il n'y a rien à faire.
    var isEnabled = true {
        didSet { applyTint() }
    }

    /// Teinte imposée, au repos comme au survol — le bouton tasse s'allume ainsi tant que le Mac
    /// est tenu éveillé. `nil` : les teintes de la palette.
    var tintOverride: NSColor? {
        didSet { applyTint() }
    }

    init(symbolName: String = "gearshape", description: String = "Settings") {
        self.symbolName = symbolName
        self.symbolDescription = description
        super.init(frame: .zero)
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: TabBarMetrics.iconSize,
            weight: .medium
        )
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolDescription)?
            .withSymbolConfiguration(configuration)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        applyTint()
    }

    func applyPalette(_ palette: OverlayPalette) {
        self.palette = palette
        applyTint()
    }

    private func applyTint() {
        iconView.contentTintColor = tintOverride
            ?? (isHovered && isEnabled ? palette.tabActiveContent : palette.tabInactiveContent)
        iconView.alphaValue = isEnabled ? 1 : 0.4
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyTint()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyTint()
    }

    override func layout() {
        super.layout()
        let icon = TabBarMetrics.iconSize
        iconView.frame = NSRect(
            x: bounds.midX - icon / 2,
            y: bounds.midY - icon / 2,
            width: icon,
            height: icon
        )
    }

    /// Même raison que pour une bulle : le glyphe est une sous-vue, et c'est lui que le clic
    /// atteindrait.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard isEnabled, bounds.contains(location) else { return }
        ButtonSound.shared.playClick()
        onClick?()
    }
}
