import AppKit

/// Bague d'utilisation d'un fournisseur : un anneau qui se remplit dans le sens horaire depuis
/// midi, la marque du fournisseur au centre, et le pourcentage dessous.
///
/// Tout est en calques, le texte aussi, pour que le ressort de survol emporte l'ensemble d'un
/// seul bloc. La vue ne reçoit aucun événement — la fenêtre de la bande laisse tout passer —
/// donc c'est `SidePanelController` qui lui annonce le survol par `setHighlighted(_:)`.
final class ClaudeUsageRingView: NSView {

    private let contentLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let markLayer = CAShapeLayer()
    private let percentLayer = CATextLayer()

    private var state: ClaudeUsageState = .loading
    private var isHighlighted = false

    /// Proportions de la case, toutes relatives à `tileSize` : le Dock système change de taille
    /// avec les préférences de l'utilisateur, et l'anneau doit suivre sans constante codée.
    private let labelHeightRatio: CGFloat = 0.24
    private let gapRatio: CGFloat = 0.04
    private let strokeWidthRatio: CGFloat = 0.11
    private let markDiameterRatio: CGFloat = 0.46

    private let mark: UsageMarkPath
    private let serviceName: String

    init(tileSize: CGFloat, mark: UsageMarkPath = .claude, serviceName: String = "Claude Code") {
        self.mark = mark
        self.serviceName = serviceName
        super.init(frame: NSRect(x: 0, y: 0, width: tileSize, height: tileSize))
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(contentLayer)

        for shape in [trackLayer, progressLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            contentLayer.addSublayer(shape)
        }
        // L'anneau part de midi et tourne dans le sens horaire : c'est le chemin lui-même qui
        // porte cette orientation, `strokeEnd` n'a plus qu'à exprimer la fraction remplie.
        progressLayer.strokeEnd = 0

        // Le tracé officiel d'OpenAI se referme sur lui-même : sans « even-odd », son nœud
        // central se remplirait.
        markLayer.fillRule = mark.usesEvenOddFill ? .evenOdd : .nonZero
        contentLayer.addSublayer(markLayer)

        percentLayer.alignmentMode = .center
        percentLayer.truncationMode = .none
        contentLayer.addSublayer(percentLayer)

        applyAppearance()
        applyState(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
        applyState(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Sans ça, `CATextLayer` rend flou sur écran Retina : contrairement à un NSTextField,
        // il ne récupère pas l'échelle de la fenêtre tout seul.
        let scale = window?.backingScaleFactor ?? 2
        percentLayer.contentsScale = scale
        markLayer.contentsScale = scale
    }

    // MARK: - État

    func apply(_ newState: ClaudeUsageState, animated: Bool) {
        state = newState
        applyState(animated: animated)
    }

    func applyCopilot(_ newState: CopilotUsageState, animated: Bool) {
        apply(newState.ringState, animated: animated)
        switch newState {
        case .loaded(let snapshot):
            toolTip = "\(serviceName) — premium interactions \(snapshot.premiumInteractions.percentage) %"
        case .loading:
            toolTip = "\(serviceName) — chargement de l'utilisation…"
        case .unavailable(let reason):
            toolTip = "\(serviceName) — \(reason)"
        }
    }

    private func applyState(animated: Bool) {
        let session = state.snapshot?.session

        let fill = session.map { CGFloat($0.utilization) } ?? 0
        let color = session.map { ClaudeUsagePalette.color(for: $0.utilization) }
            ?? ClaudeUsagePalette.unavailable

        if animated {
            progressLayer.springAnimate(keyPath: "strokeEnd", to: fill, preset: .snappy)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = fill
            CATransaction.commit()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        progressLayer.strokeColor = color
        markLayer.fillColor = color
        CATransaction.commit()

        switch state {
        case .loaded(let snapshot):
            percentLayer.string = "\(snapshot.session.percentage)%"
            toolTip = "\(serviceName) — session \(snapshot.session.percentage) % · tous modèles \(snapshot.allModels.percentage) %"
        case .loading:
            percentLayer.string = "–"
            toolTip = "\(serviceName) — chargement de l'utilisation…"
        case .unavailable(let reason), .expired(let reason):
            percentLayer.string = serviceName == "GitHub Copilot" ? "N/A" : "–"
            toolTip = "\(serviceName) — \(reason)"
        }
    }

    private func applyAppearance() {
        let palette = OverlayPalette.resolved(for: effectiveAppearance)
        trackLayer.strokeColor = ClaudeUsagePalette.track
        // Même encre que le reste de la bande : `NSColor.labelColor` se résolvait sur
        // l'apparence de dessin courante et non sur celle de la vue, ce qui donnait un
        // pourcentage noir sur fond sombre.
        percentLayer.foregroundColor = palette.buttonSymbolColor.cgColor
    }

    // MARK: - Mise en page

    override func layout() {
        super.layout()

        contentLayer.frame = bounds
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let tileSize = min(bounds.width, bounds.height)
        let labelHeight = tileSize * labelHeightRatio
        let gap = tileSize * gapRatio
        let ringDiameter = min(bounds.width, bounds.height - labelHeight - gap)
        let strokeWidth = ringDiameter * strokeWidthRatio

        // L'anneau occupe le haut de la case, le pourcentage se loge dessous — comme dans la
        // référence, où le chiffre est posé sous la bague et non à l'intérieur.
        let ringCenter = CGPoint(x: bounds.midX, y: bounds.maxY - ringDiameter / 2)
        let radius = (ringDiameter - strokeWidth) / 2

        let circle = CGMutablePath()
        circle.addArc(
            center: ringCenter,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true
        )

        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = circle
            shape.lineWidth = strokeWidth
        }

        let markDiameter = ringDiameter * markDiameterRatio
        markLayer.frame = bounds
        markLayer.path = mark.path(
            in: CGRect(
                x: ringCenter.x - markDiameter / 2,
                y: ringCenter.y - markDiameter / 2,
                width: markDiameter,
                height: markDiameter
            )
        )

        let fontSize = labelHeight * 0.86
        percentLayer.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        percentLayer.fontSize = fontSize
        percentLayer.frame = NSRect(x: 0, y: bounds.minY, width: bounds.width, height: labelHeight)
    }

    // MARK: - Survol

    /// Ressort de survol, séparé des événements de souris : la bande latérale n'installe aucune
    /// `NSTrackingArea`, donc aucun `mouseEntered` n'y arrive jamais — c'est le contrôleur qui
    /// déduit le survol de la position du curseur et l'annonce ici.
    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
    }

    override func mouseDown(with event: NSEvent) {
        contentLayer.springAnimate(keyPath: "transform.scale", to: 0.88, preset: .snappy)
    }

    /// Pas de callback au clic : la bulle d'utilisation est déjà ouverte, puisqu'il faut survoler
    /// la bague pour la cliquer. Seul le ressort d'enfoncement subsiste.
    override func mouseUp(with event: NSEvent) {
        isHighlighted = bounds.contains(convert(event.locationInWindow, from: nil))
        contentLayer.springAnimate(keyPath: "transform.scale", to: 1.0, preset: .snappy)
    }

}
