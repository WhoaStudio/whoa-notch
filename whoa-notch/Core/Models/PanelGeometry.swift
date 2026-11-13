import AppKit

/// Géométrie commune aux panneaux de l'overlay — les bandes accrochées à un bord vertical
/// (`SidePanelGeometry` à droite, le widget de luminosité à gauche) et le panneau de l'encoche
/// (`NotchPanelGeometry`). Les placements n'ont ni le même bord d'accroche ni la même
/// silhouette, mais ils doivent se lire comme plusieurs états d'une même surface : même rayon,
/// mêmes marges, même filet. Ces valeurs sont donc définies ici une fois, et chaque géométrie
/// s'y rapporte au lieu de les redire.
enum PanelGeometry {

  /// Rayon de la silhouette, convexe comme concave : c'est lui qui décide des marges, puisque
  /// les raccords rognent la zone peinte près du bord d'accroche.
  static let cornerRadius: CGFloat = 28

  /// Marges intérieures, décrites comme la silhouette elle-même : dans le repère du bord
  /// d'accroche, et non dans celui de l'écran. C'est ce qui les rend justes aux trois
  /// accroches — ce que les raccords rognent se déduit du bord auquel le panneau est suspendu,
  /// pas d'une horizontale ou d'une verticale.
  ///
  /// **Le long** du bord d'accroche, la marge vaut au moins le rayon : les deux raccords
  /// concaves y rentrent la silhouette de `cornerRadius` de chaque côté, et tout contenu posé
  /// en deçà sortirait du chemin. C'est le haut et le bas d'une bande de flanc — et la gauche
  /// et la droite du panneau de l'encoche, suspendu au bord du haut.
  static let contentInsetAlongAnchor: CGFloat = cornerRadius + 6

  /// **En profondeur** depuis le bord d'accroche, la silhouette est pleine : il suffit de ne
  /// pas coller le contenu au bord peint.
  static let contentInsetAcrossAnchor: CGFloat = 14

  /// Écart entre deux blocs empilés dans le corps d'un panneau.
  static let contentSpacing: CGFloat = 14

  /// Épaisseur du filet tracé sur la frontière de la silhouette.
  static let strokeWidth: CGFloat = 1

  // MARK: - Cadre des bandes de bord

  /// Largeur d'une bande accrochée à un bord vertical : celle du panneau latéral, qui serre
  /// sa pile de bagues (`SidePanelGeometry.ringTileSize`) au plus près. Une bande ne porte
  /// qu'une colonne de contenu — l'élargir ne ferait que voiler l'écran derrière elle.
  static let panelWidth: CGFloat = 96

  /// Hauteur plancher, pour qu'une bande garde une silhouette posée même quand son contenu
  /// tient en moins. C'est aussi la hauteur de celles qui n'ont pas de contenu à mesurer.
  static let minimumPanelHeight: CGFloat = 300

  /// Marge conservée avec le haut et le bas de la zone visible, pour qu'une bande trop haute
  /// pour l'écran ne soit soudée ni à la barre de menus ni au bas de l'écran.
  static let screenInset: CGFloat = 8

  /// Largeur de la bande de luminosité : la barre de graduations et ses deux marges, rien de
  /// plus. Le soleil, lui, vit hors de la bande, dans la marge transparente que lui laisse
  /// `brightnessPanelWidth`.
  static let brightnessBandWidth: CGFloat = contentInsetAcrossAnchor * 2 + brightnessBarWidth

  /// Largeur de la barre de graduations — tout ce que la bande a à contenir.
  static let brightnessBarWidth: CGFloat = 40

  /// Côté de la bulle posée à côté de la bande — le soleil au repos, la valeur pendant le
  /// réglage.
  static let brightnessBubbleSize: CGFloat = 44

  /// Écart entre le bord peint de la bande et cette bulle.
  static let brightnessBubbleSpacing: CGFloat = 12

