import AppKit

// MARK: - Teintes

extension NotchUsageTone {
  static let amber = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.35, alpha: 1)
  static let red = NSColor(srgbRed: 1.0, green: 0.45, blue: 0.42, alpha: 1)

  /// Couleur de la jauge et de sa lueur : le vert de la courbe d'activité tant qu'il en reste.
  var gaugeColor: NSColor {
    switch self {
    case .plenty: NotchUsageCardView.barGreen
    case .low: Self.amber
    case .critical: Self.red
    }
  }

  /// Couleur des chiffres : blanche tant qu'il n'y a rien à signaler.
  var textColor: NSColor {
    switch self {
    case .plenty: .white
    case .low: Self.amber
    case .critical: Self.red
    }
  }
}

// MARK: - Info-bulle de survol

/// Bulle sombre qui suit le curseur au-dessus d'un tracé : celle de la courbe d'activité et celle
/// de la jauge, pour qu'elles se ressemblent. Vit dans un calque que la vue hôte ajoute.
final class NotchUsageHoverTip {

  enum Placement {
    /// À côté du point, du côté où il y a de la place (courbe).
    case beside
    /// Centrée sur le point (jauge).
    case centered
  }

  let layer = CALayer()
  private let textLayer = CATextLayer()
  private static let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)

  init() {
    layer.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
    layer.cornerRadius = 6
    textLayer.font = Self.font
    textLayer.fontSize = 10.5
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .center
    layer.addSublayer(textLayer)
    layer.isHidden = true
  }

  func updateScale(_ scale: CGFloat) {
    textLayer.contentsScale = scale
  }

  /// Montre `text` près de `x`, à la hauteur `y` (bas de la bulle), borné à `width`.
  func show(_ text: String, x: CGFloat, y: CGFloat, within width: CGFloat, placement: Placement) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    textLayer.string = text
    let textWidth = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 14
    let size = CGSize(width: textWidth, height: 18)
    let origin: CGFloat
    switch placement {
    case .beside:
      origin = x < width / 2 ? x + 8 : x - 8 - size.width
    case .centered:
      origin = x - size.width / 2
    }
    layer.frame = CGRect(
      x: min(max(0, origin), max(0, width - size.width)), y: y, width: size.width,
      height: size.height)
    textLayer.frame = CGRect(x: 0, y: 2, width: size.width, height: 14)
    layer.isHidden = false
  }

  func hide() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.isHidden = true
    CATransaction.commit()
  }
}

// MARK: - Jauge

/// La jauge est une rangée de traits verticaux : les premiers sont allumés, les autres restent
/// en creux. Chaque trait est une couche à part pour que les changements de valeur (et de
/// teinte) les allument ou les éteignent l'un après l'autre. Au chargement, les traits
/// ondulent ; un repère optionnel marque où serait une consommation régulière.
final class NotchUsageGaugeView: NSView {

  static let segmentCount = 40
  private static let segmentGap: CGFloat = 2
  private static let unlitColor = NSColor.white.withAlphaComponent(0.10).cgColor
  private static let loadingColor = NSColor.white.withAlphaComponent(0.16).cgColor

  /// Fraction **restante**, `0…1`. `nil` : aucune valeur à montrer.
  var remaining: Double? {
    didSet { if remaining != oldValue { needsLayout = true } }
  }

  var isLoading = false {
    didSet {
      guard isLoading != oldValue else { return }
      needsLayout = true
      updateShimmer()
    }
  }

  /// Reste qu'une consommation régulière laisserait (fraction `0…1`), ou `nil` sans repère.
  var paceMarker: Double? {
    didSet { if paceMarker != oldValue { needsLayout = true } }
  }

