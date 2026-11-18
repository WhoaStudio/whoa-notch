import AppKit

/// Le ressort de la pastille : réponse 0,30 s, amortissement critique (aucun rebond), comme un
/// contrôle segmenté natif. `stiffness = (2π / réponse)²`, `damping = 4π × ratio / réponse`.
private enum PillSpring {
  static let stiffness: CGFloat = 438.6
  static let damping: CGFloat = 41.9
}

extension CALayer {
  /// Anime `keyPath` vers `value` avec le ressort de la pastille, depuis la valeur affichée à
  /// l'écran : un nouveau geste en plein mouvement repart de là où le calque se trouve, sans saut.
  /// Sans mouvement autorisé, la valeur est posée sèchement.
  fileprivate func pillSpring(_ keyPath: String, to value: Any) {
    let from = presentation()?.value(forKeyPath: keyPath) ?? self.value(forKeyPath: keyPath)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    setValue(value, forKeyPath: keyPath)
    if OverlayAnimation.allowsMotion, let from {
      let animation = CASpringAnimation(keyPath: keyPath)
      animation.mass = 1
      animation.stiffness = PillSpring.stiffness
      animation.damping = PillSpring.damping
      animation.fromValue = from
      animation.toValue = value
      animation.duration = animation.settlingDuration
      add(animation, forKey: keyPath)
    } else {
      removeAnimation(forKey: keyPath)
    }
    CATransaction.commit()
  }
}

/// Un profil dans la pastille : son logo et son nom. Le fond de l'actif est dessiné par la
/// pastille (il glisse d'un profil à l'autre) ; le segment ne gère que son encre, son survol et
/// son appui.
private final class DockPillSegmentView: DockButtonView {

  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private(set) var profileID = ""
  private var isActive = false
  private var isHovered = false
  private var isPressed = false
  private var showsName = true

  private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
  private static let iconSide: CGFloat = 12
  private static let iconGap: CGFloat = 4
  private static let pressedScale: CGFloat = 0.96
  static let horizontalPadding: CGFloat = 10

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    label.font = Self.font
    addSubview(icon)
    addSubview(label)
    // Le segment est l'élément d'accessibilité : l'icône et le texte ne se lisent pas à part.
    icon.setAccessibilityElement(false)
    label.setAccessibilityElement(false)
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func apply(_ profile: DockProfile, isActive newActive: Bool, showsName newShowsName: Bool) {
    let changed = newActive != isActive
    profileID = profile.id
    isActive = newActive
    showsName = newShowsName
    icon.image = NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: Self.iconSide, weight: .semibold))
    label.stringValue = profile.name
    label.isHidden = !newShowsName
    label.sizeToFit()
    toolTip = profile.name
    setAccessibilityLabel(profile.name)
    setAccessibilityValue(newActive ? 1 : 0)
    refreshAppearance(animated: changed)
    needsLayout = true
  }

  /// Encre et fond du survol : le gris, le gris éclairci au survol, le noir sur le fond actif.
  /// Un fondu court (0,15 s) lie deux états ; sans mouvement autorisé, ils s'enchaînent sec.
  private func refreshAppearance(animated: Bool) {
    if animated, OverlayAnimation.allowsMotion {
      let fade = CATransition()
      fade.type = .fade
      fade.duration = 0.15
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer?.add(fade, forKey: "ink")
    }
    let ink: NSColor
    if isActive {
      ink = .black
    } else {
      ink = NSColor(white: isHovered ? 0.80 : 0.62, alpha: 1)
    }
    layer?.backgroundColor =
      (isHovered && !isActive) ? NSColor(white: 1, alpha: 0.08).cgColor : NSColor.clear.cgColor
    icon.contentTintColor = ink
    label.textColor = ink
  }

  var preferredWidth: CGFloat {
    let name = showsName ? Self.iconGap + ceil(label.frame.width) : 0
    return Self.horizontalPadding * 2 + Self.iconSide + name
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    icon.frame = NSRect(
      x: Self.horizontalPadding, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide,
      height: Self.iconSide)
    label.frame.origin = NSPoint(
      x: Self.horizontalPadding + Self.iconSide + Self.iconGap,
      y: (bounds.height - label.frame.height) / 2)
  }

  // MARK: - Survol

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  private func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    refreshAppearance(animated: true)
  }

  // MARK: - Appui

  // Le retour se pose dès l'appui ; le clic, lui, se valide au relâchement (`DockButtonView`).
  override func mouseDown(with event: NSEvent) { setPressed(true) }

  override func mouseDragged(with event: NSEvent) {
    setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
  }

  override func mouseUp(with event: NSEvent) {
    setPressed(false)
    super.mouseUp(with: event)
  }

  private func setPressed(_ pressed: Bool) {
    guard pressed != isPressed, let layer else { return }
    isPressed = pressed
    layer.pillSpring(
      "transform", to: NSValue(caTransform3D: pressed ? pressedTransform(of: layer) : CATransform3DIdentity))
  }

  /// Réduit le segment autour de son centre, quel que soit le point d'ancrage du calque.
  private func pressedTransform(of layer: CALayer) -> CATransform3D {
    let scale = Self.pressedScale
    let anchor = CGPoint(
      x: layer.anchorPoint.x * bounds.width, y: layer.anchorPoint.y * bounds.height)
    let shift = CATransform3DMakeTranslation(
      (bounds.midX - anchor.x) * (1 - scale), (bounds.midY - anchor.y) * (1 - scale), 0)
    return CATransform3DScale(shift, scale, scale, 1)
  }

  /// Retire survol et appui, sans animation : la pastille se replie sous le curseur, qui ne
  /// livrera plus l'événement de sortie.
  func resetInteraction() {
    isHovered = false
    isPressed = false
    layer?.removeAnimation(forKey: "transform")
    layer?.transform = CATransform3DIdentity
    refreshAppearance(animated: false)
  }

  // MARK: - Accessibilité

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }
}

