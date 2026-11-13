import AppKit

enum SettingsPalette {
  /// Fond des pastilles, bannières et boutons : un voile clair sur le fond sombre de la fenêtre.
  static let fill = NSColor.white.withAlphaComponent(0.08)

  /// Fond de l'onglet ou de l'option sélectionnée, un cran au-dessus de `fill`.
  static let selectedFill = NSColor.white.withAlphaComponent(0.14)

  static let rule = NSColor.separatorColor
}