  private let segments = (0..<segmentCount).map { _ in CALayer() }
  private let marker = CALayer()
  private let tip = NotchUsageHoverTip()
  private var shownLit = 0
  private var shownTone = NotchUsageTone.plenty
  private var hasLaidOut = false
  private var trackingArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for segment in segments {
      segment.cornerRadius = 2
      segment.backgroundColor = Self.unlitColor
      segment.shadowRadius = 4
      segment.shadowOffset = .zero
      segment.shadowOpacity = 0
      layer?.addSublayer(segment)
    }
    marker.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
    marker.cornerRadius = 1
    marker.isHidden = true
    layer?.addSublayer(marker)
    layer?.addSublayer(tip.layer)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var tone: NotchUsageTone { NotchUsageTone(remaining: remaining) }

  private func litColor(at index: Int, tone: NotchUsageTone) -> CGColor {
    // Le dégradé de la courbe, étiré sur la rangée : la teinte s'éclaircit vers la pointe.
    let count = Self.segmentCount
    let ramp = 0.55 + 0.45 * Double(index) / Double(max(1, count - 1))
    return tone.gaugeColor.withAlphaComponent(ramp).cgColor
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateShimmer()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    tip.updateScale(window?.backingScaleFactor ?? 2)
  }

  // MARK: - Chargement