/// La pastille des profils : un gris foncé uni, un fin liseré, les profils côte à côte.
/// Volontairement sans verre, quel que soit le thème du dock.
final class DockProfilePillView: NSView {

  var onSelect: ((String) -> Void)?

  private var segments: [String: DockPillSegmentView] = [:]
  private var profiles: [DockProfile] = []
  private var activeID: String?
  /// Le fond de l'actif : un seul calque, sous les segments, qui glisse jusqu'au profil choisi.
  private let indicator = CALayer()
  private var indicatorPlaced = false
  private var animatesNextMove = false

  private static let inset: CGFloat = 3
  private static let segmentHeight: CGFloat = 22
  private static let segmentGap: CGFloat = 2
  /// Au-delà, seuls l'icône des profils inactifs reste ; le nom de l'actif ne se perd jamais.
  static let namedProfilesLimit = 5

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    layer?.borderWidth = 1
    indicator.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
    indicator.isHidden = true
    layer?.insertSublayer(indicator, at: 0)
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel("Profiles")
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  /// Taille voulue par le contenu ; nulle sans profil.
  var contentSize: NSSize {
    guard !profiles.isEmpty else { return .zero }
    let widths = profiles.compactMap { segments[$0.id]?.preferredWidth }
    let gaps = CGFloat(max(0, widths.count - 1)) * Self.segmentGap
    return NSSize(
      width: widths.reduce(0, +) + gaps + Self.inset * 2,
      height: Self.segmentHeight + Self.inset * 2)
  }

