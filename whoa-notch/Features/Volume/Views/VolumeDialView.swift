import AppKit

/// Vue racine du cadran de volume : un disque noir, de la même matière opaque que les autres
/// surfaces de l'overlay (`OverlayPalette.panelBackground`), portant une couronne de
/// graduations, le bandeau qui remplit la course jusqu'au niveau courant, la poignée qui y
/// court, et la valeur en grand au centre.
///
/// Le cadran ne se déplie pas depuis un bord comme les bandes de flanc et le panneau de
/// l'encoche : il **jaillit du curseur**. Tout ce qu'il peint vit donc dans un seul calque
/// (`contentLayer`) dont le point d'ancrage est posé sur le pointeur juste avant l'apparition,
/// et c'est son `transform` qui est porté jusqu'à l'échelle 1 par le ressort commun à tout
/// l'overlay (`SpringPreset.gentle`). Le même geste joué à l'envers le referme. L'ancrage ne
/// peut pas être celui du calque de la vue, qu'AppKit resynchronise à sa guise à chaque mise
/// en page.
final class VolumeDialView: NSView {

  /// La molette n'est exposée nulle part au niveau fenêtre par AppKit : on la capte ici, sur
  /// la vue qui reçoit réellement l'événement.
  var onScroll: ((CGFloat) -> Void)?

  /// Porte tout le cadran, et lui seul le grandissement depuis le curseur.
  private let contentLayer = CALayer()

  private let discLayer = CALayer()
  private let strokeLayer = CAShapeLayer()
  private let ticksRing: VolumeTicksRing
  private let trackLayer = CAShapeLayer()
  private let fillLayer = CAShapeLayer()
  private let handleLayer = CAShapeLayer()
  private let valueLayer = CATextLayer()
  private let captionLayer = CATextLayer()

  private(set) var isExpanded = false

  /// Échelle du cadran replié. Pas tout à fait zéro : une matrice d'échelle nulle n'est pas
  /// inversible, et Core Animation ne sait plus où poser ce qu'elle porte.
  private let collapsedScale: CGFloat = 0.02

  private let valueFontSize: CGFloat = 34
  private let captionFontSize: CGFloat = 11

  // Même remarque que dans `SunButtonView` : NSView (addSubview) et CALayer (addSublayer)
  // mélangés comme frères n'ont pas d'ordre garanti. zPosition fige le stacking.
  private enum Depth {
    static let disc: CGFloat = 0
    static let stroke: CGFloat = 1
    static let ticks: CGFloat = 2
    static let track: CGFloat = 3
    static let fill: CGFloat = 4
    static let handle: CGFloat = 5
    static let text: CGFloat = 6
  }

