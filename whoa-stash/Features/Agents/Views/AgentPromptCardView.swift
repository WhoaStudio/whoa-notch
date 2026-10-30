import AppKit

/// Carte de l'onglet AI qui montre ce que Claude demande : le projet, l'outil, puis la commande ou
/// le fichier — ou la question et ses choix. Elle prend la place de la carte d'utilisation tant
/// qu'une demande attend.
///
/// Quand la demande attend une réponse (`replyID`), des boutons répondent depuis l'encoche : Allow et
/// Deny pour un outil, un bouton par choix pour une question simple. Sinon (plusieurs questions,
/// choix multiples, simple notification), la réponse se donne dans Claude Code.
final class AgentPromptCardView: NSView {

    var onDecision: ((AgentEvent, AgentEvent.Decision) -> Void)?

    private var event: AgentEvent?
    private var buttons: [PromptButton] = []
    private let hintLabel = NSTextField(labelWithString: "Answer in Claude Code")
    private let buttonHeight: CGFloat = 30

    private let dotView = NSView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "Claude Code")
    private let kindLabel = NSTextField(labelWithString: "")
    private let bodyBox = NSView()
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")

    private let inset: CGFloat = 18

    /// Demande d'outil avec réponse possible : une pastille d'une ligne (point, « Allow: … ? »,
    /// Allow, Deny, logo) au lieu de la carte.
    private let pillView = NSView()
    private let pillDot = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    private let pillLogoBox = NSView()
    private let pillLogo = NSImageView()
    private var isPill = false
    private let pillHeight: CGFloat = 46

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dotView.layer?.cornerRadius = 4

        projectLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        projectLabel.textColor = .white
        projectLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.font = .systemFont(ofSize: 12, weight: .regular)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        kindLabel.font = .systemFont(ofSize: 12, weight: .medium)
        kindLabel.textColor = .systemOrange
        kindLabel.alignment = .right

        bodyBox.wantsLayer = true
        bodyBox.layer?.cornerRadius = 12
        bodyBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        bodyLabel.isSelectable = false
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyBox.addSubview(bodyLabel)

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        hintLabel.alignment = .center
        [dotView, projectLabel, sourceLabel, kindLabel, bodyBox, hintLabel].forEach(addSubview)

        let gold = NSColor(calibratedRed: 1, green: 0.72, blue: 0.25, alpha: 1)
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius = pillHeight / 2
        pillView.layer?.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 1).cgColor
        pillView.layer?.shadowColor = gold.cgColor
        pillView.layer?.shadowOpacity = 0.35
        pillView.layer?.shadowRadius = 8
        pillView.layer?.shadowOffset = .zero
        pillDot.wantsLayer = true
        pillDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        pillDot.layer?.cornerRadius = 5
        pillDot.layer?.shadowColor = NSColor.systemOrange.cgColor
        pillDot.layer?.shadowOpacity = 0.9
        pillDot.layer?.shadowRadius = 4
        pillDot.layer?.shadowOffset = .zero
        pillLabel.font = .systemFont(ofSize: 13, weight: .bold)
        pillLabel.textColor = .white
        pillLabel.lineBreakMode = .byTruncatingTail
        pillLogoBox.wantsLayer = true
        pillLogoBox.layer?.cornerRadius = 15
        pillLogoBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        pillLogoBox.layer?.borderWidth = 1
        pillLogoBox.layer?.borderColor = gold.withAlphaComponent(0.6).cgColor
        pillLogoBox.layer?.shadowColor = gold.cgColor
        pillLogoBox.layer?.shadowOpacity = 0.6
        pillLogoBox.layer?.shadowRadius = 6
        pillLogoBox.layer?.shadowOffset = .zero
        pillLogo.image = NSImage(named: "ClaudeLogo")
            ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        pillLogo.imageScaling = .scaleProportionallyUpOrDown
        pillLogoBox.addSubview(pillLogo)
        [pillDot, pillLabel, pillLogoBox].forEach(pillView.addSubview)
        pillView.isHidden = true
        addSubview(pillView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ event: AgentEvent) {
        self.event = event
        if case .tool(let name, let detail) = event.prompt, event.replyID != nil {
            isPill = true
            let command = (detail.isEmpty ? name : detail)
                .components(separatedBy: .newlines).joined(separator: " ")
            pillLabel.stringValue = "Allow: \(command)?"
            pillView.toolTip = detail.isEmpty ? name : detail
        } else {
            isPill = false
            pillView.toolTip = nil
        }
        layer?.backgroundColor = (isPill ? NSColor.clear : NSColor.white.withAlphaComponent(0.07)).cgColor
        pillView.isHidden = !isPill
        [dotView, projectLabel, sourceLabel, kindLabel, bodyBox, hintLabel].forEach { $0.isHidden = isPill }
        rebuildButtons(for: event)
        projectLabel.stringValue = event.project
        let body = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let plain: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        let bold: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let dim: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]

        switch event.prompt {
        case .tool(let name, let detail):
            kindLabel.stringValue = "Permission · \(name)"
            body.append(NSAttributedString(string: detail.isEmpty ? name : detail, attributes: plain))
        case .questions(let questions):
            kindLabel.stringValue = questions.count > 1 ? "\(questions.count) questions" : "Question"
            for (index, question) in questions.enumerated() {
                if index > 0 { body.append(NSAttributedString(string: "\n\n", attributes: plain)) }
                body.append(NSAttributedString(string: question.text, attributes: bold))
                for option in question.options {
                    body.append(NSAttributedString(string: "\n\(question.multiSelect ? "☐" : "○") \(option.label)", attributes: bold))
                    if !option.detail.isEmpty {
                        body.append(NSAttributedString(string: "  \(option.detail)", attributes: dim))
                    }
                }
            }
        case .message(let text):
            kindLabel.stringValue = "Needs input"
            body.append(NSAttributedString(string: text, attributes: [.font: bold[.font]!, .foregroundColor: NSColor.white]))
        case nil:
            kindLabel.stringValue = ""
        }
        bodyLabel.attributedStringValue = body
        needsLayout = true
    }

    /// Les actions que la demande permet depuis l'encoche ; vide quand la réponse reste dans Claude Code.
    private func actions(for event: AgentEvent) -> [(title: String, style: PromptButton.Style, decision: AgentEvent.Decision)] {
        guard event.replyID != nil else { return [] }
        switch event.prompt {
        case .tool:
            return [("Allow", .allow, .allow), ("Deny", .deny, .deny)]
        case .questions(let questions):
            guard questions.count == 1, let question = questions.first, !question.multiSelect else { return [] }
            return question.options.prefix(4).map {
                ($0.label, .allow, .answer([question.text: $0.label]))
            }
        default:
            return []
        }
    }

    private func rebuildButtons(for event: AgentEvent) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = actions(for: event).map { action in
            let button = PromptButton(title: action.title, style: action.style)
            button.onClick = { [weak self] in
                guard let self, let event = self.event else { return }
                self.onDecision?(event, action.decision)
            }
            (isPill ? pillView : self).addSubview(button)
            return button
        }
        hintLabel.isHidden = isPill || !buttons.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if isPill {
            layoutPill()
            return
        }
        let top = bounds.maxY - 14
        dotView.frame = NSRect(x: inset, y: top - 16 + 5, width: 8, height: 8)
        projectLabel.sizeToFit()
        let nameWidth = min(projectLabel.frame.width, bounds.width * 0.4)
        projectLabel.frame = NSRect(x: dotView.frame.maxX + 8, y: top - 18, width: nameWidth, height: 18)
        sourceLabel.frame = NSRect(x: projectLabel.frame.maxX + 8, y: top - 17, width: 100, height: 16)
        let kindX = bounds.width * 0.5
        kindLabel.frame = NSRect(x: kindX, y: top - 17, width: bounds.width - kindX - inset, height: 16)

        let boxTop = top - 26
        let footer: CGFloat = buttons.isEmpty ? 22 : buttonHeight + 10
        let boxBottom = 12 + footer
        bodyBox.frame = NSRect(
            x: inset, y: boxBottom, width: bounds.width - 2 * inset, height: max(0, boxTop - boxBottom))
        hintLabel.frame = NSRect(x: inset, y: 12, width: bounds.width - 2 * inset, height: 14)
        if !buttons.isEmpty {
            let gap: CGFloat = 8
            let width = (bounds.width - 2 * inset - gap * CGFloat(buttons.count - 1)) / CGFloat(buttons.count)
            for (index, button) in buttons.enumerated() {
                button.frame = NSRect(
                    x: inset + CGFloat(index) * (width + gap), y: 12, width: width, height: buttonHeight)
            }
        }
        bodyLabel.preferredMaxLayoutWidth = bodyBox.bounds.width - 20
        bodyLabel.frame = bodyBox.bounds.insetBy(dx: 10, dy: 8)
    }

    /// Seul le texte rétrécit : boutons et logo gardent leur largeur, une longue commande est tronquée.
    private func layoutPill() {
        pillView.frame = NSRect(x: 0, y: bounds.maxY - pillHeight, width: bounds.width, height: pillHeight)
        let h = pillView.bounds.height
        let buttonSize = CGSize(width: 66, height: 30)
        let logoSize: CGFloat = 30
        let gap: CGFloat = 8
        pillLogoBox.frame = NSRect(x: pillView.bounds.maxX - 10 - logoSize, y: (h - logoSize) / 2, width: logoSize, height: logoSize)
        pillLogo.frame = pillLogoBox.bounds.insetBy(dx: 5, dy: 5)
        var right = pillLogoBox.frame.minX - gap - 2
        for button in buttons.reversed() {
            right -= buttonSize.width
            button.frame = NSRect(origin: NSPoint(x: right, y: (h - buttonSize.height) / 2), size: buttonSize)
            right -= gap
        }
        pillDot.frame = NSRect(x: 18, y: (h - 10) / 2, width: 10, height: 10)
        let labelHeight = pillLabel.intrinsicContentSize.height
        let labelX = pillDot.frame.maxX + 10
        pillLabel.frame = NSRect(x: labelX, y: (h - labelHeight) / 2, width: max(0, right - labelX), height: labelHeight)
    }
}


/// Bouton plat de la carte : fond arrondi, plus clair au survol.
private final class PromptButton: NSView {

    enum Style { case allow, deny }

    var onClick: (() -> Void)?

    private let style: Style
    private let label: NSTextField
    private var isHovered = false { didSet { updateBackground() } }

    init(title: String, style: Style) {
        self.style = style
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = style == .allow
            ? NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.10, alpha: 1)
            : NSColor(calibratedRed: 1, green: 0.62, blue: 0.64, alpha: 1)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 8, y: (bounds.height - height) / 2, width: max(0, bounds.width - 16), height: height)
    }

    private func updateBackground() {
        let base = style == .allow
            ? NSColor(calibratedRed: 0.78, green: 0.91, blue: 0.62, alpha: 1)
            : NSColor(calibratedRed: 0.26, green: 0.12, blue: 0.11, alpha: 1)
        layer?.backgroundColor = (isHovered ? base.withAlphaComponent(0.8) : base).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
