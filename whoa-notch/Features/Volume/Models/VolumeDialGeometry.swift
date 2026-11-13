import AppKit

/// Géométrie du cadran de volume : un disque posé dans le coin supérieur gauche de l'écran,
/// appelé par une zone sensible carrée prise sur ce même coin.
///
/// Le cadran ne se suspend à aucun bord — c'est ce qui le distingue des bandes de flanc et du
/// panneau de l'encoche, qui se déplient depuis leur bord d'accroche et empruntent donc la
/// silhouette commune de `PanelGeometry`. Lui jaillit du curseur et reste un disque : il n'a
/// ni raccord ni évasement à décrire, seulement un rayon, une course angulaire et la façon
/// dont les graduations s'y répartissent.
///
/// Il reste malgré tout du même monde que les autres surfaces : sa marge au bord est celle de
/// `PanelGeometry.screenInset`, et sa matière vient de la même `OverlayPalette`.
enum VolumeDialGeometry {

  // MARK: - Cadre

  /// Diamètre du disque, qui est aussi le côté de la fenêtre : rien n'est peint hors du
  /// cercle, et ce qui dépasserait ne serait qu'une zone invisible retenant le cadran ouvert
  /// sous un curseur déjà parti.
  static let diameter: CGFloat = 156

  /// Marge conservée avec les deux bords du coin — la même que celle des bandes de flanc,
  /// pour que le cadran ne soit soudé ni à la barre de menus ni au flanc de l'écran.
  static let screenInset = PanelGeometry.screenInset

  /// Côté de la zone sensible, carrée et posée pile dans le coin supérieur gauche de la zone
  /// **visible** : la barre de menus occupe déjà le haut de l'écran, et une zone qui la
  /// recouvrirait n'aurait jamais le curseur pour elle.
  static let hotZoneSide: CGFloat = 24

  /// Cadre de la fenêtre du cadran, en coordonnées globales AppKit.
  static func panelFrame(on screen: NSScreen) -> NSRect {
    let visible = screen.visibleFrame
    return NSRect(
      x: visible.minX + screenInset,
      y: visible.maxY - screenInset - diameter,
      width: diameter,
      height: diameter
    )
  }

  /// Zone sensible : le carré du coin. Le cadre du cadran la recouvre largement, donc le
  /// curseur qui a appelé le disque est déjà « dessus » dès la première image — pas de
  /// fenêtre qui s'ouvre puis se referme aussitôt parce que le pointeur n'était nulle part.
  static func hotZone(on screen: NSScreen) -> NSRect {
    let visible = screen.visibleFrame
    return NSRect(
      x: visible.minX,
      y: visible.maxY - hotZoneSide,
      width: hotZoneSide,
      height: hotZoneSide
    )
  }

  // MARK: - Course angulaire

  /// Nombre de graduations réparties sur la course. La même valeur que la barre de
  /// luminosité, redite ici plutôt qu'empruntée à `BrightnessViewModel` : celui-ci est isolé
  /// sur l'acteur principal, et cette géométrie est lue depuis des calques qui ne le sont pas.
  static let tickCount = 36

  /// Départ de la course, en bas à gauche du disque.
  static let startAngle: CGFloat = .pi * 5 / 4

  /// Étendue de la course, parcourue dans le sens horaire : trois quarts de tour, donc une
  /// ouverture d'un quart de tour laissée en bas. Un cadran bouclé sur 360° ferait tomber le
  /// zéro et le cent au même endroit, et on ne saurait plus lequel des deux on regarde.
  static let sweep: CGFloat = .pi * 3 / 2

  /// Angle correspondant à une fraction de la course (`0` au départ, `1` à l'arrivée).
  static func angle(forFraction fraction: CGFloat) -> CGFloat {
    startAngle - sweep * min(max(fraction, 0), 1)
  }

  // MARK: - Traits

  /// Longueur d'une graduation longue, prise vers l'intérieur depuis le bord du disque.
  static let tickLength: CGFloat = 10
  static let tickThickness: CGFloat = 1.5

  /// Écart entre le bord peint du disque et le bout extérieur des graduations.
  static let tickOuterInset: CGFloat = 11

  /// Épaisseur du bandeau qui porte le niveau, et écart entre lui et les graduations.
  static let arcWidth: CGFloat = 7
  static let arcSpacing: CGFloat = 9

  /// Diamètre de la poignée qui court sur le bandeau — l'épaisseur du trait dont elle est
  /// l'embout, et non la taille d'une pastille posée dessus.
  static let handleDiameter: CGFloat = 15

  /// Longueur de ce trait, en part de la course. Assez courte pour que ses deux embouts se
  /// confondent en un point rond, assez longue pour que Core Animation ait bien un segment à
  /// tracer : un segment vide ne rend rien du tout.
  static let handleStrokeLength: CGFloat = 0.002

  /// Rayon sur lequel courent le bandeau et la poignée, pour un disque de `bounds`.
  static func arcRadius(in bounds: CGRect) -> CGFloat {
    min(bounds.width, bounds.height) / 2 - tickOuterInset - tickLength - arcSpacing - arcWidth / 2
  }

  /// Chemin du bandeau : l'arc complet de la course, que `strokeEnd` vient ensuite rogner au
  /// niveau courant.
  static func arcPath(in bounds: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.addArc(
      center: CGPoint(x: bounds.midX, y: bounds.midY),
      radius: arcRadius(in: bounds),
      startAngle: startAngle,
      endAngle: startAngle - sweep,
      clockwise: true
    )
    return path
  }
}
