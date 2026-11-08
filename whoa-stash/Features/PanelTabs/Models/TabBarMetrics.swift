import CoreGraphics

/// Mesures de la capsule de navigation : la barre détachée, posée sous le panneau de l'encoche,
/// qui porte les onglets.
///
/// Elles vivent à part de `NotchPanelGeometry` parce qu'elles décrivent la capsule elle-même —
/// ce qu'elle porte et comment c'est espacé — là où la géométrie du panneau ne décide que de
/// l'endroit où elle se pose. La capsule ne se resserre jamais : ses bulles ne portent que des
/// glyphes, donc sa largeur est une constante et non le résultat d'une mesure de texte.
enum TabBarMetrics {

  /// Hauteur de la capsule. Les bulles sont un peu plus basses qu'elle pour qu'il lui reste de
  /// l'air au-dessus et au-dessous.
  static let capsuleHeight: CGFloat = 40

  /// Côté d'une bulle : la zone cliquable d'un onglet, et le cercle de l'onglet actif.
  static let bubbleSize: CGFloat = 32

  /// Écart entre deux bulles d'onglet. Les cercles ne se touchent jamais, pas même entre deux
  /// onglets voisins.
  static let bubbleSpacing: CGFloat = 6

  /// Marges de la capsule de part et d'autre de la rangée de bulles.
  static let capsuleHorizontalPadding: CGFloat = 6

  /// Taille du glyphe au centre d'une bulle.
  static let iconSize: CGFloat = 15
}
