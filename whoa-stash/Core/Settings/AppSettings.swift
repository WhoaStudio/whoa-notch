import AppKit

/// Couleur d'accent de l'overlay : la teinte des graduations actives du widget de luminosité
/// et de la plaque derrière la bague survolée du panneau de l'encoche.
///
/// `.green` est la valeur par défaut parce que c'est la teinte historique de l'app — le vert
/// était écrit en dur dans `OverlayPalette` avant que ce réglage ne pilote quoi que ce soit.
/// `.system` suit la couleur d'accent de macOS, dont la résolution dépend de l'apparence de
/// dessin courante — toujours sombre, l'app n'en a plus qu'une.
enum AccentColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case green
    case system
    case blue
    case purple
    case orange
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green: return "Whoa Green"
        case .system: return "System"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .pink: return "Pink"
        }
    }

    var color: NSColor {
        switch self {
        case .green: return NSColor(cgColor: OverlayPalette.activeGreen) ?? .systemGreen
        case .system: return .controlAccentColor
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .pink: return .systemPink
        }
    }

    /// Résout la couleur *dans* une apparence donnée : `.system` et les couleurs système sont
    /// dynamiques, et leur `cgColor` dépend de l'apparence de dessin courante au moment de la
    /// lecture, qu'il faut donc poser explicitement.
    func cgColor(for appearance: NSAppearance) -> CGColor {
        var resolved = OverlayPalette.activeGreen
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }
}

/// Taille du widget de luminosité — sa hauteur seule. Sa largeur est celle d'une bande de
/// luminosité (`PanelGeometry.brightnessBandWidth`), plus étroite que le panneau latéral parce
/// que son contenu tient en peu de place : elle ne se règle pas.
enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// `.medium` vaut la hauteur plancher de la géométrie commune : c'est la taille que le
    /// widget avait avant que ce réglage ne le pilote.
    var panelHeight: CGFloat {
        switch self {
        case .small: return PanelGeometry.minimumPanelHeight - 60
        case .medium: return PanelGeometry.minimumPanelHeight
        case .large: return PanelGeometry.minimumPanelHeight + 80
        }
    }
}

/// Forme du panneau de l'encoche replié sur un écran sans encoche : suspendu au bord du haut
/// comme une encoche, ou pastille flottante sous ce bord, façon Dynamic Island.
enum NotchPanelStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case notch
    case island

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notch: return "Notch"
        case .island: return "Island"
        }
    }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    var launchAtLogin: Bool = false
    var accentColor: AccentColor = .green
    var enableAnimations: Bool = true
    var enableHapticFeedback: Bool = true
    var enableSoundFeedback: Bool = true
    /// Son « pop » sur les clics de boutons (`ButtonSound`), distinct du son des graduations.
    var enableButtonSound: Bool = true
    /// Opacité du fond des panneaux de l'overlay, de 0,35 (très translucide) à 1 (plein).
    /// Les fenêtres sont déjà `isOpaque = false` : c'est la silhouette peinte à l'intérieur qui
    /// porte le fond, donc baisser cette valeur laisse réellement voir le bureau à travers.
    var panelOpacity: Double = 1.0
    /// Raccourci global qui déplie/replie le panneau de l'encoche.
    var togglePanelShortcut: GlobalShortcut = .disabled
    /// Interrupteurs des surfaces qui n'ont pas de section dédiée dans les Préférences.
    var volumeDialEnabled: Bool = true
    var sidePanelEnabled: Bool = true
}

struct BrightnessSettings: Codable, Equatable, Sendable {
    var showPercentage: Bool = true
    /// Délai avant fermeture automatique une fois le curseur sorti du widget, en secondes.
    var autoHideDelay: Double = 0.2
    /// Multiplicateur d'intensité du glow (0...2, 1 = valeur par défaut de la palette).
    var glowIntensity: Double = 1.0
    /// Multiplicateur de la sensibilité au scroll (0.5...2.0, 1 = valeur par défaut).
    var scrollSensitivity: Double = 1.0
    var widgetPosition: EdgePosition = .left
    var widgetSize: WidgetSize = .medium
    var enableOverlay: Bool = true
}

/// Réglages du slider de volume ancré au bord de l'écran — pas de section dédiée dans les
/// Préférences aujourd'hui, mais centralisés ici comme le reste.
struct EdgeSliderSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var edgePosition: EdgePosition = .right
    var sliderHeight: Double = 160
    var sensitivity: Double = 1.0
}

/// Réglages du panneau de l'encoche — le placement haut-centre, distinct de la bande du bord
/// droit, qui garde ses propres réglages. Les deux peuvent être affichés en même temps ; ce
/// drapeau permet de n'en garder qu'un.
struct NotchPanelSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    /// Forme repliée sur un écran **sans** encoche matérielle ; un écran à encoche garde
    /// toujours la silhouette de l'encoche, quel que soit ce réglage.
    var notchlessStyle: NotchPanelStyle = .island
    /// Titres (`NotchTab.title`) des onglets coupés, en `[String]` pour tolérer un onglet disparu.
    var disabledTabs: [String] = []
    /// Ouverture au clic dans la zone sensible plutôt qu'au survol. Valable pour l'encoche et pour l'île.
    var opensOnClick: Bool = false
}

/// Racine unique des préférences de l'application, persistée automatiquement par
/// `SettingsStorage`. Aucune vue ni aucun contrôleur ne doit lire/écrire `UserDefaults`
/// directement — tout transite par ce modèle.
struct AppSettings: Codable, Equatable, Sendable {
    var general = GeneralSettings()
    var brightness = BrightnessSettings()
    var edgeSlider = EdgeSliderSettings()
    var notchPanel = NotchPanelSettings()
    var knock = KnockSettings()
    var spotify = SpotifySettings()
    var dock = DockSettings()
    var radialMenu = RadialMenuSettings()
    var ai = AISettings()
    var mail = MailSettings()
    var colorPicker = ColorPickerSettings()
    /// Vrai une fois la fenêtre de bienvenue fermée : elle ne s'affiche qu'au premier lancement.
    var hasSeenOnboarding = false

    static let `default` = AppSettings()
}
