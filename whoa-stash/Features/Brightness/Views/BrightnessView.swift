import AppKit

/// Vue racine de l'overlay : une bande accrochée à un bord de l'écran, de la même matière que
/// le panneau latéral — même hauteur, même silhouette évasée dans le bord, même fond plein et
/// même filet (`PanelGeometry`). Elle est bien plus étroite que lui : elle ne
/// porte que la barre de graduations, et le reste du cadre, laissé transparent, sert de marge
/// où le soleil se pose hors de la bande.
///
/// Assemble `BrightnessBarView` dans la boîte de contenu de la bande et `SunButtonView` à côté
/// d'elle, pilote son dépliage et retranscrit le thème effectif (clair/sombre) vers ses enfants à chaque
/// changement d'apparence.
///
/// Elle se déplie depuis son bord comme la bande de bagues et le panneau de l'encoche, du même
/// geste et par le même moteur (`PanelFold`) : rien ne se déplace, c'est la silhouette qui passe
/// de la poignée à la bande entière. Comme la bande de bagues — et contrairement à l'encoche,
/// qui reste à l'écran repliée — elle s'efface tout entière, puisque rien ne doit rester sur le
/// bord entre deux survols.
final class BrightnessView: NSView {

  let barView: BrightnessBarView
  /// Posé hors de la bande, donc hors du masque de dépliage : il est fils de la vue racine
  /// et non du conteneur de contenu, que la silhouette découpe.
  let sunButton: SunButtonView

  /// Le scroll trackpad n'est exposé nulle part au niveau fenêtre par AppKit :
  /// on le capte directement ici, sur la vue qui reçoit réellement l'événement.
  var onScroll: ((CGFloat) -> Void)?

  /// Bord d'accroche de la bande, relayé par `BrightnessOverlayController` depuis les
  /// Préférences : c'est lui qui décide de quel côté la silhouette s'évase.
  var edge: EdgePosition = .left {
    didSet {
      guard edge != oldValue else { return }
      needsLayout = true
    }
  }

  private let backgroundLayer = CAShapeLayer()
  private let strokeLayer = CAShapeLayer()
  private let contentMask = CAShapeLayer()

  /// La barre et le soleil vivent dans un conteneur à part pour n'avoir qu'un masque à piloter
  /// pendant le dépliage. Masquer le calque de la vue elle-même rognerait aussi le filet, qui
  /// est tracé centré sur la frontière et y perdrait la moitié de son épaisseur.
  private let contentContainer = NSView()

  private(set) var isExpanded = false

  /// Part du cadre que la bande peint réellement : le reste sert de marge à la bulle.
  private var bandRect: CGRect {
    PanelGeometry.brightnessBand(in: bounds, anchoredTo: edge)
  }

  private let barWidth = PanelGeometry.brightnessBarWidth
  private let buttonSize = PanelGeometry.brightnessBubbleSize

  /// Écart entre le bord peint de la bande et le soleil : assez pour qu'il se lise comme posé
  /// à côté, et non comme un morceau de la bande.
  private let buttonSpacing = PanelGeometry.brightnessBubbleSpacing

  // Même remarque que dans BrightnessBarView : NSView (addSubview) et CALayer (addSublayer)
  // mélangés comme frères n'ont pas d'ordre garanti. zPosition fige le stacking.
  private enum Depth {
    static let background: CGFloat = -2
    static let stroke: CGFloat = -1
  }

