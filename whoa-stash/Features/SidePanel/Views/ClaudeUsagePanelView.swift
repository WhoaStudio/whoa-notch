import AppKit

/// Contenu du panneau latéral : l'en-tête « Claude Usage » et les deux fenêtres de quota, chacune
/// avec sa barre horizontale, son pourcentage et son instant de réinitialisation.
///
/// Mise en page en frames, comme le reste de l'overlay — `layout()` est la seule source de vérité
/// des positions, et les hauteurs sont des constantes nommées plutôt que des nombres répétés.
final class ClaudeUsagePanelView: NSView {

  /// `tintsMark: false` : l'étoile reste blanche au centre, seule la bague autour d'elle porte
  /// la couleur du taux — l'en-tête doit rester lisible comme un titre.
  private let ring = ClaudeUsageRing(tintsMark: false)
  private var state: ClaudeUsageState = .loading
  private let titleLabel = NSTextField(labelWithString: "Claude Usage")
  private let sessionRow = ClaudeUsageRowView(title: "Current session")
  private let allModelsRow = ClaudeUsageRowView(title: "All models")

  /// Réglée par la vue hôte selon sa silhouette, comme `trailingInset`.
  var leadingInset: CGFloat = 22 {
    didSet {
      guard leadingInset != oldValue else { return }
      needsLayout = true
    }
  }
  /// Réglée par la vue hôte selon sa silhouette : sur la carte accrochée au bord de l'écran, ce
  /// bord touche l'écran et les coins concaves y rognent la zone réellement peinte, donc la
  /// marge y est plus large que la gauche ; dans la bulle, les deux bords sont symétriques.
  var trailingInset: CGFloat = 26 {
    didSet {
      guard trailingInset != oldValue else { return }
      needsLayout = true
    }
  }
  /// Marge haute et basse, réglable par la vue hôte.
  var verticalInset: CGFloat = 18 {
    didSet {
      guard verticalInset != oldValue else { return }
      needsLayout = true
    }
  }
  /// Hauteur de l'en-tête, et donc diamètre de la bague.
  private let headerHeight: CGFloat = 30
  /// Entre la bague et le titre.
  private let headerGap: CGFloat = 10
  private var headerSpacing: CGFloat = 16
  private var rowSpacing: CGFloat = 16

  /// Resserre les marges et les écarts verticaux : la carte du panneau de l'encoche tient en
  /// 172 pt au lieu de 190, sans toucher à la bulle de la bande latérale, qui garde les siens.
  func useCompactSpacing() {
    verticalInset = 10
    headerSpacing = 10
    rowSpacing = 10
    needsLayout = true
  }

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
    if let layer { ring.install(in: layer) }

    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    addSubview(titleLabel)

    addSubview(sessionRow)
    addSubview(allModelsRow)

    applyPalette()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    ring.setContentsScale(window?.backingScaleFactor ?? 2)
  }

  private func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    titleLabel.textColor = palette.buttonSymbolColor
    ring.markColor = palette.buttonSymbolColor.cgColor
    applyRing(animated: false)
    sessionRow.applyPalette()
    allModelsRow.applyPalette()
  }

  // MARK: - État

  private func applyRing(animated: Bool) {
    ring.apply(utilization: state.snapshot?.session.utilization, animated: animated)
  }

  func apply(_ state: ClaudeUsageState, animated: Bool) {
    apply(
      state,
      title: "Claude Usage",
      primaryLabel: "Current session",
      secondaryLabel: "All models",
      animated: animated
    )
  }

  func apply(
    _ state: ClaudeUsageState,
    title: String,
    primaryLabel: String,
    secondaryLabel: String,
    animated: Bool
  ) {
    self.state = state
    applyRing(animated: animated)
    titleLabel.stringValue = title
    sessionRow.title = primaryLabel
    allModelsRow.title = secondaryLabel
    switch state {
    case .loaded(let snapshot):
      sessionRow.apply(window: snapshot.session, animated: animated)
      allModelsRow.apply(window: snapshot.allModels, animated: animated)
    case .loading:
      sessionRow.applyPlaceholder(detail: "Loading…")
      allModelsRow.applyPlaceholder(detail: "Loading…")
    case .unavailable(let reason), .expired(let reason):
      sessionRow.applyPlaceholder(detail: reason)
      allModelsRow.applyPlaceholder(detail: "")
    }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()

    let contentWidth = bounds.width - leadingInset - trailingInset
    let headerTop = bounds.maxY - verticalInset - headerHeight

    ring.layout(
      in: bounds,
      center: CGPoint(x: leadingInset + headerHeight / 2, y: headerTop + headerHeight / 2),
      diameter: headerHeight
    )

    let titleSize = titleLabel.intrinsicContentSize
    titleLabel.frame = NSRect(
      x: leadingInset + headerHeight + headerGap,
      y: headerTop + (headerHeight - titleSize.height) / 2,
      width: titleLabel.layoutWidth,
      height: titleSize.height
    )

    let rowHeight = ClaudeUsageRowView.height
    let sessionTop = headerTop - headerSpacing - rowHeight
    sessionRow.frame = NSRect(
      x: leadingInset, y: sessionTop, width: contentWidth, height: rowHeight)
    allModelsRow.frame = NSRect(
      x: leadingInset,
      y: sessionTop - rowSpacing - rowHeight,
      width: contentWidth,
      height: rowHeight
    )
  }
}