  /// Largeur du cadre du widget de luminosité : la bande, puis la marge transparente où la
  /// bulle se pose. Le cadre serre les deux au plus près — ce qui dépasse ne serait qu'une
  /// zone invisible qui retiendrait le widget ouvert sous un curseur déjà parti.
  static let brightnessPanelWidth: CGFloat =
    brightnessBandWidth + brightnessBubbleSpacing + brightnessBubbleSize

  /// Part d'un cadre de bande réellement peinte par le widget de luminosité : la moitié
  /// accrochée au bord configuré. Décrite sur un `CGRect` quelconque, donc valable aussi bien
  /// dans le repère d'une vue que dans celui de l'écran — c'est le même découpage, qu'on
  /// dessine la silhouette ou qu'on demande si le curseur est encore dessus.
  static func brightnessBand(in frame: CGRect, anchoredTo edge: EdgePosition) -> CGRect {
    CGRect(
      x: edge == .right ? frame.maxX - brightnessBandWidth : frame.minX,
      y: frame.minY,
      width: min(brightnessBandWidth, frame.width),
      height: frame.height
    )
  }

  /// Cadre affleurant le bord demandé, en coordonnées globales AppKit : c'est depuis ce bord
  /// que le contenu glisse, donc la bande doit y toucher — l'espacement visuel vient des coins
  /// arrondis, pas d'une marge.
  ///
  /// La bande est **centrée verticalement** sur la zone visible de l'écran, au milieu de son
  /// bord : c'est là que la zone sensible va la chercher (`hotZone(on:anchoredTo:)`), et les
  /// deux doivent se répondre — une bande posée ailleurs sur le bord s'ouvrirait loin du
  /// curseur qui l'a appelée. Une bande plus haute que l'écran est ramenée à la zone visible,
  /// marges comprises.
  ///
  /// Deux bandes posées sur les deux bords du même écran partagent donc cadre et hauteur : ce
  /// sont bien deux images l'une de l'autre.
  static func panelFrame(
    on screen: NSScreen,
    anchoredTo edge: EdgePosition,
    height: CGFloat = minimumPanelHeight,
    width: CGFloat = panelWidth
  ) -> NSRect {
    let visible = screen.visibleFrame
    let available = max(0, visible.height - 2 * screenInset)
    let clamped = min(height, available)
    let x = edge == .right ? screen.frame.maxX - width : screen.frame.minX
    return NSRect(x: x, y: visible.midY - clamped / 2, width: width, height: clamped)
  }

  // MARK: - Poignée repliée

  /// Poignée à laquelle un panneau se replie : la silhouette réduite qu'il garde sur son bord
  /// d'accroche — ou, quand il n'y reste pas, celle depuis laquelle il se déplie. Décrite dans
  /// le repère du bord (`width` le long de celui-ci, `height` en profondeur), donc la même pour
  /// les trois accroches : la pastille du panneau de l'encoche est celle d'une bande de flanc
  /// couchée.
  static let collapsedHandleSize = CGSize(width: 160, height: 22)

  /// Rayons de cette poignée. Ils lui sont propres et ne valent pas ceux du panneau déplié :
  /// elle est trop basse pour porter `cornerRadius`, qui l'arrondirait jusqu'à la gommer.
  static let collapsedShoulderRadius: CGFloat = 7
  static let collapsedFarRadius: CGFloat = 10

  // MARK: - Zone sensible

  /// Zone sensible d'une bande : 100 pt de haut sur 20 pt de large, centrée sur le milieu de
  /// son bord d'accroche — donc sur le milieu de la bande qu'elle ouvre, puisque `panelFrame`
  /// y centre le cadre. On va chercher la bande là où elle vit : ailleurs sur le bord, elle
  /// s'ouvrirait loin du curseur qui l'a appelée.
  ///
  /// Le milieu est celui de la **zone visible**, comme pour le cadre, et non celui de l'écran :
  /// la barre de menus décale l'un par rapport à l'autre.
  static let hotZoneWidth: CGFloat = 20
  static let hotZoneHeight: CGFloat = 100

  static func hotZone(on screen: NSScreen, anchoredTo edge: EdgePosition) -> NSRect {
    return NSRect(
      x: edge == .right ? screen.frame.maxX - hotZoneWidth : screen.frame.minX,
      y: screen.visibleFrame.midY - hotZoneHeight / 2,
      width: hotZoneWidth,
      height: hotZoneHeight
    )
  }

