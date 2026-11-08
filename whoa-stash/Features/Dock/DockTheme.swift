import AppKit

/// Thème du dock : choisit le fond des capsules. Ajouter un thème = un cas ici et un
/// `DockSurfaceBackground`, sans toucher aux vues du dock.
enum DockTheme: String, Codable, CaseIterable, Identifiable, Sendable {
  case dark
  case liquidGlass

  var id: String { rawValue }

  /// Interrupteur du Liquid Glass : désactivé temporairement (« Coming soon… »). Le code du verre
  /// reste en place ; passer à `true` le réactive, y compris dans les réglages.
  static let liquidGlassEnabled = false

  /// Vrai quand le thème peut être choisi et rendu.
  var isAvailable: Bool { self != .liquidGlass || Self.liquidGlassEnabled }

  var displayName: String {
    switch self {
    case .dark: return "Dark"
    case .liquidGlass: return "Liquid Glass"
    }
  }

  /// Vrai quand le système est en mode sombre ; le Dock macOS le suit, pas l'app (`.darkAqua`).
  static var systemIsDark: Bool {
    UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
  }

  /// La couleur de ce qui se dessine sur le fond (points, séparateur, noms) : blanc sur le fond
  /// sombre, noir sur du verre clair comme dans le vrai Dock.
  var ink: NSColor {
    switch self {
    case .dark: return .white
    case .liquidGlass: return !isAvailable || Self.systemIsDark ? .white : .black
    }
  }

  func makeBackground() -> DockSurfaceBackground {
    switch self {
    case .dark: return DarkDockBackground()
    case .liquidGlass: return isAvailable ? GlassDockBackground() : DarkDockBackground()
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
  /// « Reduce transparency » : le fond est peint sans aucune transparence.
  var reducesTransparency = false { didSet { updateFill() } }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    updateFill()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  private func updateFill() {
    let base = OverlayPalette.base.panelBackground
    layer?.backgroundColor = reducesTransparency ? (base.copy(alpha: 1) ?? base) : base
  }

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
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
      queue: .main
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
  private(set) var reducesTransparency = false
  var cornerRadius: CGFloat = 0 {
    didSet { background?.cornerRadius = cornerRadius }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  /// `opaque` : « Reduce transparency » ; un fond translucide (verre) passe alors au fond plein.
  func apply(theme newTheme: DockTheme, opaque: Bool = false) {
    guard newTheme != theme || opaque != reducesTransparency else { return }
    theme = newTheme
    reducesTransparency = opaque
    background?.removeFromSuperview()
    var next = newTheme.makeBackground()
    if opaque, !(next is DarkDockBackground) { next = DarkDockBackground(frame: .zero) }
    (next as? DarkDockBackground)?.reducesTransparency = opaque
    next.frame = bounds
    next.autoresizingMask = [.width, .height]
    next.cornerRadius = cornerRadius
    addSubview(next, positioned: .below, relativeTo: nil)
    background = next
  }
}
