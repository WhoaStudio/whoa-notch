import AppKit

enum SettingsPalette {
  /// Fond des pastilles, bannières et boutons : un voile clair sur le fond sombre de la fenêtre.
  static let fill = NSColor.white.withAlphaComponent(0.08)

  /// Fond de l'onglet ou de l'option sélectionnée, un cran au-dessus de `fill`.
  static let selectedFill = NSColor.white.withAlphaComponent(0.14)

  static let rule = NSColor.separatorColor

  /// Fond de la fenêtre (gris 0,16 en sombre, 0,93 en clair), comme la fenêtre de whoa-type.
  static let windowBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(calibratedWhite: 0.16, alpha: 1)
      : NSColor(calibratedWhite: 0.93, alpha: 1)
  }

  /// Carte d'un groupe : fond de contrôle à 85 % et liseré à 12 %.
  static let groupFill = NSColor.controlBackgroundColor.withAlphaComponent(0.85)
  static let groupBorder = NSColor.labelColor.withAlphaComponent(0.12)

  /// Ligne sélectionnée de la sidebar.
  static let sidebarSelection = NSColor.labelColor.withAlphaComponent(0.09)
}