  // MARK: - Silhouette

  /// Bord auquel une silhouette est suspendue. Les panneaux de l'overlay s'accrochent tous à
  /// un bord d'écran, mais pas au même : les bandes à un flanc, le panneau de l'encoche au haut.
  enum Anchor {
    case top
    case left
    case right

    init(_ edge: EdgePosition) {
      self = edge == .right ? .right : .left
    }

    /// Étendue de `rect` dans le repère du bord : `width` le long du bord d'accroche,
    /// `height` en profondeur depuis celui-ci.
    fileprivate func stackSize(of rect: CGRect) -> CGSize {
      switch self {
      case .top: CGSize(width: rect.width, height: rect.height)
      case .left, .right: CGSize(width: rect.height, height: rect.width)
      }
    }

    /// Transformation qui rapporte le repère du bord — origine au départ du bord d'accroche,
    /// `+x` le long de celui-ci, `-y` en profondeur — à celui de `rect`, en centrant la
    /// silhouette sur le bord. C'est tout ce qui distingue les trois accroches.
    fileprivate func placement(in rect: CGRect, along: CGFloat) -> CGAffineTransform {
      switch self {
      case .top:
        CGAffineTransform(translationX: rect.midX - along / 2, y: rect.maxY)
      case .right:
        CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.maxX, ty: rect.midY + along / 2)
      case .left:
        CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: rect.minX, ty: rect.midY + along / 2)
      }
    }
  }

  /// Silhouette d'un panneau suspendu à `anchor`, en un seul chemin fermé : deux raccords
  /// **concaves** là où il rejoint son bord d'accroche, qui l'y évasent comme un onglet de
  /// navigateur s'évase dans sa barre, et deux coins **convexes** du côté opposé. Les arcs
  /// concaves sont décrits avec `addArc(center:radius:startAngle:endAngle:clockwise:)` et non
  /// avec la variante `tangent1End:tangent2End:`, qui ne sait produire que des coins convexes.
  ///
  /// Le chemin est tracé une fois dans un repère indépendant du bord — le long du bord
  /// d'accroche, puis en profondeur depuis celui-ci — et c'est `Anchor.placement(in:along:)`
  /// qui le rapporte au repère de la vue. Les trois accroches partagent donc une seule
  /// recette : une silhouette de flanc est celle du haut couchée, et non un second tracé que
  /// rien n'empêcherait de diverger.
  ///
  /// `size` décrit la silhouette dans ce repère — `width` le long du bord, `height` en
  /// profondeur — et la centre sur le bord ; `nil` lui donne tout `rect`. Deux tailles
  /// différentes produisent le même nombre de segments, dans le même ordre : Core Animation sait
  /// donc interpoler l'une vers l'autre, et c'est ce qui rend un dépliage animable.
  ///
  /// Tout est dans le même `CGPath` : aucune couture entre le corps et les raccords, et tout ce
  /// qui est hors du chemin reste non peint, donc réellement transparent.
  static func silhouette(
    in rect: CGRect,
    anchoredTo anchor: Anchor,
    size: CGSize? = nil,
    shoulderRadius: CGFloat = cornerRadius,
    farRadius: CGFloat = cornerRadius
  ) -> CGPath {
    let available = anchor.stackSize(of: rect)
    let requested = size ?? available
    let along = min(requested.width, available.width)
    let across = min(requested.height, available.height)

    // Les quatre rayons doivent tenir dans la silhouette, qui est minuscule quand un panneau
    // se replie jusqu'à sa poignée.
    let shoulder = min(shoulderRadius, along / 4, across / 2)
    let far = min(farRadius, along / 2 - shoulder, across - shoulder)

    let path = stackSilhouette(along: along, across: across, shoulder: shoulder, far: far)
    var placement = anchor.placement(in: rect, along: along)
    return path.copy(using: &placement) ?? path
  }

  /// Pastille flottante : même séquence de segments que `silhouette` (départ, arc, flanc, arc,
  /// fond, arc, flanc, arc, fermeture), donc interpolable avec elle, mais détachée du bord du
  /// haut — décalée de `topGap` vers le bas, et arrondie sur ses quatre coins.
  static func islandSilhouette(
    in rect: CGRect,
    size: CGSize,
    topGap: CGFloat,
    cornerRadius: CGFloat = .infinity,
    bottomCornerRadius: CGFloat? = nil
  ) -> CGPath {
    let along = min(size.width, rect.width)
    let across = min(size.height, rect.height - topGap)
    let full = min(across, along) / 2
    let rt = min(cornerRadius, full)
    let rb = min(bottomCornerRadius ?? cornerRadius, full)
    let top = -topGap
    let bottom = top - across
    let left = rect.midX - along / 2
    let right = left + along

    let path = CGMutablePath()
    path.move(to: CGPoint(x: left + rt, y: rect.maxY + top))
    path.addArc(
      center: CGPoint(x: left + rt, y: rect.maxY + top - rt), radius: rt,
      startAngle: .pi / 2, endAngle: .pi, clockwise: false)
    path.addLine(to: CGPoint(x: left, y: rect.maxY + bottom + rb))
    path.addArc(
      center: CGPoint(x: left + rb, y: rect.maxY + bottom + rb), radius: rb,
      startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
    path.addLine(to: CGPoint(x: right - rb, y: rect.maxY + bottom))
    path.addArc(
      center: CGPoint(x: right - rb, y: rect.maxY + bottom + rb), radius: rb,
      startAngle: -.pi / 2, endAngle: 0, clockwise: false)
    path.addLine(to: CGPoint(x: right, y: rect.maxY + top - rt))
    path.addArc(
      center: CGPoint(x: right - rt, y: rect.maxY + top - rt), radius: rt,
      startAngle: 0, endAngle: .pi / 2, clockwise: false)
    path.closeSubpath()
    return path
  }

  /// La recette, dans le repère du bord : le bord d'accroche est la ligne `y = 0`, et la
  /// silhouette s'enfonce vers les `y` négatifs sur `across` de profondeur.
  private static func stackSilhouette(
    along: CGFloat,
    across: CGFloat,
    shoulder r: CGFloat,
    far b: CGFloat
  ) -> CGPath {
    let depth = -across
    let path = CGMutablePath()

    // Premier évasement concave depuis le bord d'accroche. Le centre est posé **sur** ce
    // bord, décalé en profondeur de la hauteur du rayon : c'est ce qui rend l'arc tangent au
    // bord d'un côté et au flanc de l'autre — centré sur le coin, il rejoindrait les deux à
    // l'équerre et laisserait une marche.
    path.move(to: CGPoint(x: 0, y: 0))
    path.addArc(
      center: CGPoint(x: 0, y: -r),
      radius: r,
      startAngle: .pi / 2,
      endAngle: 0,
      clockwise: true
    )

    // Premier flanc, puis coin convexe du côté opposé au bord.
    path.addLine(to: CGPoint(x: r, y: depth + b))
    path.addArc(
      center: CGPoint(x: r + b, y: depth + b),
      radius: b,
      startAngle: .pi,
      endAngle: 3 * .pi / 2,
      clockwise: false
    )

    // Fond de la silhouette, puis second coin convexe.
    path.addLine(to: CGPoint(x: along - r - b, y: depth))
    path.addArc(
      center: CGPoint(x: along - r - b, y: depth + b),
      radius: b,
      startAngle: -.pi / 2,
      endAngle: 0,
      clockwise: false
    )

    // Second flanc, puis évasement concave symétrique du premier.
    path.addLine(to: CGPoint(x: along - r, y: -r))
    path.addArc(
      center: CGPoint(x: along, y: -r),
      radius: r,
      startAngle: .pi,
      endAngle: .pi / 2,
      clockwise: true
    )

    // Le bord d'accroche referme la silhouette : c'est par lui que le panneau tient à l'écran.
    path.closeSubpath()
    return path
  }
}