  init(initialPalette: OverlayPalette) {
    ticksRing = VolumeTicksRing(
      tickCount: VolumeDialGeometry.tickCount,
      palette: initialPalette
    )
    super.init(frame: .zero)
    wantsLayer = true
    setUp(palette: initialPalette)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp(palette: OverlayPalette) {
    // Clic droit : le menu partagé par tous les panneaux de l'overlay. Posé sur la vue de
    // contenu, AppKit remonte la chaîne des responders jusqu'à elle.
    menu = OverlayContextMenu.shared.menu

    contentLayer.zPosition = 0
    layer?.addSublayer(contentLayer)

    discLayer.zPosition = Depth.disc
    contentLayer.addSublayer(discLayer)

    strokeLayer.fillColor = nil
    strokeLayer.lineWidth = PanelGeometry.strokeWidth
    strokeLayer.zPosition = Depth.stroke
    contentLayer.addSublayer(strokeLayer)

    ticksRing.layer.zPosition = Depth.ticks
    contentLayer.addSublayer(ticksRing.layer)

    // Le bandeau et sa rainure partagent exactement le même chemin : c'est `strokeEnd` seul
    // qui dit jusqu'où le niveau est monté, donc les deux ne peuvent pas diverger.
    for arc in [trackLayer, fillLayer] {
      arc.fillColor = nil
      arc.lineWidth = VolumeDialGeometry.arcWidth
      arc.lineCap = .round
      contentLayer.addSublayer(arc)
    }
    trackLayer.zPosition = Depth.track
    fillLayer.zPosition = Depth.fill
    fillLayer.strokeEnd = 0

    // La poignée n'est pas un point qu'on déplace le long du bandeau : c'est **le bout du
    // bandeau lui-même**, tracé sur le même chemin, avec un bout rond et une épaisseur plus
    // grande. Un segment minuscule suffit — ce qu'on voit est son embout.
    //
    // C'est ce qui la tient sur la ligne en toutes circonstances. Une position animée
    // joindrait deux points par la corde et couperait à travers le cadran ; un support qu'on
    // ferait tourner resterait bien sur le cercle, mais le ressort le ferait déborder la
    // course aux deux bouts, là où `strokeEnd` est borné par Core Animation et s'arrête net.
    // Né du même chemin et borné de la même façon, le point ne peut plus s'en détacher.
    handleLayer.fillColor = nil
    handleLayer.lineWidth = VolumeDialGeometry.handleDiameter
    handleLayer.lineCap = .round
    handleLayer.shadowOffset = .zero
    handleLayer.zPosition = Depth.handle
    contentLayer.addSublayer(handleLayer)

    for text in [valueLayer, captionLayer] {
      text.alignmentMode = .center
      text.isWrapped = false
      text.truncationMode = .none
      text.zPosition = Depth.text
      text.contentsScale = window?.backingScaleFactor ?? 2
      contentLayer.addSublayer(text)
    }
    valueLayer.font = NSFont.systemFont(ofSize: valueFontSize, weight: .medium)
    valueLayer.fontSize = valueFontSize
    valueLayer.string = "0"
    captionLayer.font = NSFont.systemFont(ofSize: captionFontSize, weight: .medium)
    captionLayer.fontSize = captionFontSize
    captionLayer.string = "Volume"

    applyPalette(palette)

    // État de départ : replié et effacé. La première image montrée doit être le début du
    // jaillissement, jamais le disque déjà en place.
    contentLayer.opacity = 0
    contentLayer.transform = CATransform3DMakeScale(collapsedScale, collapsedScale, 1)
  }

  override func layout() {
    super.layout()
    guard bounds.width > 0, bounds.height > 0 else { return }

    // `bounds`/`position` plutôt que `frame` : pendant le jaillissement le calque porte une
    // échelle, et poser un `frame` sur un calque transformé ne veut plus rien dire.
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
    contentLayer.position = CGPoint(
      x: bounds.minX + contentLayer.anchorPoint.x * bounds.width,
      y: bounds.minY + contentLayer.anchorPoint.y * bounds.height
    )

    let disc = CGRect(origin: .zero, size: bounds.size)
    discLayer.frame = disc
    discLayer.cornerRadius = disc.width / 2

    // Le filet est tracé centré sur la frontière : la moitié qui déborderait du disque est
    // rattrapée par le demi-point d'`insetBy`, sinon il perdrait la moitié de son épaisseur.
    strokeLayer.frame = disc
    strokeLayer.path = CGPath(ellipseIn: disc.insetBy(dx: 0.5, dy: 0.5), transform: nil)

    ticksRing.layout(in: disc)

    let arcPath = VolumeDialGeometry.arcPath(in: disc)
    trackLayer.frame = disc
    trackLayer.path = arcPath
    fillLayer.frame = disc
    fillLayer.path = arcPath

    handleLayer.frame = disc
    handleLayer.path = arcPath
    let handle = handleStroke(forFraction: currentFraction)
    handleLayer.strokeStart = handle.start
    handleLayer.strokeEnd = handle.end

    // Le chiffre est posé un cheveu au-dessus du centre et la légende juste en dessous :
    // les deux ensemble, et non le seul chiffre, doivent se lire comme centrées dans le
    // disque. Les `CATextLayer` dessinent depuis le haut de leur cadre, d'où des cadres
    // décrits par leur sommet.
    let valueHeight = valueFontSize * 1.2
    valueLayer.frame = CGRect(
      x: disc.minX,
      y: disc.midY + 25 - valueHeight,
      width: disc.width,
      height: valueHeight
    )
    let captionHeight = captionFontSize * 1.4
    captionLayer.frame = CGRect(
      x: disc.minX,
      y: disc.midY - 24 - captionHeight,
      width: disc.width,
      height: captionHeight
    )

    CATransaction.commit()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    let scale = window?.backingScaleFactor ?? 2
    valueLayer.contentsScale = scale
    captionLayer.contentsScale = scale
  }

  // MARK: - Jaillissement

  /// Replie le cadran sans animation et pose son point de croissance sur `point` (dans le
  /// repère de la vue) — à appeler avant d'afficher la fenêtre, pour que la première image
  /// montrée soit déjà le début du geste.
  func prepareForReveal(growingFrom point: NSPoint) {
    isExpanded = false
    // La mise en page est vidée tout de suite : sans cela le cadre du calque serait posé
    // dans la même transaction que le jaillissement, qui partirait alors d'ailleurs.
    layoutSubtreeIfNeeded()
    setGrowthOrigin(point)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentLayer.opacity = 0
    contentLayer.transform = CATransform3DMakeScale(collapsedScale, collapsedScale, 1)
    CATransaction.commit()
  }

  /// Fait jaillir ou résorber le cadran. `completion` est appelée une fois le ressort
  /// stabilisé, pour que le contrôleur puisse retirer la fenêtre.
  func setVisible(_ visible: Bool, completion: (() -> Void)? = nil) {
    guard visible != isExpanded else {
      completion?()
      return
    }
    isExpanded = visible

    let scale: CGFloat = visible ? 1 : collapsedScale
    contentLayer.springAnimate(
      keyPath: "transform",
      to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
      preset: .gentle,
      completion: completion
    )
    // Le fondu est porté par le même ressort que l'échelle : sur un fondu court, le disque
    // aurait disparu avant d'avoir fini de se résorber et le geste passerait inaperçu.
    contentLayer.springAnimate(
      keyPath: "opacity", to: visible ? Float(1) : Float(0), preset: .gentle)
  }

  /// Pose le point d'ancrage du calque sur le pointeur, en compensant la position pour que le
  /// cadran ne bouge pas d'un pouce : seul le point depuis lequel il grandit change.
  private func setGrowthOrigin(_ point: NSPoint) {
    guard bounds.width > 0, bounds.height > 0 else { return }

    let anchor = CGPoint(
      x: min(max((point.x - bounds.minX) / bounds.width, 0), 1),
      y: min(max((point.y - bounds.minY) / bounds.height, 0), 1)
    )

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentLayer.anchorPoint = anchor
    contentLayer.position = CGPoint(
      x: bounds.minX + anchor.x * bounds.width,
      y: bounds.minY + anchor.y * bounds.height
    )
    CATransaction.commit()
  }

  // MARK: - Niveau

  private var currentFraction: CGFloat = 0

  func updateVolume(fraction: CGFloat, activeTickCount: Int, percent: Int, animated: Bool) {
    currentFraction = min(max(fraction, 0), 1)

    ticksRing.setActiveCount(activeTickCount, animated: animated)

    // Le bandeau et la poignée reçoivent le même ressort sur la même grandeur : ils
    // s'élancent, débordent et se stabilisent ensemble, donc le point reste sur le bout de
    // la ligne même en plein débattement.
    let handle = handleStroke(forFraction: currentFraction)
    if animated {
      fillLayer.springAnimate(keyPath: "strokeEnd", to: currentFraction)
      handleLayer.springAnimate(keyPath: "strokeStart", to: handle.start)
      handleLayer.springAnimate(keyPath: "strokeEnd", to: handle.end)
    } else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      fillLayer.strokeEnd = currentFraction
      handleLayer.strokeStart = handle.start
      handleLayer.strokeEnd = handle.end
      CATransaction.commit()
    }

    // Le chiffre, lui, ne s'anime jamais : un ressort sur une valeur qu'on lit la rendrait
    // illisible pendant tout le réglage, qui est précisément le moment où on la regarde.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    valueLayer.string = "\(percent)"
    CATransaction.commit()
  }

