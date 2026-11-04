import AppKit

/// Marque d'un fournisseur, tracée en vecteur dans la couleur demandée.
final class NotchUsageMarkView: NSView {

    private let shape = CAShapeLayer()

    var mark: UsageMarkPath = .claude {
        didSet { needsLayout = true }
    }

    var color: NSColor = .white {
        didSet { shape.fillColor = color.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shape)
        shape.fillColor = color.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.fillRule = mark.usesEvenOddFill ? .evenOdd : .nonZero
        shape.path = mark.path(in: bounds)
        CATransaction.commit()
    }
}

/// Bouton-glyphe sans fond (actualiser, réglages).
final class NotchUsageIconButton: NSView {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(symbolName: String, description: String) {
        super.init(frame: .zero)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyTint() {
        iconView.contentTintColor = NSColor.white.withAlphaComponent(isHovered ? 1 : 0.85)
    }

    override func layout() {
        super.layout()
        iconView.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
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

    // Le panneau ne prend jamais le focus : sans cela, le premier clic serait avalé.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Un onglet de l'en-tête : marque, fenêtre et pourcentage restant (« 5H 42% »).
final class NotchUsageProviderTabView: NSView {

    static let height: CGFloat = 28
    private static let padding: CGFloat = 9
    private static let gap: CGFloat = 6
    private static let markSize: CGFloat = 16

    /// Couleur de la marque dans l'onglet, propre à chaque fournisseur.
    private static func markColor(for provider: NotchUsageProvider) -> NSColor {
        switch provider {
        case .claude: NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        case .codex: NSColor(srgbRed: 0x7B / 255, green: 0x8C / 255, blue: 0xFF / 255, alpha: 1)
        case .copilot: NSColor(white: 0.78, alpha: 1)
        }
    }

    let provider: NotchUsageProvider
    var onSelect: (() -> Void)?

    private let markView = NotchUsageMarkView()
    private let label = NSTextField(labelWithString: "")

    var isSelected = false {
        didSet { applySelection() }
    }

    init(provider: NotchUsageProvider) {
        self.provider = provider
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        markView.mark = provider.mark
        markView.color = Self.markColor(for: provider)
        label.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
        addSubview(markView)
        addSubview(label)
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ reading: NotchUsageReading) {
        let percentage = reading.remainingPercentage.map { "\($0)%" } ?? "--"
        label.stringValue = "\(reading.windowLabel) \(percentage)"
        label.sizeToFit()
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    private func applySelection() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.12 : 0).cgColor
        label.textColor = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.8)
    }

    var fittingWidth: CGFloat {
        Self.padding + Self.markSize + Self.gap + ceil(label.intrinsicContentSize.width) + Self.padding
    }

    override func layout() {
        super.layout()
        markView.frame = NSRect(
            x: Self.padding, y: (bounds.height - Self.markSize) / 2,
            width: Self.markSize, height: Self.markSize)
        let size = label.intrinsicContentSize
        label.frame = NSRect(
            x: markView.frame.maxX + Self.gap, y: (bounds.height - size.height) / 2,
            width: ceil(size.width), height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

/// En-tête de l'onglet AI : le titre à gauche ; au centre l'actualisation puis les onglets des
/// fournisseurs ; les réglages tout à droite.
final class NotchUsageHeaderView: NSView {

    static let height: CGFloat = 30

    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onSelect: ((NotchUsageProvider) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Usage")
    private let refreshButton = NotchUsageIconButton(symbolName: "arrow.clockwise", description: "Refresh")
    private let settingsButton = NotchUsageIconButton(symbolName: "gearshape", description: "Settings")
    private let tabs: [NotchUsageProviderTabView]

    private let buttonSize: CGFloat = 24
    private let groupGap: CGFloat = 6

    override init(frame frameRect: NSRect) {
        tabs = NotchUsageProvider.allCases.map { NotchUsageProviderTabView(provider: $0) }
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.textColor = .white
        addSubview(titleLabel)
        addSubview(refreshButton)
        addSubview(settingsButton)
        refreshButton.onClick = { [weak self] in self?.onRefresh?() }
        settingsButton.onClick = { [weak self] in self?.onOpenSettings?() }
        for tab in tabs {
            tab.onSelect = { [weak self] in self?.onSelect?(tab.provider) }
            addSubview(tab)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ reading: NotchUsageReading, for provider: NotchUsageProvider) {
        tabs[provider.rawValue].apply(reading)
        needsLayout = true
    }

    func select(_ provider: NotchUsageProvider) {
        for tab in tabs { tab.isSelected = tab.provider == provider }
    }

    override func layout() {
        super.layout()

        let title = titleLabel.intrinsicContentSize
        titleLabel.frame = NSRect(
            x: 0, y: (bounds.height - title.height) / 2, width: ceil(title.width), height: title.height)

        // Le glyphe, et non sa zone cliquable, tombe sur le bord droit du contenu : il s'aligne ainsi
        // sur l'engrenage du panneau (voir `NotchPanelGeometry.gearInsetX`).
        let overhang = (buttonSize - TabBarMetrics.iconSize) / 2
        settingsButton.frame = NSRect(
            x: bounds.maxX - buttonSize + overhang, y: (bounds.height - buttonSize) / 2,
            width: buttonSize, height: buttonSize)

        // Actualiser + onglets forment un groupe centré dans l'espace laissé entre le titre et les
        // réglages.
        let tabWidths = tabs.map(\.fittingWidth)
        let groupWidth = buttonSize + groupGap + tabWidths.reduce(0, +) + CGFloat(tabs.count - 1) * 2
        let free = NSRect(
            x: titleLabel.frame.maxX, y: 0,
            width: settingsButton.frame.minX - titleLabel.frame.maxX, height: bounds.height)
        var x = max(free.minX, free.midX - groupWidth / 2)

        refreshButton.frame = NSRect(
            x: x, y: (bounds.height - buttonSize) / 2, width: buttonSize, height: buttonSize)
        x = refreshButton.frame.maxX + groupGap

        for (tab, width) in zip(tabs, tabWidths) {
            tab.frame = NSRect(
                x: x, y: (bounds.height - NotchUsageProviderTabView.height) / 2,
                width: width, height: NotchUsageProviderTabView.height)
            x = tab.frame.maxX + 2
        }
    }
}
