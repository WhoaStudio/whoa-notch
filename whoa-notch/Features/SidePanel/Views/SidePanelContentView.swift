import AppKit

/// Contenu du panneau latéral : une surface quasi opaque accrochée à un bord vertical de l'écran,
/// arrondie du côté intérieur et évasée dans le bord.
///
/// Porte les bagues d'utilisation (`SidePanelStackView`). La carte détaillée d'une bague, elle,
/// vit dans la bulle qui s'ouvre à son survol (`UsageCalloutWindow`).
///
/// Ni onglets ni semaine ici : ils appartiennent au panneau de l'encoche. La bande n'est à l'écran
/// que le temps d'un survol, raison pour laquelle une rangée d'onglets y serait peu atteignable.
/// Le seul clic qu'elle sert est le clic droit, qui ouvre le menu partagé de l'overlay
/// (`OverlayContextMenu`).
///
/// Porte aussi le dépliage : la bande se déplie depuis son bord comme le panneau de l'encoche se
/// déplie depuis le haut de l'écran, du même geste et par le même moteur (`PanelFold`). Rien ne
/// se déplace — ni la fenêtre, ni le cadre de la vue —, c'est la silhouette qui passe de la
/// poignée au panneau entier. Une seule chose la distingue de l'encoche : celle-ci garde sa
/// silhouette repliée à l'écran, alors que la bande s'efface entièrement, puisque rien ne doit
/// rester sur le bord entre deux survols.
///
/// Mise en page entièrement en frames, comme le reste de l'overlay (`BrightnessBarView`) —
/// pas de contraintes Auto Layout.
final class SidePanelContentView: NSView {

  private let backgroundLayer = CAShapeLayer()
  private let strokeLayer = CAShapeLayer()
  private let contentMask = CAShapeLayer()

  /// Le contenu vit dans un conteneur à part pour n'avoir qu'un masque à piloter pendant le
  /// dépliage. Masquer le calque de la vue lui-même rognerait aussi le filet, qui est tracé
  /// centré sur la frontière et y perdrait la moitié de son épaisseur.
  private let contentContainer = NSView()
  private let stack = SidePanelStackView()

  /// Bord de l'écran auquel la bande est accrochée : c'est lui qui décide du côté où la
  /// silhouette s'évase, et donc du sens dans lequel elle se déplie.
  var anchorEdge: EdgePosition = .right {
    didSet {
      guard anchorEdge != oldValue else { return }
      needsLayout = true
    }
  }

  /// Rayon unique de toute la silhouette dépliée : il vaut à la fois pour les deux coins
  /// convexes (côté intérieur) et pour les deux raccords concaves qui évasent le panneau dans
  /// le bord de l'écran. À `largeur / 2`, les deux arcs se rejoignent tangentiellement sans
  /// segment droit entre eux — c'est la proportion de la référence.
  private let cornerRadius = SidePanelGeometry.panelCornerRadius

  private(set) var isExpanded = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    // Clic droit : le menu partagé par tous les panneaux de l'overlay. Posé ici plutôt que
    // sur chaque enfant — AppKit remonte la chaîne des responders jusqu'à la première vue
    // qui porte un menu.
    menu = OverlayContextMenu.shared.menu

    // Fond plein plutôt qu'un `NSVisualEffectView` : le matériau laissait remonter le fond
    // d'écran et délavait le panneau en gris, alors qu'il doit rester franchement sombre.
    layer?.addSublayer(backgroundLayer)

    strokeLayer.fillColor = nil
    strokeLayer.lineWidth = PanelGeometry.strokeWidth
    layer?.addSublayer(strokeLayer)

    contentContainer.wantsLayer = true
    // Le contenu est découpé par la silhouette elle-même : pendant le dépliage il ne doit
    // rien dépasser de la forme, qui est encore plus étroite que lui.
    contentContainer.layer?.mask = contentMask
    addSubview(contentContainer)

    contentContainer.addSubview(stack)

    // Aucune ombre portée : le panneau se détache par sa propre teinte et son filet, et la
    // fenêtre est elle aussi sans ombre (`SidePanelWindow`).
    layer?.masksToBounds = false

