import AppKit

/// Constantes visuelles partagées par toutes les vues de Préférences — un seul endroit à
/// ajuster pour garder la fenêtre cohérente.
enum SettingsMetrics {
  /// Hauteur taillée sur l'écran le plus dense — « General ». Le scroll view de
  /// `SettingsSectionViewController` reste le filet de sécurité.
  static let windowSize = NSSize(width: 760, height: 640)

  static let sidebarWidth: CGFloat = 224
  static let sidebarRowHeight: CGFloat = 38
  static let sidebarIconSize: CGFloat = 22

  static let contentInset: CGFloat = 16

  /// Barre d'en-tête fixe du volet ; le contenu commence 16 pt sous elle.
  static let headerHeight: CGFloat = 38
  static let contentTopInset: CGFloat = headerHeight + contentInset
  /// Haut du contenu d'un volet sans en-tête commun (« About »).
  static let headerlessTopInset: CGFloat = 44
  static let contentBottomInset: CGFloat = 16
  static let rowSpacing: CGFloat = 18

  /// Hauteur minimale d'une ligne de formulaire.
  static let rowMinHeight: CGFloat = 28
  static let rowControlGap: CGFloat = 16
  static let captionMaxWidth: CGFloat = 300

  static let headerIconSize: CGFloat = 22
  static let groupCornerRadius: CGFloat = 14
  static let groupInset: CGFloat = 12
  static let groupRowSpacing: CGFloat = 10

  static let sliderWidth: CGFloat = 180
  static let keyButtonSize = NSSize(width: 280, height: 34)
  static let bannerWidth: CGFloat = 360
  static let bannerCornerRadius: CGFloat = 14

  static let choiceSpacing: CGFloat = 10
  static let iconChoiceSize: CGFloat = 52
  static let thumbnailSize = NSSize(width: 84, height: 56)

  /// Durée des micro-animations quand `enableAnimations` est actif.
  static let transitionDuration: TimeInterval = 0.18
}
