import AppKit

/// Teinte de l'onglet Stay Awake, partagée avec le bouton de l'en-tête qui l'ouvre : le jaune du
/// café, le même que l'on soit actif ou non, pour que le bouton se reconnaisse d'un coup d'œil.
enum StayAwakeStyle {
    static let accent = NSColor(srgbRed: 1, green: 0.73, blue: 0.24, alpha: 1)
}

/// L'onglet Stay Awake : à gauche l'état (tasse, titre, temps restant, « Turn Off »), à droite
/// les réglages — la durée, puis ce qui reste éveillé.
///
/// Choisir une durée démarre (ou relance) tout de suite : il n'y a pas de bouton « Start »
/// séparé. Le choix de ce qui reste éveillé, lui, s'applique à chaud.
final class StayAwakeTabView: NSView {

    var onAction: ((StayAwakeAction) -> Void)?

    private var state = StayAwakeState()
    private var palette = OverlayPalette.resolved(for: .currentDrawing())

    private let iconCircle = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let scopeLabel = NSTextField(labelWithString: "")
    private let turnOffButton = StayAwakeButtonView(title: "Turn Off", symbolName: "stop.fill", cornerRadius: nil)
    private let divider = NSView()
    private let durationLabel = NSTextField(labelWithString: "For")
    private let scopeHeader = NSTextField(labelWithString: "Stays awake")
    private let chips: [(duration: StayAwakeDuration, view: StayAwakeButtonView)]
    private let scopeButtons: [(scope: StayAwakeScope, view: StayAwakeButtonView)]

    private static let circleSize: CGFloat = 40
    private static let chipHeight: CGFloat = 28
    private static let scopeHeight: CGFloat = 30
    private static let gap: CGFloat = 6

    override init(frame: NSRect) {
        chips = StayAwakeDuration.allCases.map { ($0, StayAwakeButtonView(title: $0.label)) }
        scopeButtons = StayAwakeScope.allCases.map {
            ($0, StayAwakeButtonView(title: $0.title, symbolName: $0.symbolName))
        }
        super.init(frame: frame)
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        iconCircle.wantsLayer = true
        addSubview(iconCircle)
        let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Stay awake")?
            .withSymbolConfiguration(configuration)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconCircle.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        scopeLabel.font = .systemFont(ofSize: 11, weight: .regular)
        for label in [durationLabel, scopeHeader] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
        }
        for label in [titleLabel, statusLabel, scopeLabel, durationLabel, scopeHeader] {
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }

        turnOffButton.onClick = { [weak self] in self?.onAction?(.turnOff) }
        addSubview(turnOffButton)

        divider.wantsLayer = true
        addSubview(divider)

        for (duration, view) in chips {
            view.onClick = { [weak self] in self?.onAction?(.start(duration)) }
            addSubview(view)
        }
        for (scope, view) in scopeButtons {
            view.onClick = { [weak self] in self?.onAction?(.setScope(scope)) }
            addSubview(view)
        }

