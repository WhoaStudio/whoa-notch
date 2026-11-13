import Foundation

/// Apparence réglée dans Préférences ▸ Appearance. Les cotes d'espacement et de rayon sont en
/// points de référence (icône de 52 pt) ; le dock les met à l'échelle comme le reste.
struct DockStyle: Equatable, Sendable {
  /// Taille du dock, en pourcentage de la taille d'icône du Dock macOS.
  var sizePercent: Double = 100
  var widgetSpacing: CGFloat = 8
  var cornerRadius: CGFloat = 14
  var shadow = false
  var monochromeWidgets = false
  var tileBackgrounds = false
  var reduceTransparency = false
  var grayscaleIcons = false
  /// Réduit les icônes quand la rangée ne tient pas sur l'écran.
  var adaptsToFit = true

  /// Largeur de la rangée divisée par la taille d'icône, pour `n` icônes espacées de `spacing`
  /// (points de référence), plus la place de l'icône de réserve et les marges, qui sont
  /// proportionnelles à la taille.
  static func widthFactor(count: Int, spacing: CGFloat) -> CGFloat {
    let n = CGFloat(count)
    return n + 1 + (n * spacing + 24) / 52
  }

  /// Taille d'icône qui fait tenir `count` icônes dans `available` points. Ne grandit jamais au-delà de `base`.
  static func fittedIconSize(base: CGFloat, count: Int, spacing: CGFloat, available: CGFloat)
    -> CGFloat
  {
    guard count > 0, available > 0 else { return base }
    return min(base, available / widthFactor(count: count, spacing: spacing))
  }
}

/// Réglages du Dock macOS que le dock personnalisé reprend par défaut : taille des icônes,
/// agrandissement au survol, masquage auto, rebond au lancement. Lus dans `com.apple.dock`.
struct DockAppearance: Equatable, Sendable {
  var iconSize: CGFloat = 48
  var magnification = false
  var magnifiedSize: CGFloat = 128
  var autohide = false
  /// Délai avant l'apparition au contact du bord, en secondes.
  var revealDelay: Double = 0.5
  var bounceOnLaunch = true
  /// Réglages « Appearance » de Préférences, par-dessus les valeurs du Dock macOS.
  var style = DockStyle()

  /// Quand l'app a masqué le Dock système, `autohide` et `autohide-delay` valent *nos* valeurs
  /// (masquage + 1000 s) : le dock personnalisé reprend alors celles de la sauvegarde, qui sont
  /// les vraies préférences de l'utilisateur.
  @MainActor
  static func read(from defaults: DockDefaultsAccessing, saved: SavedSystemDock?) -> DockAppearance
  {
    var result = DockAppearance()
    if let size = defaults.double("tilesize"), size > 0 { result.iconSize = CGFloat(size) }
    result.magnification = defaults.bool("magnification") ?? false
    if let large = defaults.double("largesize"), large > 0 { result.magnifiedSize = CGFloat(large) }
    result.magnifiedSize = max(result.magnifiedSize, result.iconSize)
    result.bounceOnLaunch = defaults.bool("launchanim") ?? true
    if let saved {
      result.autohide = saved.autohide ?? false
      if let delay = saved.autohideDelay { result.revealDelay = delay }
    } else {
      result.autohide = defaults.bool("autohide") ?? false
      if let delay = defaults.double("autohide-delay") { result.revealDelay = delay }
    }
    return result
  }
}
