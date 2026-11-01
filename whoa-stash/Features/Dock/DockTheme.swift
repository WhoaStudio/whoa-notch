import AppKit

/// Thème du dock : choisit le fond des capsules. Ajouter un thème = un cas ici et un
/// `DockSurfaceBackground`, sans toucher aux vues du dock.
enum DockTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark
    case liquidGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    /// Vrai quand le système est en mode sombre ; le Dock macOS le suit, pas l'app (`.darkAqua`).
    static var systemIsDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    /// La couleur de ce qui se dessine sur le fond (points, séparateur, noms) : blanc sur le fond
    /// sombre, noir sur du verre clair comme dans le vrai Dock.
    var ink: NSColor {
        switch self {
        case .dark: return .white
        case .liquidGlass: return Self.systemIsDark ? .white : .black
        }
    }

    func makeBackground() -> DockSurfaceBackground {
        switch self {
        case .dark: return DarkDockBackground()
        case .liquidGlass: return GlassDockBackground()
        }
    }
}

/// Fond d'une capsule du dock ; il remplit sa surface et suit son rayon d'angle.
@MainActor
class DockSurfaceBackground: NSView {
    var cornerRadius: CGFloat = 0 { didSet { cornerRadiusChanged() } }
    func cornerRadiusChanged() {}
}

/// Fond plein d'origine, identique à celui du panneau de l'encoche.
final class DarkDockBackground: DockSurfaceBackground {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = OverlayPalette.base.panelBackground
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func cornerRadiusChanged() { layer?.cornerRadius = cornerRadius }
}

/// Verre translucide natif (`NSGlassEffectView`) : aucun aplat dessous, le bureau transparaît.
/// L'app force `.darkAqua`, mais le Dock macOS suit le système : le verre en fait autant, sans
/// quoi il serait teinté de sombre sur un bureau clair.
final class GlassDockBackground: DockSurfaceBackground {
    private let glass = NSGlassEffectView()
    private var observer: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        syncAppearance()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAppearance() }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    private func syncAppearance() {
        glass.appearance = NSAppearance(named: DockTheme.systemIsDark ? .darkAqua : .aqua)
    }

    override func cornerRadiusChanged() { glass.cornerRadius = cornerRadius }
}

/// Une capsule du dock : un fond interchangeable sous le contenu éventuel.
final class DockSurfaceView: NSView {
    private var background: DockSurfaceBackground?
    private(set) var theme: DockTheme?
    var cornerRadius: CGFloat = 0 {
        didSet { background?.cornerRadius = cornerRadius }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func apply(theme newTheme: DockTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        background?.removeFromSuperview()
        let next = newTheme.makeBackground()
        next.frame = bounds
        next.autoresizingMask = [.width, .height]
        next.cornerRadius = cornerRadius
        addSubview(next, positioned: .below, relativeTo: nil)
        background = next
    }
}