/// Une ligne du panneau : intitulé à gauche, réinitialisation à droite, barre pleine largeur
/// dessous, puis « 73 % Used ».
private final class ClaudeUsageRowView: NSView {

  static let titleHeight: CGFloat = 16
  static let barHeight: CGFloat = 6
  static let usedHeight: CGFloat = 15
  static let innerSpacing: CGFloat = 7
  static var height: CGFloat { titleHeight + innerSpacing + barHeight + innerSpacing + usedHeight }

  private let titleLabel: NSTextField
  private let resetLabel = NSTextField(labelWithString: "")
  private let usedLabel = NSTextField(labelWithString: "")
  private let trackLayer = CALayer()
  private let fillLayer = CALayer()
  private var utilization: Double = 0

  init(title: String) {
    titleLabel = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  var title: String {
    get { titleLabel.stringValue }
    set { titleLabel.stringValue = newValue }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
    resetLabel.font = .systemFont(ofSize: 11, weight: .regular)
    resetLabel.alignment = .right
    usedLabel.font = .systemFont(ofSize: 11.5, weight: .medium)

    addSubview(titleLabel)
    addSubview(resetLabel)
    addSubview(usedLabel)

    layer?.addSublayer(trackLayer)

    // Ancré à gauche : c'est la largeur qui est animée, et la barre doit grandir vers la
    // droite sans que son origine ne bouge.
    fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
    layer?.addSublayer(fillLayer)

    applyPalette()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPalette()
  }

  func applyPalette() {
    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    titleLabel.textColor = palette.buttonSymbolColor
    usedLabel.textColor = palette.buttonSymbolColor
    resetLabel.textColor = .secondaryLabelColor
    trackLayer.backgroundColor = ClaudeUsagePalette.track
  }

  func apply(window: ClaudeUsageWindow, animated: Bool) {
    resetLabel.stringValue = ClaudeUsageFormatting.resetText(for: window.resetsAt)
    usedLabel.stringValue = "\(window.percentage)% Used"
    utilization = window.utilization
    needsLayout = true
    updateFill(animated: animated)
  }

  func applyPlaceholder(detail: String) {
    resetLabel.stringValue = detail
    usedLabel.stringValue = "—"
    utilization = 0
    needsLayout = true
    updateFill(animated: false)
  }

  /// Seul endroit qui fixe la largeur du remplissage. `apply` et `layout` y passent tous les
  /// deux : a la premiere passe la vue n'a pas encore de largeur et seule la mise en page peut
  /// donner la bonne valeur ; ensuite c'est `apply` qui l'anime.
  private func updateFill(animated: Bool) {
    let width = bounds.width * CGFloat(utilization)
    let color = ClaudeUsagePalette.color(for: utilization)

    guard animated, bounds.width > 0 else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      fillLayer.bounds.size.width = width
      fillLayer.backgroundColor = color
      CATransaction.commit()
      return
    }

    fillLayer.springAnimate(keyPath: "bounds.size.width", to: width, preset: .gentle)
    fillLayer.backgroundColor = color
  }

  override func layout() {
    super.layout()

    let titleTop = bounds.maxY - Self.titleHeight
    let titleSize = titleLabel.intrinsicContentSize
    let titleWidth = titleLabel.layoutWidth
    titleLabel.frame = NSRect(x: 0, y: titleTop, width: titleWidth, height: Self.titleHeight)

    // Le libellé de droite ne mord jamais sur celui de gauche : il est tronqué par la
    // largeur disponible plutôt que de se superposer quand la locale est verbeuse.
    let resetX = max(titleWidth + 8, bounds.width - resetLabel.layoutWidth)
    resetLabel.frame = NSRect(
      x: resetX, y: titleTop, width: bounds.width - resetX, height: Self.titleHeight)

    let barY = titleTop - Self.innerSpacing - Self.barHeight
    trackLayer.frame = NSRect(x: 0, y: barY, width: bounds.width, height: Self.barHeight)
    trackLayer.cornerRadius = Self.barHeight / 2

    fillLayer.bounds.size.height = Self.barHeight
    fillLayer.position = CGPoint(x: 0, y: barY + Self.barHeight / 2)
    fillLayer.cornerRadius = Self.barHeight / 2
    updateFill(animated: false)

    usedLabel.frame = NSRect(
      x: 0, y: bounds.minY, width: usedLabel.layoutWidth, height: Self.usedHeight)
  }
}
