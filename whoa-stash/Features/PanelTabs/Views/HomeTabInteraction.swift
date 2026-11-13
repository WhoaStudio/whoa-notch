import AppKit

extension CALayer {

  /// Met le calque à l'échelle autour de son centre, au ressort. Sert au retour d'appui des
  /// boutons de l'onglet Global. Avec « Réduire les animations », rien ne bouge : l'échelle
  /// reste à 1 et c'est la teinte qui porte le retour d'appui.
  func springScale(to scale: CGFloat) {
    guard OverlayAnimation.allowsMotion else {
      removeAnimation(forKey: "transform")
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      transform = CATransform3DIdentity
      CATransaction.commit()
      return
    }
    // `transform` s'applique autour de `anchorPoint` : on compense pour que l'échelle se fasse
    // autour du centre, quel que soit le point d'ancrage du calque de la vue.
    let anchor = CGPoint(x: anchorPoint.x * bounds.width, y: anchorPoint.y * bounds.height)
    var matrix = CATransform3DIdentity
    matrix.m11 = scale
    matrix.m22 = scale
    matrix.m41 = (1 - scale) * (bounds.width / 2 - anchor.x)
    matrix.m42 = (1 - scale) * (bounds.height / 2 - anchor.y)
    springAnimate(keyPath: "transform", to: NSValue(caTransform3D: matrix))
  }
}

/// Bouton en pastille : fond qui s'éclaircit au survol, léger rétrécissement à l'appui, action
/// au relâchement dans la pastille (glisser dehors annule, comme un bouton système).
final class HomePillButton: NSView {

  var onClick: (() -> Void)?

  private let titleLabel = NSTextField(labelWithString: "")
  private var trackingArea: NSTrackingArea?

  private var isHovered = false { didSet { updateAppearance() } }
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      updateAppearance()
      layer?.springScale(to: isPressed ? 0.95 : 1)
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerCurve = .continuous
    titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .white
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.alignment = .center
    addSubview(titleLabel)
    setAccessibilityRole(.button)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var title: String {
    get { titleLabel.stringValue }
    set {
      titleLabel.stringValue = newValue
      setAccessibilityLabel(newValue)
      needsLayout = true
    }
  }

  /// Largeur qui contient le titre, marges comprises.
  var fittingWidth: CGFloat { ceil(titleLabel.intrinsicContentSize.width) + 20 }

  private func updateAppearance() {
    let alpha: CGFloat = isPressed ? 0.30 : (isHovered ? 0.22 : 0.14)
    layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    let height = titleLabel.intrinsicContentSize.height
    titleLabel.frame = NSRect(
      x: 8, y: (bounds.height - height) / 2, width: max(0, bounds.width - 16), height: height)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true }
  override func mouseExited(with event: NSEvent) { isHovered = false }
  override func mouseDown(with event: NSEvent) { isPressed = true }
  override func mouseDragged(with event: NSEvent) {
    isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
  }
  override func mouseUp(with event: NSEvent) {
    let inside = bounds.contains(convert(event.locationInWindow, from: nil))
    isPressed = false
    if inside { onClick?() }
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }
}

/// Ce que l'onglet Global dit quand l'agenda n'est pas lisible : une phrase et un bouton qui
/// fait ce qu'il peut faire — demander l'accès tant que macOS le permet, sinon ouvrir Réglages.
final class CalendarAccessCardView: NSView {

  var onAction: (() -> Void)?

  private let iconView = NSImageView()
  private let messageLabel = NSTextField(labelWithString: "")
  private let button = HomePillButton()

  private let buttonHeight: CGFloat = 20
  private let messageHeight: CGFloat = 14
  private let iconSize: CGFloat = 12

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    iconView.image = NSImage(
      systemSymbolName: "calendar.badge.exclamationmark", accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    iconView.contentTintColor = .white.withAlphaComponent(0.55)
    addSubview(iconView)

    messageLabel.font = .systemFont(ofSize: 11, weight: .regular)
    messageLabel.textColor = .white.withAlphaComponent(0.55)
    messageLabel.lineBreakMode = .byTruncatingTail
    addSubview(messageLabel)

    button.onClick = { [weak self] in self?.onAction?() }
    addSubview(button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ access: CalendarAccess) {
    switch access {
    case .notDetermined:
      messageLabel.stringValue = "Calendar not connected"
      button.title = "Allow access"
    case .denied, .granted:
      messageLabel.stringValue = "Calendar access is off"
      button.title = "Open Settings"
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let top = bounds.maxY - 2
    let messageY = top - messageHeight
    iconView.frame = NSRect(
      x: 0, y: messageY + (messageHeight - iconSize) / 2, width: iconSize, height: iconSize)
    let textX = iconSize + 5
    messageLabel.frame = NSRect(
      x: textX - 2, y: messageY, width: max(0, bounds.width - textX + 2), height: messageHeight)
    button.frame = NSRect(
      x: 0, y: messageY - 4 - buttonHeight, width: min(bounds.width, button.fittingWidth),
      height: buttonHeight)
  }
}

/// Titre qui défile au survol quand il est trop long pour tenir : posé exactement sur le titre
/// tronqué, il le remplace le temps du survol et laisse voir la fin, puis s'efface. Sans
/// « Réduire les animations », rien ne défile : le titre complet est alors dans l'infobulle.
final class TitleMarqueeOverlay: NSView {

  /// Dit à l'appelant de masquer (ou rendre) le titre tronqué qu'il recouvre.
  var onActiveChanged: ((Bool) -> Void)?

  private let label = NSTextField(labelWithString: "")
  private var trackingArea: NSTrackingArea?
  private(set) var isActive = false

  /// Pause avant que le texte parte, et vitesse du défilement en points par seconde.
  private let startDelay: CFTimeInterval = 0.35
  private let speed: CGFloat = 40

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    isHidden = true
    label.wantsLayer = true
    label.lineBreakMode = .byClipping
    label.usesSingleLineMode = true
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(text: String, font: NSFont?, color: NSColor?) {
    // Un nouveau titre remet le défilement à zéro, même si la souris est encore dessus.
    stop()
    label.stringValue = text
    label.font = font
    label.textColor = color
    needsLayout = true
  }

  /// Texte qui dépasse de la zone visible, en points.
  private var overflow: CGFloat {
    max(0, ceil(label.intrinsicContentSize.width) - bounds.width)
  }

  override func layout() {
    super.layout()
    label.frame = NSRect(
      x: 0, y: 0, width: max(bounds.width, ceil(label.intrinsicContentSize.width)),
      height: bounds.height)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) { start() }
  override func mouseExited(with event: NSEvent) { stop() }

  private func start() {
    guard !isActive, OverlayAnimation.allowsMotion, overflow > 0, let layer = label.layer else {
      return
    }
    isActive = true
    isHidden = false
    onActiveChanged?(true)

    let travel = overflow + 2
    let animation = CABasicAnimation(keyPath: "transform.translation.x")
    animation.fromValue = 0
    animation.toValue = -travel
    animation.duration = max(1, Double(travel / speed))
    animation.beginTime = CACurrentMediaTime() + startDelay
    animation.fillMode = .both
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    // La valeur finale est posée aussi : le texte reste au bout tant que la souris est là.
    layer.transform = CATransform3DMakeTranslation(-travel, 0, 0)
    layer.add(animation, forKey: "marquee")
  }

  private func stop() {
    guard isActive else { return }
    isActive = false
    label.layer?.removeAllAnimations()
    label.layer?.transform = CATransform3DIdentity
    isHidden = true
    onActiveChanged?(false)
  }
}