  init(tickCount: Int, initialPalette: OverlayPalette) {
    barView = BrightnessBarView(tickCount: tickCount, palette: initialPalette)
    sunButton = SunButtonView(palette: initialPalette)
    super.init(frame: .zero)
    wantsLayer = true
    setUp(palette: initialPalette)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp(palette: OverlayPalette) {
    // Clic droit : le menu partagé par tous les panneaux de l'overlay. Posé ici plutôt que
    // sur chaque enfant — AppKit remonte la chaîne des responders jusqu'à la première vue
    // qui porte un menu.
    menu = OverlayContextMenu.shared.menu

    // Fond plein plutôt qu'un `NSVisualEffectView`, comme le panneau latéral : le matériau
    // laissait remonter le fond d'écran et délavait la surface en gris.
    backgroundLayer.zPosition = Depth.background
    layer?.addSublayer(backgroundLayer)

    strokeLayer.fillColor = nil
    strokeLayer.lineWidth = PanelGeometry.strokeWidth
    strokeLayer.zPosition = Depth.stroke
    layer?.addSublayer(strokeLayer)

    contentContainer.wantsLayer = true
    // Le contenu est découpé par la silhouette elle-même : pendant le dépliage il ne doit
    // rien dépasser de la forme, qui est encore plus étroite que lui.
    contentContainer.layer?.mask = contentMask
    addSubview(contentContainer)

    contentContainer.addSubview(barView)

    addSubview(sunButton)

    applyPalette(palette)

  }

  override func layout() {
    super.layout()

    // La silhouette est reposée dans l'état courant : la mise en page suit un changement de
    // bord, de taille ou d'écran, qui ne doit ni rejouer le dépliage ni laisser le chemin au
    // cadre précédent. Le fond et le filet reçoivent exactement le même chemin, tracé centré
    // sur la frontière — voir `SidePanelContentView` pour pourquoi aucun `insetBy` n'est
    // appliqué ici.
    applyExpandedShape()

    contentContainer.frame = bounds

    // Boîte de contenu : tout ce qui est peint reste à l'intérieur de la ligne où le bord
    // se relève vers le bord de l'écran pour former l'évasement. Elle est prise sur la
    // bande, pas sur le cadre : la moitié qui reste transparente n'accueille rien.
    let box = bandRect.insetBy(
      dx: PanelGeometry.contentInsetAcrossAnchor,
      dy: PanelGeometry.contentInsetAlongAnchor
    )

    // La barre tient seule dans la bande, centrée dans la boîte : la coller à un bord la
    // ferait flotter de travers.
    barView.frame = NSRect(
      x: box.midX - barWidth / 2,
      y: box.minY,
      width: barWidth,
      height: box.height
    )

    // Le soleil se pose hors de la bande, du côté opposé au bord d'accroche, et reste
    // centré en hauteur sur elle : c'est là, et non dans la bande, que la valeur se lit
    // pendant le réglage, à la place de l'icône.
    let buttonX =
      edge == .right
      ? bandRect.minX - buttonSpacing - buttonSize
      : bandRect.maxX + buttonSpacing
    sunButton.frame = NSRect(
      x: buttonX,
      y: bandRect.midY - buttonSize / 2,
      width: buttonSize,
      height: buttonSize
    )
  }

  // MARK: - Dépliage

  private var revealOffset: CGFloat {
    edge == .right ? bounds.width : -bounds.width
  }

  private func applyExpandedShape() {
    guard bounds.width > 0, bounds.height > 0 else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for shape in [backgroundLayer, strokeLayer, contentMask] {
      shape.frame = bounds
      shape.path = expandedPath()
    }
    CATransaction.commit()
  }

  /// Les deux états, tirés de la même recette que les autres panneaux de l'overlay
  /// (`PanelGeometry.silhouette`), ici suspendue au bord configuré. Seuls la taille et les
  /// rayons les distinguent, donc les deux chemins ont le même nombre de segments dans le même
  /// ordre — c'est cette identité de structure qui rend le dépliage animable d'un seul
  /// `CASpringAnimation` sur `path`.

  private func collapsedPath() -> CGPath {
    PanelGeometry.silhouette(
      in: bandRect,
      anchoredTo: PanelGeometry.Anchor(edge),
      size: PanelGeometry.collapsedHandleSize,
      shoulderRadius: PanelGeometry.collapsedShoulderRadius,
      farRadius: PanelGeometry.collapsedFarRadius
    )
  }

  private func expandedPath() -> CGPath {
    PanelGeometry.silhouette(in: bandRect, anchoredTo: PanelGeometry.Anchor(edge))
  }

  /// Replie la bande sans animation et l'efface — à appeler avant d'afficher la fenêtre, pour
  /// que la première image montrée soit déjà le début du dépliage et non la bande en place.
  func prepareForReveal() {
    isExpanded = false
    // La mise en page est vidée tout de suite : sans cela la silhouette repliée serait posée
    // dans la même transaction que le dépliage, qui partirait alors du chemin précédent.
    layoutSubtreeIfNeeded()
    applyExpandedShape()
    layer?.setValue(revealOffset, forKeyPath: "transform.translation.x")
  }

  /// Déplie ou replie la bande. `completion` est appelée une fois le ressort stabilisé, pour
  /// que le contrôleur puisse retirer la fenêtre.
  func setVisible(_ visible: Bool, completion: (() -> Void)? = nil) {
    guard visible != isExpanded else {
      completion?()
      return
    }
    isExpanded = visible
    guard let layer else {
      completion?()
      return
    }

    layer.springAnimate(
      keyPath: "transform.translation.x",
      to: visible ? CGFloat(0) : revealOffset,
      preset: .gentle,
      completion: completion
    )
  }

  private func applyShape(expanded: Bool, animated: Bool, completion: (() -> Void)? = nil) {
    guard bounds.width > 0, bounds.height > 0 else {
      completion?()
      return
    }

    // C'est tout le calque de la vue qui s'efface, filet et fond compris, et son fondu suit
    // le ressort du dépliage (`dissolving`) : sur un fondu court, la bande aurait disparu
    // avant d'avoir fini de se replier et le geste passerait inaperçu.
    PanelFold.apply(
      path: expanded ? expandedPath() : collapsedPath(),
      to: [backgroundLayer, strokeLayer, contentMask],
      in: bounds,
      dissolving: layer.map { [$0] } ?? [],
      to: expanded ? 1 : 0,
      animated: animated,
      completion: completion
    )
  }

  func updateBrightness(activeTickCount: Int, animated: Bool) {
    barView.setActiveTickCount(activeTickCount, animated: animated)
  }

  func showPercent(_ percent: Int) {
    sunButton.showPercent(percent)
  }

  func applyPalette(_ palette: OverlayPalette) {
    backgroundLayer.fillColor = palette.panelBackground
    strokeLayer.strokeColor = palette.strokeColor
    barView.apply(palette: palette)
    sunButton.apply(palette: palette)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette(OverlayPalette.resolved(for: effectiveAppearance))
  }

  override func scrollWheel(with event: NSEvent) {
    onScroll?(event.scrollingDeltaY)
  }

  /// Hors de la bande et du soleil, la fenêtre est transparente : elle ne doit ni capter les
  /// clics ni recevoir le scroll, sinon le vide entre les deux réglerait la luminosité et
  /// masquerait ce qu'il y a dessous.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    guard bandRect.contains(local) || sunButton.frame.contains(local) else { return nil }
    return super.hitTest(point)
  }
}