        applyPalette(palette)
        apply(state)
    }

    func applyPalette(_ palette: OverlayPalette) {
        self.palette = palette
        divider.layer?.backgroundColor = palette.strokeColor
        chips.forEach { $0.view.applyPalette(palette) }
        scopeButtons.forEach { $0.view.applyPalette(palette) }
        turnOffButton.applyPalette(palette)
        applyColors()
    }

    func apply(_ newState: StayAwakeState) {
        state = newState
        titleLabel.stringValue = newState.isActive ? "Staying awake" : "Stay awake"
        statusLabel.stringValue = newState.statusText
        scopeLabel.stringValue = newState.scope.title
        scopeLabel.isHidden = !newState.isActive
        turnOffButton.isHidden = !newState.isActive
        for (duration, view) in chips { view.isSelected = newState.duration == duration }
        for (scope, view) in scopeButtons { view.isSelected = newState.scope == scope }
        applyColors()
        needsLayout = true
    }

    private func applyColors() {
        let accent = StayAwakeStyle.accent
        iconCircle.layer?.backgroundColor = state.isActive
            ? accent.withAlphaComponent(0.22).cgColor
            : palette.tabCapsuleFill
        iconView.contentTintColor = state.isActive ? accent : palette.tabInactiveContent
        titleLabel.textColor = palette.tabActiveContent
        statusLabel.textColor = state.isActive ? accent : palette.tabInactiveContent
        scopeLabel.textColor = palette.tabInactiveContent
        durationLabel.textColor = palette.tabInactiveContent
        scopeHeader.textColor = palette.tabInactiveContent
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
    }

    override func layout() {
        super.layout()

        let leftWidth = min(150, bounds.width * 0.36)
        layoutLeft(width: leftWidth)

        let dividerX = leftWidth + 12
        divider.frame = NSRect(x: dividerX, y: bounds.minY + 14, width: 1, height: max(0, bounds.height - 28))

        layoutRight(originX: dividerX + 13)
    }

    /// Pile de lignes de l'état, centrée sur la hauteur ; la tasse se centre sur la pile.
    private func layoutLeft(width: CGFloat) {
        let circle = Self.circleSize
        iconCircle.frame = NSRect(x: 0, y: bounds.midY - circle / 2, width: circle, height: circle)
        iconCircle.layer?.cornerRadius = circle / 2
        let glyph: CGFloat = 20
        iconView.frame = NSRect(x: (circle - glyph) / 2, y: (circle - glyph) / 2, width: glyph, height: glyph)

        let textX = circle + 10
        let textWidth = max(0, width - textX)
        let lineHeights: [CGFloat] = state.isActive ? [17, 16, 14] : [17, 16]
        let buttonHeight: CGFloat = state.isActive ? 24 : 0
        let buttonGap: CGFloat = state.isActive ? 8 : 0
        let total = lineHeights.reduce(0, +) + buttonGap + buttonHeight
        var y = bounds.midY + total / 2

        var labels: [NSTextField] = [titleLabel, statusLabel]
        if state.isActive { labels.append(scopeLabel) }
        for (label, height) in zip(labels, lineHeights) {
            y -= height
            label.frame = NSRect(x: textX, y: y, width: textWidth, height: height)
        }
        if state.isActive {
            y -= buttonGap + buttonHeight
            let buttonWidth = min(textWidth, 78)
            turnOffButton.frame = NSRect(x: textX, y: y, width: buttonWidth, height: buttonHeight)
        }
    }

    private func layoutRight(originX: CGFloat) {
        let width = max(0, bounds.maxX - originX)
        let gap = Self.gap
        let labelHeight: CGFloat = 14
        let total = labelHeight + gap + Self.chipHeight + 14 + labelHeight + gap + Self.scopeHeight
        var y = bounds.midY + total / 2

        y -= labelHeight
        durationLabel.frame = NSRect(x: originX, y: y, width: width, height: labelHeight)

        y -= gap + Self.chipHeight
        let chipWidth = (width - gap * CGFloat(chips.count - 1)) / CGFloat(chips.count)
        for (index, item) in chips.enumerated() {
            item.view.frame = NSRect(
                x: originX + CGFloat(index) * (chipWidth + gap),
                y: y,
                width: chipWidth,
                height: Self.chipHeight
            )
        }

        y -= 14 + labelHeight
        scopeHeader.frame = NSRect(x: originX, y: y, width: width, height: labelHeight)

        y -= gap + Self.scopeHeight
        let scopeWidth = (width - gap * CGFloat(scopeButtons.count - 1)) / CGFloat(scopeButtons.count)
        for (index, item) in scopeButtons.enumerated() {
            item.view.frame = NSRect(
                x: originX + CGFloat(index) * (scopeWidth + gap),
                y: y,
                width: scopeWidth,
                height: Self.scopeHeight
            )
        }
    }
}

// MARK: - Un bouton

/// Pastille cliquable de l'onglet : un intitulé, un glyphe en option. Sélectionnée, elle prend
/// le jaune et un texte noir.
///
/// Le retour se fait à l'appui, pas au relâché : la pastille s'assombrit dès le `mouseDown`, et
/// ne déclenche qu'au `mouseUp` si le curseur est encore dessus — comme les bulles de la capsule.
private final class StayAwakeButtonView: NSView {

    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { applyStyle() }
    }

    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let cornerRadius: CGFloat?
    private var palette = OverlayPalette.resolved(for: .currentDrawing())
    private var isPressed = false

    /// `cornerRadius` à `nil` : une pastille entière, rayon égal à la moitié de la hauteur.
    init(title: String, symbolName: String? = nil, cornerRadius: CGFloat? = 8) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous

        label.stringValue = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        if let symbolName {
            let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
                .withSymbolConfiguration(configuration)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(iconView)
        }
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyPalette(_ palette: OverlayPalette) {
        self.palette = palette
        applyStyle()
    }

    private func applyStyle() {
        let content = isSelected ? NSColor.black : palette.tabActiveContent
        layer?.backgroundColor = isSelected ? StayAwakeStyle.accent.cgColor : palette.tabCapsuleFill
        layer?.opacity = isPressed ? 0.65 : 1
        label.textColor = content
        iconView.contentTintColor = content
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius ?? bounds.height / 2

        // Le texte prend tout le reste de la largeur plutôt que sa largeur mesurée : la cellule d'un
        // `NSTextField` retranche ses marges du cadre, et une largeur juste le coupe en « … ».
        let textHeight = label.intrinsicContentSize.height
        let textY = bounds.midY - textHeight / 2
        guard iconView.image != nil else {
            label.alignment = .center
            label.frame = NSRect(x: 2, y: textY, width: max(0, bounds.width - 4), height: textHeight)
            return
        }
        let iconWidth: CGFloat = 13
        let iconGap: CGFloat = 3
        let content = iconWidth + iconGap + ceil(label.intrinsicContentSize.width)
        let x = max(4, bounds.midX - content / 2)
        iconView.frame = NSRect(x: x, y: bounds.midY - iconWidth / 2, width: iconWidth, height: iconWidth)
        label.alignment = .left
        let labelX = x + iconWidth + iconGap
        label.frame = NSRect(x: labelX, y: textY, width: max(0, bounds.maxX - 2 - labelX), height: textHeight)
    }

    /// Même raison que pour une bulle de la capsule : le texte et le glyphe sont des sous-vues,
    /// et c'est eux que le clic atteindrait.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        applyStyle()
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != isPressed else { return }
        isPressed = inside
        applyStyle()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        applyStyle()
        guard inside else { return }
        ButtonSound.shared.playClick()
        onClick?()
    }
}
