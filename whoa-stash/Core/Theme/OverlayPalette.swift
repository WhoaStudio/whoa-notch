import AppKit

/// Jeu de couleurs et de matériaux de l'overlay. L'app est sombre et ne l'est que : il n'y a
/// qu'une palette, `base`, sur laquelle les réglages viennent se poser.
struct OverlayPalette {
  var activeTickColor: CGColor
  var inactiveTickColor: CGColor
  var glowOpacity: Float
  var glowRadius: CGFloat

  /// Matériau translucide et sa teinte. Plus personne ne s'en sert depuis que le widget de
  /// luminosité est passé au fond plein : gardés pour un éventuel retour au translucide.
  var backgroundMaterial: NSVisualEffectView.Material
  var backgroundTint: CGColor
  /// Fond opaque de toutes les surfaces de l'overlay : panneau latéral, panneau de l'encoche,
  /// pilule et bouton du widget de luminosité.
  var panelBackground: CGColor
  var strokeColor: CGColor

  /// Fond de la capsule de navigation, posée sous le panneau de l'encoche et détachée de lui.
  /// Translucide : elle flotte au-dessus du bureau, elle n'est pas un morceau de la silhouette.
  var tabCapsuleFill: CGColor

  /// Cercle de l'onglet actif dans la capsule. Franchement plus clair que la capsule qui le
  /// porte — c'est la seule chose qui désigne l'onglet choisi, les glyphes étant tous de la
  /// même taille. Distinct de `tabPillFill`, qui est la même marque posée sur le **panneau**,
  /// bien plus sombre : la même teinte aux deux endroits serait invisible à l'un ou criarde à
  /// l'autre.
  var tabCircleFill: CGColor

  var buttonSymbolColor: NSColor
  var buttonGlowColor: CGColor

  /// Pastille de l'onglet actif dans la barre du panneau, et les deux teintes de son contenu.
  /// L'onglet actif est franc sur sa pastille ; les autres restent en retrait, sans pastille.
  var tabPillFill: CGColor
  /// Teinte du glyphe posé **sur** la pastille. Distincte de `tabActiveContent`, qui est celle
  /// d'un contenu franc posé à même la capsule.
  var tabPillContent: NSColor
  var tabActiveContent: NSColor
  var tabInactiveContent: NSColor

  // MARK: - Calendrier

  /// Rouge du widget calendrier : le numéro de semaine et le mois de l'en-tête, et la pastille
  /// du jour courant. C'est la seule teinte franche du panneau — tout le reste y est blanc,
  /// gris ou emprunté au calendrier porteur d'un événement —, et c'est ce qui fait du jour
  /// courant le point d'accroche des deux surfaces qui le portent, la bande de la semaine et
  /// la grille du mois.
  var calendarAccent: NSColor
  var calendarTodayFill: CGColor

  /// Les deux teintes des jours qui ne sont pas aujourd'hui, dans la bande de la semaine comme
  /// dans la grille du mois. La semaine ouvrée se lit franchement ; le week-end reste en
  /// retrait, et c'est ce seul écart de gris qui le désigne — aucune des deux vues ne le
  /// marque autrement.
  var calendarDayContent: NSColor
  var calendarWeekendContent: NSColor

  /// Accent et translucidité choisis dans les Préférences, poussés ici par
  /// `OverlayPaletteSettings`. Ils vivent sur le type plutôt que d'être passés en argument
  /// parce que toutes les vues de l'overlay appellent déjà `resolved(for:)` sans rien savoir
  /// des réglages : les y faire atterrir évite de tordre chaque `applyPalette()`.
  @MainActor static var accent: AccentColor = GeneralSettings().accentColor
  @MainActor static var panelOpacity: Double = GeneralSettings().panelOpacity

  /// Postée quand `accent` ou `panelOpacity` change. Les vues qui se repeignent déjà sur
  /// `viewDidChangeEffectiveAppearance` s'y abonnent pour la même raison.
  static let didChangeNotification = Notification.Name("whoa-stash.overlayPaletteDidChange")

  /// L'apparence reste un argument : `AccentColor.system` est une couleur dynamique, dont le
  /// `cgColor` ne se lit que dans une apparence de dessin posée explicitement.
  @MainActor
  static func resolved(for appearance: NSAppearance) -> OverlayPalette {
    base
      .accented(with: accent, in: appearance)
      .fadingPanel(to: panelOpacity)
  }

  /// Vert d'accent de l'overlay. Partagé hors de la palette — le panneau de l'encoche
  /// s'en sert pour marquer la bague survolée — d'où sa visibilité interne.
  static let activeGreen = CGColor(red: 0x00 / 255, green: 0xFF / 255, blue: 0x00 / 255, alpha: 1)

