import AppKit

/// Carte de l'onglet AI qui montre ce que fait un agent pendant qu'il travaille : à gauche son nom et
/// les étapes (Read, Edit, Bash, Done) avec la courante en avant ; à droite le fichier travaillé,
/// onglet, chemin et quelques lignes.
///
/// Elle prend la place de la carte d'utilisation ; une demande en attente passe devant (voir
/// `NotchUsageTabView`). Mise en page entièrement en frames, comme le reste de l'overlay.
final class AgentActivityCardView: NSView {

    private let logoView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "Claude Code")
    private let stepRows: [StepRow]
    private let tabBox = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let codeBox = NSView()
    private let lineNumbers: [NSTextField]
    private let codeLines: [NSTextField]
    private let captionLabel = NSTextField(labelWithString: "")

    private var startLine = 1
    private let inset: CGFloat = 16
    private let leftWidth: CGFloat = 112
    private let rowHeight: CGFloat = 15
    private let rowGap: CGFloat = 5

    override init(frame frameRect: NSRect) {
        stepRows = AgentStep.allCases.map(StepRow.init)
        lineNumbers = (0..<ToolCall.previewLines).map { _ in NSTextField(labelWithString: "") }
        codeLines = (0..<ToolCall.previewLines).map { _ in NSTextField(labelWithString: "") }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor

        logoView.image = NSImage(named: "ClaudeLogo")
        logoView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.55)

        tabBox.wantsLayer = true
        tabBox.layer?.cornerRadius = 8
        tabBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        badgeLabel.font = .systemFont(ofSize: 8, weight: .heavy)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 3
        badgeLabel.layer?.backgroundColor = NSColor.systemBlue.cgColor
        fileLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        fileLabel.textColor = .white
        fileLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        pathLabel.alignment = .right
        pathLabel.lineBreakMode = .byTruncatingHead

        codeBox.wantsLayer = true
        codeBox.layer?.cornerRadius = 10
        codeBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        for label in lineNumbers {
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = NSColor.white.withAlphaComponent(0.3)
            label.alignment = .right
        }
        for label in codeLines {
            label.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
        }
        captionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        captionLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        captionLabel.alignment = .center

        [logoView, nameLabel, sourceLabel, tabBox, pathLabel, codeBox].forEach(addSubview)
        stepRows.forEach(addSubview)
        [badgeLabel, fileLabel].forEach(tabBox.addSubview)
        (lineNumbers + codeLines + [captionLabel]).forEach(codeBox.addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ activity: AgentActivity) {
        nameLabel.stringValue = activity.project
        for row in stepRows {
            let state: StepRow.State
            if activity.step == row.step { state = row.step == .done ? .visited : .current }
            else if activity.visited.contains(row.step) { state = .visited }
            else { state = .pending }
            row.apply(state)
        }

        // Onglet : le fichier, ou l'outil quand il n'y en a pas (commande, recherche).
        let path = activity.filePath ?? ""
        let name = path.isEmpty ? (activity.toolName ?? "") : (path as NSString).lastPathComponent
        fileLabel.stringValue = name
        pathLabel.stringValue = path
        let ext = (name as NSString).pathExtension
        badgeLabel.stringValue = ext.isEmpty ? (activity.step == .bash ? "SH" : "•") : String(ext.prefix(2)).uppercased()
        badgeLabel.layer?.backgroundColor = Self.badgeColor(ext: ext).cgColor
        tabBox.isHidden = name.isEmpty

        startLine = activity.startLine
        let showCode = activity.step == .bash || activity.filePath != nil
        for index in 0..<ToolCall.previewLines {
            let hasLine = index < activity.snippet.count
            codeLines[index].isHidden = !hasLine
            lineNumbers[index].isHidden = !hasLine || activity.step == .bash
            if hasLine {
                codeLines[index].attributedStringValue = Self.highlight(activity.snippet[index])
                lineNumbers[index].stringValue = String(startLine + index)
            }
        }
        captionLabel.isHidden = !activity.snippet.isEmpty
        captionLabel.stringValue =
            activity.step == .done ? "Done"
            : (activity.toolName.map { "Using \($0)" } ?? "Thinking…")
        codeBox.isHidden = !showCode && activity.snippet.isEmpty && activity.step == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let top = bounds.maxY - inset

        // Le logo garde le rapport de l'image (586 × 366).
        logoView.frame = NSRect(x: inset, y: top - 26, width: 42, height: 26)
        nameLabel.frame = NSRect(x: inset, y: top - 26 - 24, width: leftWidth - inset, height: 20)
        sourceLabel.frame = NSRect(x: inset, y: nameLabel.frame.minY - 15, width: leftWidth - inset, height: 14)
        var y = sourceLabel.frame.minY - 10 - rowHeight
        for row in stepRows {
            row.frame = NSRect(x: inset, y: y, width: leftWidth - inset, height: rowHeight)
            y -= rowHeight + rowGap
        }

        let rightX = leftWidth + 6
        let rightWidth = bounds.width - rightX - inset
        let tabHeight: CGFloat = 26
        tabBox.frame = NSRect(x: rightX, y: top - tabHeight, width: min(rightWidth * 0.6, 200), height: tabHeight)
        badgeLabel.frame = NSRect(x: 8, y: (tabHeight - 13) / 2, width: 18, height: 13)
        fileLabel.frame = NSRect(x: 32, y: (tabHeight - 16) / 2, width: tabBox.frame.width - 38, height: 16)
        let pathX = tabBox.frame.maxX + 10
        pathLabel.frame = NSRect(x: pathX, y: top - tabHeight + 5, width: max(0, rightX + rightWidth - pathX), height: 14)

        let boxTop = top - tabHeight - 8
        codeBox.frame = NSRect(x: rightX, y: inset, width: rightWidth, height: max(0, boxTop - inset))
        let lineHeight: CGFloat = 14
        for index in 0..<ToolCall.previewLines {
            let lineY = codeBox.bounds.maxY - 10 - lineHeight * CGFloat(index + 1)
            lineNumbers[index].frame = NSRect(x: 4, y: lineY, width: 26, height: lineHeight)
            codeLines[index].frame = NSRect(x: 36, y: lineY, width: max(0, codeBox.bounds.width - 40), height: lineHeight)
        }
        captionLabel.frame = NSRect(x: 0, y: codeBox.bounds.midY - 8, width: codeBox.bounds.width, height: 16)
    }

    // MARK: - Coloration

    private static func badgeColor(ext: String) -> NSColor {
        switch ext.lowercased() {
        case "ts", "tsx": .systemBlue
        case "js", "jsx": .systemYellow.blended(withFraction: 0.4, of: .black) ?? .systemYellow
        case "swift": .systemOrange
        case "py": .systemGreen
        case "md": .systemGray
        default: .systemPurple
        }
    }

    private static let keywords: NSRegularExpression = {
        let words = [
            "import", "from", "const", "let", "var", "function", "export", "return", "if", "else", "for", "while",
            "class", "struct", "enum", "func", "def", "async", "await", "new", "true", "false", "null", "nil", "in",
            "of", "type", "interface", "case", "switch", "guard", "static", "private", "public", "final", "extension",
        ]
        return try! NSRegularExpression(pattern: "\\b(" + words.joined(separator: "|") + ")\\b")
    }()
    private static let numbers = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
    private static let strings = try! NSRegularExpression(pattern: "'[^']*'|\"[^\"]*\"|`[^`]*`")
    private static let comments = try! NSRegularExpression(pattern: "(//|#).*$")

    /// Coloration légère par motifs : mots-clés, nombres, chaînes, commentaires. Pas de grammaire.
    static func highlight(_ line: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: line,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ])
        let whole = NSRange(location: 0, length: (line as NSString).length)
        let rules: [(NSRegularExpression, NSColor)] = [
            (keywords, NSColor(srgbRed: 0.69, green: 0.55, blue: 0.95, alpha: 1)),
            (numbers, NSColor(srgbRed: 0.93, green: 0.55, blue: 0.5, alpha: 1)),
            (strings, NSColor(srgbRed: 0.93, green: 0.74, blue: 0.5, alpha: 1)),
            (comments, NSColor.white.withAlphaComponent(0.4)),
        ]
        for (regex, color) in rules {
            regex.enumerateMatches(in: line, range: whole) { match, _, _ in
                if let range = match?.range { result.addAttribute(.foregroundColor, value: color, range: range) }
            }
        }
        return result
    }
}