  func apply(profiles newProfiles: [DockProfile], activeID newActiveID: String?) {
    let ids = Set(newProfiles.map(\.id))
    for (id, segment) in segments where !ids.contains(id) {
      segment.removeFromSuperview()
      segments[id] = nil
    }
    for profile in newProfiles where segments[profile.id] == nil {
      let segment = DockPillSegmentView()
      segment.onClick = { [weak self, id = profile.id] in self?.onSelect?(id) }
      addSubview(segment)
      segments[profile.id] = segment
    }
    // Seul un vrai changement de profil fait glisser le fond ; le reste (ajout, renommage) le pose.
    animatesNextMove = indicatorPlaced && newActiveID != activeID
    profiles = newProfiles
    activeID = newActiveID
    let compact = newProfiles.count > Self.namedProfilesLimit
    for profile in newProfiles {
      let isActive = profile.id == newActiveID
      segments[profile.id]?.apply(profile, isActive: isActive, showsName: !compact || isActive)
    }
    setAccessibilityChildren(newProfiles.compactMap { segments[$0.id] })
    needsLayout = true
  }

  func resetInteraction() {
    segments.values.forEach { $0.resetInteraction() }
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    var x = Self.inset
    for profile in profiles {
      guard let segment = segments[profile.id] else { continue }
      let width = segment.preferredWidth
      segment.frame = NSRect(x: x, y: Self.inset, width: width, height: Self.segmentHeight)
      x += width + Self.segmentGap
    }
    placeIndicator()
  }

  /// Pose le fond sous le segment actif : d'un coup au premier placement ou hors changement de
  /// profil, en ressort sinon, depuis la position affichée à l'écran.
  private func placeIndicator() {
    guard let activeID, let target = segments[activeID]?.frame else {
      indicator.isHidden = true
      indicatorPlaced = false
      return
    }
    let animated = animatesNextMove && indicatorPlaced && !indicator.isHidden
    animatesNextMove = false
    let fromX = indicator.presentation()?.position.x ?? indicator.position.x
    let fromWidth = indicator.presentation()?.bounds.width ?? indicator.bounds.width

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    indicator.isHidden = false
    indicator.frame = target
    indicator.cornerRadius = target.height / 2
    CATransaction.commit()
    indicatorPlaced = true

    if animated {
      indicator.removeAnimation(forKey: "position.x")
      indicator.removeAnimation(forKey: "bounds.size.width")
      springIndicator("position.x", from: fromX, to: target.midX)
      springIndicator("bounds.size.width", from: fromWidth, to: target.width)
    } else {
      indicator.removeAnimation(forKey: "position.x")
      indicator.removeAnimation(forKey: "bounds.size.width")
    }
  }

  private func springIndicator(_ keyPath: String, from: CGFloat, to: CGFloat) {
    guard OverlayAnimation.allowsMotion, from != to else { return }
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.mass = 1
    animation.stiffness = PillSpring.stiffness
    animation.damping = PillSpring.damping
    animation.fromValue = from
    animation.toValue = to
    animation.duration = animation.settlingDuration
    indicator.add(animation, forKey: keyPath)
  }
}

/// La fenêtre de la pastille, au-dessus du dock. Elle n'apparaît qu'au survol du dock (ou d'ellemême) ;
/// son fond est transparent, hors de la pastille les clics la traversent.
@MainActor
final class DockProfilePillPanel {

  let pill = DockProfilePillView()
  private let panel: NSPanel
  private(set) var isShown = false

  init() {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    // Comme le dock : sans cela, le survol de la pastille ne serait pas livré à l'app.
    panel.acceptsMouseMovedEvents = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    panel.contentView = pill
    panel.alphaValue = 0
  }

  /// Montre la pastille dans `frame` (en coordonnées d'écran) ou la retire.
  func setShown(_ shown: Bool, frame: NSRect) {
    if shown {
      panel.setFrame(frame, display: true)
      guard !isShown else { return }
      isShown = true
      panel.orderFrontRegardless()
      pill.layer?.springReveal()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
        panel.animator().alphaValue = 1
      }
    } else if isShown {
      isShown = false
      pill.resetInteraction()
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
          panel.animator().alphaValue = 0
        },
        completionHandler: { [weak self] in
          MainActor.assumeIsolated {
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
          }
        })
    }
  }
}