  /// Les deux bouts du segment qui fait la poignée : une longueur dérisoire finissant au
  /// niveau courant. Ce n'est pas lui qu'on voit mais son embout rond, large de
  /// `handleDiameter` — d'où le soin à le garder minuscule, pour que le point soit rond et
  /// non allongé.
  ///
  /// Sa longueur ne varie jamais, même à zéro, où le segment serait sinon vide et le point
  /// disparaîtrait : au plus bas il est repoussé au départ de la course, qu'il marque. Le
  /// bandeau, lui, est bel et bien vide à zéro — c'est le niveau qu'il montre, pas la position.
  private func handleStroke(forFraction fraction: CGFloat) -> (start: CGFloat, end: CGFloat) {
    let length = VolumeDialGeometry.handleStrokeLength
    let end = max(min(max(fraction, 0), 1), length)
    return (end - length, end)
  }

  // MARK: - Matière

  /// Palette du cadran : celle de l'overlay, ré-accentuée en orange. Le cadran ne suit pas
  /// l'accent choisi dans les Préférences, qui habille les graduations de la luminosité et la
  /// bague survolée du panneau de l'encoche — le son a sa couleur, et c'est l'orange de macOS.
  /// Définie ici, et non chez le contrôleur, pour que la repeinte sur changement d'apparence
  /// ne puisse pas retomber sur la palette accentuée d'ailleurs.
  static func palette(for appearance: NSAppearance) -> OverlayPalette {
    OverlayPalette.resolved(for: appearance).accented(with: .orange, in: appearance)
  }

  func applyPalette(_ palette: OverlayPalette) {
    discLayer.backgroundColor = palette.panelBackground
    strokeLayer.strokeColor = palette.strokeColor
    ticksRing.apply(palette: palette)

    trackLayer.strokeColor = palette.inactiveTickColor.copy(alpha: 0.18)
    fillLayer.strokeColor = palette.activeTickColor.copy(alpha: 0.85)

    handleLayer.strokeColor = palette.activeTickColor
    handleLayer.shadowColor = palette.activeTickColor
    handleLayer.shadowOpacity = palette.glowOpacity
    handleLayer.shadowRadius = palette.glowRadius

    valueLayer.foregroundColor = palette.buttonSymbolColor.cgColor
    captionLayer.foregroundColor = palette.tabInactiveContent.cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette(Self.palette(for: effectiveAppearance))
  }

  // MARK: - Événements

  override func scrollWheel(with event: NSEvent) {
    // L'événement s'arrête ici : il ne doit surtout pas remonter la chaîne des responders,
    // où il ferait défiler ce qu'il y a sous le cadran.
    onScroll?(event.scrollingDeltaY)
  }

  /// Hors du disque, la fenêtre est transparente : elle ne doit ni capter les clics ni recevoir
  /// la molette, sinon les quatre coins du cadre régleraient le volume et masqueraient ce qu'il
  /// y a dessous.
  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    let radius = min(bounds.width, bounds.height) / 2
    let offset = CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
    guard offset.x * offset.x + offset.y * offset.y <= radius * radius else { return nil }
    return super.hitTest(point)
  }
}