/// Une ligne de la liste d'étapes : glyphe (ou roue pour l'étape courante) et titre.
private final class StepRow: NSView {

    enum State { case pending, visited, current }

    let step: AgentStep
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let spinner = NSProgressIndicator()

    init(_ step: AgentStep) {
        self.step = step
        titleLabel = NSTextField(labelWithString: step.title)
        super.init(frame: .zero)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = NSImage(systemSymbolName: step.symbolName, accessibilityDescription: step.title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        [iconView, titleLabel, spinner].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ state: State) {
        let alpha: CGFloat = state == .pending ? 0.3 : (state == .current ? 1 : 0.6)
        titleLabel.textColor = NSColor.white.withAlphaComponent(alpha)
        titleLabel.font = .systemFont(ofSize: 14, weight: state == .current ? .bold : .medium)
        iconView.contentTintColor =
            step == .done && state != .pending ? .systemGreen : NSColor.white.withAlphaComponent(alpha)
        iconView.isHidden = state == .current
        if state == .current { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let icon: CGFloat = 14
        iconView.frame = NSRect(x: 0, y: (bounds.height - icon) / 2, width: icon, height: icon)
        spinner.frame = iconView.frame
        titleLabel.frame = NSRect(x: icon + 9, y: 0, width: max(0, bounds.width - icon - 9), height: bounds.height)
    }
}