    applyPalette()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  private func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    backgroundLayer.fillColor = palette.panelBackground
    strokeLayer.strokeColor = palette.strokeColor
  }

  /// Relayé par `SidePanelWindow` depuis le modèle de vue partagé avec la bulle : les deux
  /// surfaces montrent toujours le même instantané.
  func apply(claudeState: ClaudeUsageState, copilotState: CopilotUsageState, animated: Bool) {
    stack.apply(claudeState: claudeState, copilotState: copilotState, animated: animated)
  }

  /// Met en avant la bague survolée — le contrôleur la désigne depuis la position du curseur.
  func setHighlightedRing(_ index: Int?) {
    stack.setHighlightedRing(index)
  }

  /// Cadre d'une bague dans le repère de cette vue : `SidePanelWindow` le convertit en
  /// coordonnées écran pour que la bulle sache où pointer.
  func ringFrame(at index: Int) -> NSRect? {
    guard let frame = stack.ringFrame(at: index) else { return nil }
    return stack.convert(frame, to: self)
  }

  var ringCount: Int { stack.ringCount }

  override func layout() {
    super.layout()

    // La silhouette est reposée dans l'état courant : la mise en page suit un changement de
    // cadre d'écran, qui ne doit ni rejouer le dépliage ni laisser le chemin au cadre
    // précédent.
    applyExpandedShape()

    contentContainer.frame = bounds

    // Boîte de contenu : tout ce qui est peint reste sous la ligne où le bord supérieur se
    // relève vers le bord de l'écran pour former l'évasement (voir `PanelGeometry.silhouette`).
    stack.frame = bounds.insetBy(
      dx: SidePanelGeometry.contentHorizontalInset,
      dy: SidePanelGeometry.contentVerticalInset
    )
  }

  // MARK: - Silhouette

  /// Les deux états, tirés de la même recette que le panneau de l'encoche
  /// (`PanelGeometry.silhouette`), ici suspendue à un **flanc**. Seuls la taille et les rayons
  /// les distinguent, donc les deux chemins ont le même nombre de segments dans le même ordre —
  /// c'est cette identité de structure qui rend le dépliage animable d'un seul
  /// `CASpringAnimation` sur `path`.

  private func collapsedPath() -> CGPath {
    PanelGeometry.silhouette(
      in: bounds,
      anchoredTo: PanelGeometry.Anchor(anchorEdge),
      size: SidePanelGeometry.collapsedSize,
      shoulderRadius: PanelGeometry.collapsedShoulderRadius,
      farRadius: PanelGeometry.collapsedFarRadius
    )
  }

  private func expandedPath() -> CGPath {
    PanelGeometry.silhouette(
      in: bounds,
      anchoredTo: PanelGeometry.Anchor(anchorEdge),
      shoulderRadius: cornerRadius,
      farRadius: cornerRadius
    )
  }

  // MARK: - Dépliage

  private var revealOffset: CGFloat {
    anchorEdge == .right ? bounds.width : -bounds.width
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

  /// Replie la bande sans animation et l'efface — à appeler avant d'afficher la fenêtre, pour
  /// que la première image montrée soit déjà le début du dépliage et non le panneau en place.
  func prepareForReveal() {
    isExpanded = false
    // La mise en page est vidée tout de suite : sans cela la silhouette repliée serait posée
    // dans la même transaction que le dépliage, qui partirait alors du chemin précédent.
    layoutSubtreeIfNeeded()
    applyExpandedShape()
    layer?.setValue(revealOffset, forKeyPath: "transform.translation.x")
  }

  /// Déplie ou replie la bande. `completion` est appelée une fois le ressort stabilisé, pour que
  /// la fenêtre puisse se retirer — contrairement au panneau de l'encoche, la bande ne laisse
  /// rien derrière elle.
  func setExpanded(_ expanded: Bool, animated: Bool = true, completion: (() -> Void)? = nil) {
    guard expanded != isExpanded else {
      completion?()
      return
    }
    isExpanded = expanded
    guard let layer else {
      completion?()
      return
    }

    let target = expanded ? CGFloat(0) : revealOffset
    guard animated else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.setValue(target, forKeyPath: "transform.translation.x")
      CATransaction.commit()
      completion?()
      return
    }

    layer.springAnimate(
      keyPath: "transform.translation.x",
      to: target,
      preset: .gentle,
      completion: completion
    )
  }

  private func applyShape(expanded: Bool, animated: Bool, completion: (() -> Void)? = nil) {
    guard bounds.width > 0, bounds.height > 0 else {
      completion?()
      return
    }

    // C'est tout le calque de la vue qui s'efface, filet et fond compris : la bande n'a pas
    // d'état replié visible, là où le panneau de l'encoche ne fait disparaître que son contenu
    // et garde sa silhouette à l'écran. D'où `dissolving` plutôt que `fading` — le fondu suit
    // le ressort du dépliage, sans quoi la bande se serait effacée avant d'avoir fini de se
    // replier et le geste passerait inaperçu.
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
}
