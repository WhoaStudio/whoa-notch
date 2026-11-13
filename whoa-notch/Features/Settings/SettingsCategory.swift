import AppKit

/// Une catégorie de la sidebar des Préférences — ordre d'affichage = ordre des cas.
enum SettingsCategory: String, CaseIterable, Identifiable {
  case general
  case appearance
  case screens
  case privacy
  case brightness
  case radialMenu
  case dock
  case profiles
  case ai
  case mail
  case about

  var id: String { rawValue }

  /// Groupe de la sidebar : une coupure d'espace sépare deux groupes. Les réglages de base, puis
  /// les fonctions, puis « About » seul en bas.
  var sidebarGroup: Int {
    switch self {
    case .general, .appearance, .screens, .privacy: return 0
    case .brightness, .radialMenu, .dock, .profiles, .ai, .mail: return 1
    case .about: return 2
    }
  }

  var title: String {
    switch self {
    case .general: return "General"
    case .appearance: return "Appearance"
    case .screens: return "Screens"
    case .privacy: return "Privacy & Permissions"
    case .brightness: return "Brightness"
    case .radialMenu: return "Radial Menu"
    case .dock: return "Dock"
    case .profiles: return "Profiles"
    case .ai: return "AI"
    case .mail: return "Mail"
    case .about: return "About"
    }
  }

  var symbolName: String {
    switch self {
    case .general: return "gearshape"
    case .appearance: return "paintpalette"
    case .screens: return "display.2"
    case .privacy: return "hand.raised.fill"
    case .brightness: return "sun.max"
    case .radialMenu: return "circle.dotted"
    case .dock: return "dock.rectangle"
    case .profiles: return "square.grid.2x2"
    case .ai: return "sparkles"
    case .mail: return "envelope"
    case .about: return "info.circle"
    }
  }

  /// Sous-titre gris de l'en-tête du volet.
  var subtitle: String {
    switch self {
    case .general:
      return "Startup behaviour, surfaces, appearance, feedback and your Spotify account."
    case .appearance: return "Size, spacing, corners and shadow of the dock."
    case .screens: return "The displays the dock appears on."
    case .privacy:
      return "Whoa Notch is local-first. It only asks for a permission when a feature needs it."
    case .brightness: return "The brightness band and the displays it controls."
    case .radialMenu: return "The round menu that opens under the cursor."
    case .dock: return "The custom Dock at the bottom of the screen."
    case .profiles: return "Dock profiles and the widgets in each one."
    case .ai: return "Usage rings and Claude Code agent events."
    case .mail: return "New-mail notifications in the notch."
    case .about: return "Version, credits and links."
    }
  }

  /// Couleur du carré d'icône dans la sidebar et l'en-tête.
  var tint: NSColor {
    switch self {
    case .general, .about: return .systemGray
    case .appearance: return .systemRed
    case .screens: return .systemCyan
    case .privacy: return .systemBlue
    case .brightness: return .systemOrange
    case .radialMenu: return .systemBlue
    case .dock: return .systemTeal
    case .profiles: return .systemIndigo
    case .ai: return .systemPink
    case .mail: return .systemBlue
    }
  }
}