  private func updateShimmer() {
    for (index, segment) in segments.enumerated() {
      segment.removeAnimation(forKey: "shimmer")
      guard isLoading, window != nil, OverlayAnimation.allowsMotion else { continue }
      let wave = CABasicAnimation(keyPath: "opacity")
      wave.fromValue = 1
      wave.toValue = 0.3
      wave.duration = 0.7
      wave.autoreverses = true
      wave.repeatCount = .infinity
      wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      // Une onde qui court de gauche à droite : chaque trait part un peu après son voisin.
      wave.beginTime = CACurrentMediaTime() + 0.025 * Double(index)
      wave.fillMode = .backwards
      segment.add(wave, forKey: "shimmer")
    }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let count = Self.segmentCount
    let gap = Self.segmentGap
    let width = max(1, (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count))
    let fraction = min(1, max(0, remaining ?? 0))
    // Un reste non nul allume au moins un trait : « 1 % » ne doit pas ressembler à « vide ».
    let lit = fraction > 0 ? max(1, Int((fraction * Double(count)).rounded())) : 0
    let tone = self.tone
    let unlit = isLoading ? Self.loadingColor : Self.unlitColor

    // Valeurs de départ lues avant d'écrire les nouvelles, pour que l'animation reparte de ce
    // qui est à l'écran même si la précédente n'est pas finie.
    let toneChanged = tone != shownTone
    let animate =
      hasLaidOut && (lit != shownLit || toneChanged) && window != nil
      && OverlayAnimation.allowsMotion
    let previous = segments.map {
      (
        color: $0.presentation()?.backgroundColor ?? $0.backgroundColor,
        glow: $0.presentation()?.shadowOpacity ?? $0.shadowOpacity
      )
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, segment) in segments.enumerated() {
      segment.frame = CGRect(
        x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
      segment.backgroundColor = index < lit ? litColor(at: index, tone: tone) : unlit
      segment.shadowColor = tone.gaugeColor.cgColor
      segment.shadowOpacity = index < lit ? 0.45 : 0
    }
    if let paceMarker {
      marker.isHidden = false
      let x = CGFloat(min(1, max(0, paceMarker))) * bounds.width
      marker.frame = CGRect(x: x - 1, y: -3, width: 2, height: bounds.height + 6)
    } else {
      marker.isHidden = true
    }
    CATransaction.commit()

    // Les traits qui changent d'état s'allument (ou s'éteignent) en cascade : de gauche à
    // droite quand la jauge monte, de droite à gauche quand elle descend. Un changement de
    // teinte recolore d'un coup tous les traits qui restent allumés, de gauche à droite.
    if animate {
      let changed = min(lit, shownLit)..<max(lit, shownLit)
      let growing = lit > shownLit
      let start = CACurrentMediaTime()
      for index in 0..<count {
        let inRange = changed.contains(index)
        guard inRange || (toneChanged && index < min(lit, shownLit)) else { continue }
        let step =
          inRange
          ? (growing ? index - changed.lowerBound : changed.upperBound - 1 - index) : index
        let segment = segments[index]
        let timing = CAMediaTimingFunction(name: .easeOut)
        let color = CABasicAnimation(keyPath: "backgroundColor")
        color.fromValue = previous[index].color
        color.toValue = segment.backgroundColor
        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = previous[index].glow
        glow.toValue = segment.shadowOpacity
        for (animation, key) in [(color, "color"), (glow, "glow")] {
          animation.duration = 0.28
          animation.timingFunction = timing
          animation.beginTime = start + 0.014 * Double(step)
          animation.fillMode = .backwards
          segment.add(animation, forKey: key)
        }
      }
    }
    shownLit = lit
    shownTone = tone
    hasLaidOut = hasLaidOut || !bounds.isEmpty
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds.insetBy(dx: 0, dy: -6),
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    guard let remaining, !isLoading else {
      tip.hide()
      return
    }
    let x = convert(event.locationInWindow, from: nil).x
    tip.show(
      NotchUsageFormatting.exactText(remaining: remaining), x: x, y: bounds.height + 8,
      within: max(bounds.width, 1), placement: .centered)
  }

  override func mouseExited(with event: NSEvent) { tip.hide() }

  /// Cache la bulle : le bloc bouge ou son contenu change sous le curseur.
  func hideTip() { tip.hide() }

  /// Les clics traversent la jauge : ils appartiennent à la carte qui la porte.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Anneau

/// Petit anneau de reste, dans les onglets de l'en-tête : la teinte de la jauge, en un coup d'œil.
final class NotchUsageRingView: NSView {

  private let track = CAShapeLayer()
  private let arc = CAShapeLayer()

  /// Fraction restante `0…1` ; `nil` : anneau vide.
  var remaining: Double? {
    didSet {
      guard remaining != oldValue else { return }
      let end = CGFloat(min(1, max(0, remaining ?? 0)))
      let tint = NotchUsageTone(remaining: remaining).gaugeColor.cgColor
      if OverlayAnimation.allowsMotion, window != nil {
        arc.springAnimate(keyPath: "strokeEnd", to: end, preset: .gentle)
      } else {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeEnd = end
        CATransaction.commit()
      }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      arc.strokeColor = tint
      CATransaction.commit()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for shape in [track, arc] {
      shape.fillColor = nil
      shape.lineWidth = 2.5
      shape.lineCap = .round
      layer?.addSublayer(shape)
    }
    track.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
    arc.strokeColor = NotchUsageTone.plenty.gaugeColor.cgColor
    arc.strokeEnd = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let path = CGMutablePath()
    path.addArc(
      center: center, radius: min(rect.width, rect.height) / 2, startAngle: .pi / 2,
      endAngle: .pi / 2 - 2 * .pi, clockwise: true)
    for shape in [track, arc] {
      shape.frame = bounds
      shape.path = path
    }
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Pastille de texte

/// Petite pastille arrondie portant un mot (« 5H », « Over pace »).
final class NotchUsageTagView: NSView {

  static let height: CGFloat = 18

  private let label = NSTextField(labelWithString: "")

  var text: String {
    get { label.stringValue }
    set {
      guard newValue != label.stringValue else { return }
      label.stringValue = newValue
      label.sizeToFit()
      needsLayout = true
    }
  }

  var tint: NSColor = .white {
    didSet { applyTint() }
  }

  /// Fond plein plutôt que filet : pour la pastille d'alerte.
  var isFilled = false {
    didSet { applyTint() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = Self.height / 2
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    addSubview(label)
    applyTint()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func applyTint() {
    label.textColor = isFilled ? tint : tint.withAlphaComponent(0.8)
    layer?.backgroundColor = tint.withAlphaComponent(isFilled ? 0.16 : 0.10).cgColor
  }

  var fittingWidth: CGFloat { ceil(label.intrinsicContentSize.width) + 16 }

  override func layout() {
    super.layout()
    let size = label.intrinsicContentSize
    label.frame = NSRect(
      x: (bounds.width - ceil(size.width)) / 2, y: (bounds.height - size.height) / 2,
      width: ceil(size.width), height: size.height)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