  /// La palette brute, sans les réglages. Les tests s'en servent pour vérifier les
  /// transformations une par une.
  static let base = OverlayPalette(
    activeTickColor: activeGreen,
    inactiveTickColor: CGColor(gray: 0.55, alpha: 0.55),
    glowOpacity: 0.85,
    glowRadius: 4,
    backgroundMaterial: .hudWindow,
    backgroundTint: CGColor(gray: 0, alpha: 0.35),
    panelBackground: CGColor(gray: 0.04, alpha: 1),
    strokeColor: CGColor(gray: 1, alpha: 0.08),
    tabCapsuleFill: CGColor(gray: 0.12, alpha: 0.80),
    tabCircleFill: CGColor(gray: 0.42, alpha: 1),
    buttonSymbolColor: .white,
    buttonGlowColor: CGColor(gray: 1, alpha: 0.5),
    tabPillFill: CGColor(gray: 0.22, alpha: 1),
    tabPillContent: .white,
    tabActiveContent: .white,
    tabInactiveContent: NSColor(white: 0.62, alpha: 1),
    calendarAccent: calendarRed,
    calendarTodayFill: calendarRed.cgColor,
    calendarDayContent: NSColor(white: 0.93, alpha: 1),
    calendarWeekendContent: NSColor(white: 0.44, alpha: 1)
  )

  /// Le rouge du calendrier, à la source : `calendarAccent` et `calendarTodayFill` sont la même
  /// teinte sous deux formes, l'une pour le texte, l'autre pour une couche.
  static let calendarRed = NSColor(
    srgbRed: 0xEB / 255, green: 0x53 / 255, blue: 0x4C / 255, alpha: 1)

  // MARK: - Teintes d'un événement

  /// Ce qu'une ligne d'agenda fait de la couleur du calendrier porteur. Elle est trop sombre
  /// pour s'écrire telle quelle sur le fond du panneau : le titre la relève d'une part de
  /// blanc, et l'heure reprend ce titre assombri. Les deux se déduisent donc d'une seule
  /// couleur, celle de la barre d'accent — c'est ce qui fait tenir ensemble les trois marques
  /// d'une même ligne, quel que soit le calendrier d'où elle sort.
  static let agendaTitleLift: CGFloat = 0.25
  static let agendaTimeDimming: CGFloat = 0.72

  static func agendaTitleColor(for color: NSColor) -> NSColor {
    guard let base = color.usingColorSpace(.sRGB) else { return color }
    let lift: (CGFloat) -> CGFloat = { $0 + (1 - $0) * agendaTitleLift }
    return NSColor(
      srgbRed: lift(base.redComponent),
      green: lift(base.greenComponent),
      blue: lift(base.blueComponent),
      alpha: 1
    )
  }

  static func agendaTimeColor(for color: NSColor) -> NSColor {
    guard let title = agendaTitleColor(for: color).usingColorSpace(.sRGB) else { return color }
    return NSColor(
      srgbRed: title.redComponent * agendaTimeDimming,
      green: title.greenComponent * agendaTimeDimming,
      blue: title.blueComponent * agendaTimeDimming,
      alpha: 1
    )
  }
}

extension OverlayPalette {
  /// Applique le multiplicateur `Brightness > Glow intensity` des Préférences à une palette
  /// déjà résolue pour l'apparence courante.
  func scalingGlow(by intensity: Double) -> OverlayPalette {
    var palette = self
    palette.glowOpacity = Float(min(1, max(0, Double(glowOpacity) * intensity)))
    palette.glowRadius = glowRadius * CGFloat(intensity)
    return palette
  }

  /// Substitue la teinte d'accent choisie au vert historique — graduations actives du widget
  /// de luminosité, et plaque derrière la bague survolée du panneau de l'encoche.
  func accented(with accent: AccentColor, in appearance: NSAppearance) -> OverlayPalette {
    var palette = self
    palette.activeTickColor = accent.cgColor(for: appearance)
    return palette
  }

  /// Rend le fond des panneaux translucide. Les fenêtres sont déjà `isOpaque = false` et
  /// `backgroundColor = .clear`, donc abaisser l'alpha du fond peint laisse réellement voir
  /// à travers ; le filet et le contenu gardent le leur, sinon la silhouette se dissoudrait.
  func fadingPanel(to opacity: Double) -> OverlayPalette {
    guard opacity < 1 else { return self }
    var palette = self
    let clamped = max(0.2, min(1, opacity))
    palette.panelBackground = panelBackground.copy(alpha: CGFloat(clamped)) ?? panelBackground
    return palette
  }
}
