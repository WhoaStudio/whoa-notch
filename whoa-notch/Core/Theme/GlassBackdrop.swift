import AppKit

/// Fond en verre (Liquid Glass) d'un panneau de l'overlay, découpé par la silhouette du panneau.
///
/// `NSGlassEffectView` ne sait dessiner qu'un rectangle arrondi ; les panneaux ont une forme
/// propre (épaules de l'encoche, évasement dans le bord de l'écran) qui se déplie au ressort.
/// Le verre est donc masqué par `shapeMask`, qu'il suffit de confier à `PanelFold` avec les
/// autres silhouettes pour que le dépliage reste celui d'avant.
final class GlassBackdrop: NSGlassEffectView {

  /// Le dégradé noir → verre : une vue posée comme `contentView` du verre, donc dans l'effet
  /// lui-même (c'est le seul emplacement que `NSGlassEffectView` garantit), et non un second
  /// verre. Le noir part d'un bord et s'efface vers le verre nu, qui reste celui d'Apple.
  private final class FadeView: NSView {
    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  private let fadeView = FadeView()
  private var fadeIsEnabled = false

  /// Silhouette qui découpe le verre. À poser dans le même repère que la vue (cadre = `bounds`).
  let shapeMask = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    // Le verre ne s'arrondit pas de lui-même : c'est le masque qui donne la forme.
    cornerRadius = 0
    layer?.mask = shapeMask

    fadeView.wantsLayer = true
    contentView = fadeView
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Le fond ne prend jamais un clic : le contenu et la vue du panneau restent seuls
  /// interlocuteurs, comme avec le fond peint qu'il remplace.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Variante pour une forme simple — disque, capsule — où le rayon du verre suffit : le
  /// masque est retiré et c'est `cornerRadius` qui arrondit.
  func useRoundedCorners(radius: CGFloat) {
    layer?.mask = nil
    cornerRadius = radius
  }

  /// Fait partir le fond du noir au bord `start` pour le laisser en verre nu vers `end`. Les
  /// points sont dans le repère unitaire de Core Animation, origine en bas à gauche.
  /// `solidUntil` et `clearBy` sont des parts du trajet de `start` à `end` : noir franc
  /// jusqu'à la première, verre nu à partir de la seconde.
  func fadeToGlass(
    from start: CGPoint,
    to end: CGPoint,
    solidUntil: CGFloat = 0.72,
    clearBy: CGFloat = 0.97
  ) {
    fadeIsEnabled = true
    fadeView.gradient.startPoint = start
    fadeView.gradient.endPoint = end
    // Noir franc sur l'essentiel, puis une transition courte : seul le bord du bas est du
    // verre, comme la référence.
    fadeView.gradient.locations = [0, solidUntil as NSNumber, clearBy as NSNumber]
    style = .clear
  }

  /// Part de l'alpha du fond de la palette que prend la teinte : à pleine opacité le verre doit
  /// rester sombre sans être un aplat, sinon il n'y aurait plus rien à réfracter.
  private static let tintStrength: CGFloat = 0.55
  /// Avec le dégradé, c'est lui qui assombrit le haut : la teinte du verre reste à peine
  /// perceptible pour que le bas laisse voir le fond.
  private static let fadedTintStrength: CGFloat = 0.08

  /// Teinte le verre avec le fond de la palette : son alpha suit `Panel opacity`, donc
  /// plus le réglage baisse, plus le bureau se voit à travers.
  func applyTint(from palette: OverlayPalette) {
    tintColor = NSColor(cgColor: palette.panelBackground)?
      .withAlphaComponent(
        palette.panelBackground.alpha * (fadeIsEnabled ? Self.fadedTintStrength : Self.tintStrength)
      )

    guard fadeIsEnabled else { return }
    // Le noir du dégradé suit `Panel opacity` comme la teinte, sans la part de `tintStrength` :
    // c'est lui qui doit rester franchement noir au bord, là où le panneau se confond avec
    // l'encoche ou le bord de l'écran.
    let solid = palette.panelBackground
    fadeView.gradient.colors = [
      solid,
      solid,
      solid.copy(alpha: 0) ?? solid,
    ]
  }
}
