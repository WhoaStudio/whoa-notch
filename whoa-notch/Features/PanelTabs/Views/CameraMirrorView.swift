import AVFoundation
import AppKit

/// L'onglet Mirror : l'image de la caméra dans un cercle, avec à sa gauche le curseur courbe de
/// luminosité.
///
/// Le curseur ne règle que l'aperçu : deux voiles posés sur la vidéo, noir pour assombrir et blanc
/// pour éclaircir (`CameraBrightness`). Il ne touche ni à la caméra ni à la luminosité de l'écran.
///
/// La caméra n'est allumée que sur ordre de `setActive(_:)` : c'est le panneau qui sait quand
/// cette vue est réellement à l'écran. Sans autorisation, ou sans caméra, le cercle montre un
/// écriteau à la place de l'image.
///
/// Gestes, tous sur le cercle :
/// - pincement, ou défilement vertical : zoom numérique de 1× à 3× ;
/// - un clic : fige l'image, un second clic la relâche ;
/// - un double-clic : revient à 1× ;
/// - au survol : « Flip » (miroir / image vue par les autres) et, image figée, « Copy frame ».
///
/// Le mouvement ne touche jamais à la couche vidéo elle-même : le zoom passe par la transformation
/// d'une couche porteuse, l'ouverture et la fermeture par un obturateur posé *par-dessus*. Le
/// compositeur déplace ces couches sans redessiner la vidéo, donc aucune image n'est perdue.
final class CameraMirrorView: NSView {

  private let viewModel: CameraMirrorViewModel
  private let feedback: any OverlayFeedback

  private let circle = NSView()
  /// Porte la vidéo : c'est elle qui zoome.
  private let zoomLayer = CALayer()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  /// Dégradé de remplacement, quand la source ne fournit pas de session (fausse source).
  private let placeholderLayer = CAGradientLayer()
  private let darkenLayer = CALayer()
  private let lightenLayer = CALayer()
  /// Anneau de lumière : un halo blanc sur le bord du cercle, qui suit le curseur au-dessus du neutre.
  private let ringLayer = CAGradientLayer()
  /// Repères en tiers, visibles le temps d'un zoom.
  private let guidesLayer = CAShapeLayer()
  /// Obturateur : un disque plein percé d'un trou qui s'agrandit (ouverture) ou se referme.
  private let shutterLayer = CAShapeLayer()
  private let slider = CurvedBrightnessSlider()

  private let statusIcon = NSImageView()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let actionButton = HomePillButton()

  private let badge = NSView()
  private let badgeLabel = NSTextField(labelWithString: "")
  private let controls = NSView()
  private let flipButton = HomePillButton()
  private let copyButton = HomePillButton()

  /// Écart entre le bord du cercle et la piste du curseur.
  private static let sliderGap: CGFloat = 22
  private static let circleColor = NSColor(white: 0.08, alpha: 1)

  private var zoom = MirrorZoom()
  private var isMirrored = true
  private var isFrozen = false
  private var isHovering = false
  private var shutterIsOpen = false
  /// Compte les démarrages : l'obturateur qui se ferme ne masque la vidéo que s'il n'y en a pas eu d'autre depuis.
  private var runGeneration = 0
  private var currentState: CameraMirrorState = .idle

  private var edgeFeedbackFired = false
  private var scrollZoomLocked = false
  private var pressStart: NSPoint?
  private var trackingArea: NSTrackingArea?
  private var settleTask: Task<Void, Never>?
  private var guidesTask: Task<Void, Never>?
  private var copiedTask: Task<Void, Never>?

  init(
    viewModel: CameraMirrorViewModel,
    feedback: any OverlayFeedback = SystemOverlayFeedback(playsSound: false)
  ) {
    self.viewModel = viewModel
    self.feedback = feedback
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    circle.wantsLayer = true
    circle.layer?.masksToBounds = true
    circle.layer?.backgroundColor = Self.circleColor.cgColor
    addSubview(circle)

    // Miroir : on se voit comme dans une glace, pas comme les autres nous voient. La géométrie de
    // la couche passe par `bounds` et `position` (voir `layout()`), jamais par `frame`, qui n'est
    // pas défini une fois une transformation posée.
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
    zoomLayer.addSublayer(previewLayer)

    placeholderLayer.colors = [
      NSColor(srgbRed: 0.93, green: 0.64, blue: 0.45, alpha: 1).cgColor,
      NSColor(srgbRed: 0.45, green: 0.46, blue: 0.85, alpha: 1).cgColor,
    ]
    placeholderLayer.isHidden = true
    zoomLayer.addSublayer(placeholderLayer)
    circle.layer?.addSublayer(zoomLayer)

    darkenLayer.backgroundColor = NSColor.black.cgColor
    lightenLayer.backgroundColor = NSColor.white.cgColor
    circle.layer?.addSublayer(darkenLayer)
    circle.layer?.addSublayer(lightenLayer)

    ringLayer.type = .radial
    ringLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
    ringLayer.endPoint = CGPoint(x: 1, y: 1)
    ringLayer.colors = [
      NSColor.white.withAlphaComponent(0).cgColor,
      NSColor.white.withAlphaComponent(0).cgColor,
      NSColor.white.withAlphaComponent(0.9).cgColor,
    ]
    ringLayer.locations = [0, 0.84, 1]
    circle.layer?.addSublayer(ringLayer)

    guidesLayer.strokeColor = NSColor.white.withAlphaComponent(0.4).cgColor
    guidesLayer.lineWidth = 0.5
    guidesLayer.fillColor = nil
    guidesLayer.opacity = 0
    circle.layer?.addSublayer(guidesLayer)

    shutterLayer.fillColor = Self.circleColor.cgColor
    shutterLayer.fillRule = .evenOdd
    circle.layer?.addSublayer(shutterLayer)

    statusIcon.contentTintColor = NSColor(white: 0.62, alpha: 1)
    statusIcon.imageScaling = .scaleProportionallyUpOrDown
    statusLabel.alignment = .center
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = NSColor(white: 0.7, alpha: 1)
    actionButton.onClick = { [weak self] in self?.performStatusAction() }
    for view in [statusIcon, statusLabel, actionButton] {
      view.isHidden = true
      circle.addSubview(view)
    }

    badgeLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
    badgeLabel.textColor = .white
    badge.wantsLayer = true
    badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
    badge.layer?.cornerCurve = .continuous
    badge.addSubview(badgeLabel)
    badge.isHidden = true
    circle.addSubview(badge)

    controls.wantsLayer = true
    controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
    controls.layer?.cornerCurve = .continuous
    flipButton.title = "Flip"
    flipButton.onClick = { [weak self] in self?.toggleMirror() }
    copyButton.title = "Copy frame"
    copyButton.onClick = { [weak self] in self?.copyFrame() }
    copyButton.isHidden = true
    controls.addSubview(flipButton)
    controls.addSubview(copyButton)
    controls.alphaValue = 0
    controls.isHidden = true
    circle.addSubview(controls)

    addSubview(slider)
    slider.onChange = { [weak self] value in self?.applyBrightness(value) }
    applyBrightness(slider.value)

    viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
    apply(viewModel.state)
  }

  /// Allume ou éteint la caméra — voir `CameraMirrorViewModel.setActive(_:)`.
  func setActive(_ active: Bool) {
    viewModel.setActive(active)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()

    // Le cercle est le fond du panneau : centré, posé sur son bord bas à un liseré près.
    let diameter = NotchPanelGeometry.mirrorDiameter
    circle.frame = NSRect(
      x: bounds.midX - diameter / 2,
      y: bounds.minY + NotchPanelGeometry.mirrorRim,
      width: diameter,
      height: diameter
    )
    circle.layer?.cornerRadius = diameter / 2
    circle.layer?.cornerCurve = .circular

    let inner = circle.bounds
    let center = CGPoint(x: inner.midX, y: inner.midY)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for layer in [zoomLayer, previewLayer, placeholderLayer] {
      layer.bounds = inner
      layer.position = center
    }
    for layer in [darkenLayer, lightenLayer, ringLayer, guidesLayer, shutterLayer] {
      layer.frame = inner
    }
    guidesLayer.path = thirdsPath(in: inner)
    let shutter = shutterTarget(open: shutterIsOpen)
    shutterLayer.path = shutter.path
    shutterLayer.opacity = shutter.opacity
    CATransaction.commit()

    // La piste longe le cercle dans le coin haut-gauche, entre le cercle et le flanc : même
    // centre, un peu plus large.
    slider.frame = bounds
    slider.arc = ArcSliderGeometry(
      center: CGPoint(x: circle.frame.midX - bounds.minX, y: circle.frame.midY - bounds.minY),
      radius: diameter / 2 + Self.sliderGap,
      startAngle: 150 * .pi / 180,
      endAngle: 122 * .pi / 180
    )

    layoutStatus(in: inner)
    layoutOverlays(in: inner)
  }

  private func layoutStatus(in inner: NSRect) {
    let width = inner.width * 0.62
    let iconSize: CGFloat = 28
    let labelHeight = statusLabel.sizeThatFits(
      NSSize(width: width, height: .greatestFiniteMagnitude)
    ).height
    let buttonHeight: CGFloat = 22
    let gap: CGFloat = 8
    let showsButton = !actionButton.isHidden
    let total = iconSize + gap + labelHeight + (showsButton ? gap + buttonHeight : 0)

    var y = inner.midY + total / 2
    y -= iconSize
    statusIcon.frame = NSRect(x: inner.midX - iconSize / 2, y: y, width: iconSize, height: iconSize)
    y -= gap + labelHeight
    statusLabel.frame = NSRect(x: inner.midX - width / 2, y: y, width: width, height: labelHeight)
    y -= gap + buttonHeight
    let buttonWidth = actionButton.fittingWidth
    actionButton.frame = NSRect(
      x: inner.midX - buttonWidth / 2, y: y, width: buttonWidth, height: buttonHeight)
  }

  /// Pastille d'état en haut du cercle, boutons de survol en bas.
  private func layoutOverlays(in inner: NSRect) {
    let badgeHeight: CGFloat = 20
    let labelSize = badgeLabel.intrinsicContentSize
    let badgeWidth = ceil(labelSize.width) + 18
    badge.frame = NSRect(
      x: inner.midX - badgeWidth / 2, y: inner.maxY - 36 - badgeHeight, width: badgeWidth,
      height: badgeHeight)
    badge.layer?.cornerRadius = badgeHeight / 2
    badgeLabel.frame = NSRect(
      x: 9, y: (badgeHeight - labelSize.height) / 2, width: ceil(labelSize.width),
      height: labelSize.height)

    let inset: CGFloat = 3
    let spacing: CGFloat = 4
    let buttonHeight: CGFloat = 20
    var x = inset
    flipButton.frame = NSRect(x: x, y: inset, width: flipButton.fittingWidth, height: buttonHeight)
    x = flipButton.frame.maxX
    if !copyButton.isHidden {
      x += spacing
      copyButton.frame = NSRect(
        x: x, y: inset, width: copyButton.fittingWidth, height: buttonHeight)
      x = copyButton.frame.maxX
    }
    let controlsWidth = x + inset
    let controlsHeight = buttonHeight + 2 * inset
    controls.frame = NSRect(
      x: inner.midX - controlsWidth / 2, y: inner.minY + 26, width: controlsWidth,
      height: controlsHeight)
    controls.layer?.cornerRadius = controlsHeight / 2
  }

  private func thirdsPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    for fraction in [1.0 / 3, 2.0 / 3] {
      let x = rect.minX + rect.width * fraction
      let y = rect.minY + rect.height * fraction
      path.move(to: CGPoint(x: x, y: rect.minY))
      path.addLine(to: CGPoint(x: x, y: rect.maxY))
      path.move(to: CGPoint(x: rect.minX, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    return path
  }

  // MARK: - Obturateur

  /// Chemin et opacité de l'obturateur. Ouvert : le trou couvre tout le cercle. Fermé : plein.
  /// Avec « Réduire les animations » du système, il ne bouge pas : il s'efface en fondu.
  private func shutterTarget(open: Bool) -> (path: CGPath, opacity: Float) {
    let inner = circle.bounds
    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let radius = open && !reduced ? inner.width / 2 : 0
    let path = CGMutablePath()
    path.addRect(inner)
    path.addEllipse(
      in: CGRect(
        x: inner.midX - radius, y: inner.midY - radius, width: radius * 2, height: radius * 2))
    return (path, open && reduced ? 0 : 1)
  }

  private func setShutter(open: Bool, completion: (() -> Void)? = nil) {
    shutterIsOpen = open
    let target = shutterTarget(open: open)
    let fromPath = shutterLayer.presentation()?.path ?? shutterLayer.path
    let fromOpacity = shutterLayer.presentation()?.opacity ?? shutterLayer.opacity

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shutterLayer.path = target.path
    shutterLayer.opacity = target.opacity
    CATransaction.commit()

    guard OverlayAnimation.isEnabled else {
      shutterLayer.removeAllAnimations()
      completion?()
      return
    }

    let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    // Ouverture longue et douce, fermeture courte : l'œil attend la caméra, pas son extinction.
    let duration: CFTimeInterval = reduced ? 0.2 : (open ? 0.55 : 0.28)
    let timing =
      open
      ? CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      : CAMediaTimingFunction(name: .easeIn)

    let path = CABasicAnimation(keyPath: "path")
    path.fromValue = fromPath
    path.toValue = target.path
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = fromOpacity
    fade.toValue = target.opacity
    let group = CAAnimationGroup()
    group.animations = [path, fade]
    group.duration = duration
    group.timingFunction = timing

    CATransaction.begin()
    if let completion { CATransaction.setCompletionBlock(completion) }
    shutterLayer.add(group, forKey: "shutter")
    CATransaction.commit()
  }

  // MARK: - État

  private func apply(_ state: CameraMirrorState) {
    let wasRunning = currentState == .running
    currentState = state
    let showsVideo = state == .running

    if showsVideo {
      runGeneration += 1
      // `nil` : la fausse source n'a pas d'image, le dégradé tient la place de la vidéo.
      // Rattachée une seule fois : (re)brancher la couche modifie les connexions de la
      // session, ce qui plante si `startRunning()` tourne en même temps sur sa file.
      if previewLayer.session !== viewModel.session { previewLayer.session = viewModel.session }
      previewLayer.isHidden = false
      placeholderLayer.isHidden = viewModel.session != nil
      resetControls()
      setShutter(open: true)
    } else {
      let generation = runGeneration
      let hide = { [weak self] in
        guard let self, generation == runGeneration, currentState != .running else { return }
        // Couche masquée à l'arrêt plutôt que détachée : elle ne garde pas la dernière image figée.
        previewLayer.isHidden = true
        placeholderLayer.isHidden = true
      }
      // La caméra est déjà éteinte : l'obturateur se referme sur la dernière image, puis la
      // vidéo est masquée.
      if wasRunning {
        setShutter(open: false, completion: hide)
      } else {
        setShutter(open: false)
        hide()
      }
      resetControls()
    }
    // Les voiles ne règlent que la vidéo : sur l'écriteau, ils grisaient le texte.
    darkenLayer.isHidden = !showsVideo
    lightenLayer.isHidden = !showsVideo
    ringLayer.isHidden = !showsVideo

    let message: (symbol: String, text: String, action: String?)? =
      switch state {
      case .idle, .running: nil
      case .needsAccess: ("camera.fill", "Allow camera access to see yourself here.", "Allow camera")
      case .denied: ("camera.fill", "Camera access is off for Whoa Notch.", "Open Settings")
      case .unavailable: ("video.slash.fill", "No camera found.", nil)
      }

    let previousMessage = statusLabel.stringValue
    statusIcon.isHidden = message == nil
    statusLabel.isHidden = message == nil
    actionButton.isHidden = message?.action == nil
    if let message {
      statusIcon.image = NSImage(systemSymbolName: message.symbol, accessibilityDescription: nil)
      statusLabel.stringValue = message.text
      if let action = message.action { actionButton.title = action }
      if previousMessage != message.text {
        for view in [statusIcon, statusLabel, actionButton] as [NSView] where !view.isHidden {
          view.wantsLayer = true
          view.layer?.springReveal()
        }
      }
    }
    needsLayout = true
  }

  private func performStatusAction() {
    switch currentState {
    case .needsAccess: viewModel.requestAccess()
    case .denied: PrivacyPermissionService.openSettings(.camera)
    default: break
    }
  }

  /// Zoom, image figée et boutons repartent à zéro à chaque démarrage comme à chaque arrêt ; le
  /// sens du miroir, lui, reste celui que l'on a choisi.
  private func resetControls() {
    settleTask?.cancel()
    guidesTask?.cancel()
    copiedTask?.cancel()
    zoom.reset()
    isFrozen = false
    previewLayer.connection?.isEnabled = true
    zoomLayer.removeAnimation(forKey: "transform.scale")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    zoomLayer.setValue(1, forKeyPath: "transform.scale")
    guidesLayer.opacity = 0
    CATransaction.commit()
    copyButton.title = "Copy frame"
    copyButton.isHidden = true
    updateBadge(animated: false)
    updateControlsVisibility(animated: false)
  }

  private func applyBrightness(_ value: Double) {
    let overlay = CameraBrightness.overlay(for: value)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    darkenLayer.opacity = Float(overlay.darkness)
    lightenLayer.opacity = Float(overlay.lightness)
    // L'anneau prend le relais au-dessus du neutre : plein quand le voile blanc est à son maximum.
    ringLayer.opacity = Float(min(1, overlay.lightness / 0.55))
    CATransaction.commit()
  }

  // MARK: - Zoom

  private var canAdjust: Bool { currentState == .running }

  private func applyZoomLive() {
    zoomLayer.removeAnimation(forKey: "transform.scale")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    zoomLayer.setValue(zoom.displayed, forKeyPath: "transform.scale")
    CATransaction.commit()

    if zoom.isOutOfRange, !edgeFeedbackFired {
      edgeFeedbackFired = true
      feedback.tickCrossed()
    }
    updateBadge(animated: true)
  }

  private func beginZoomGesture() {
    edgeFeedbackFired = false
    setGuides(visible: true)
  }

  /// Fin du geste : l'image revient au ressort sur la borne si elle l'a dépassée.
  private func endZoomGesture() {
    settleTask?.cancel()
    zoom.settle()
    zoomLayer.springAnimate(keyPath: "transform.scale", to: zoom.settled)
    edgeFeedbackFired = false
    updateBadge(animated: true)
    guidesTask?.cancel()
    guidesTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      guard !Task.isCancelled else { return }
      self?.setGuides(visible: false)
    }
  }

  /// Les gestes sans phase de fin (molette) sont refermés après un court silence.
  private func scheduleSettle() {
    settleTask?.cancel()
    settleTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled else { return }
      self?.endZoomGesture()
    }
  }

  private func resetZoom() {
    zoom.reset()
    zoomLayer.springAnimate(keyPath: "transform.scale", to: 1)
    updateBadge(animated: true)
  }

  private func setGuides(visible: Bool) {
    guidesTask?.cancel()
    let target: Float = visible ? 1 : 0
    guard guidesLayer.opacity != target else { return }
    let from = guidesLayer.presentation()?.opacity ?? guidesLayer.opacity
    guidesLayer.opacity = target
    guard OverlayAnimation.allowsMotion else {
      guidesLayer.removeAnimation(forKey: "fade")
      return
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = target
    fade.duration = visible ? 0.12 : 0.3
    guidesLayer.add(fade, forKey: "fade")
  }

  override func magnify(with event: NSEvent) {
    guard canAdjust else { return super.magnify(with: event) }
    if event.phase.contains(.began) { beginZoomGesture() }
    zoom.magnify(by: Double(event.magnification))
    applyZoomLive()
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      endZoomGesture()
    }
  }

  /// Le défilement vertical zoome ; l'horizontal reste au panneau, qui s'en sert pour changer
  /// d'onglet. L'axe est décidé au début du geste et tenu jusqu'à la fin de l'inertie.
  override func scrollWheel(with event: NSEvent) {
    guard canAdjust else { return super.scrollWheel(with: event) }
    let precise = event.hasPreciseScrollingDeltas
    let isStart = event.phase.contains(.began) || event.phase.isEmpty && event.momentumPhase.isEmpty
    if isStart {
      scrollZoomLocked = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
    }
    guard scrollZoomLocked else { return super.scrollWheel(with: event) }
    // L'inertie ne zoome pas : un coup de doigt ne doit pas continuer seul.
    guard event.momentumPhase.isEmpty else { return }

    if isStart || guidesLayer.opacity == 0 { beginZoomGesture() }
    zoom.scroll(by: Double(event.scrollingDeltaY) * (precise ? 1 : 8))
    applyZoomLive()
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      endZoomGesture()
    } else {
      scheduleSettle()
    }
  }

  // MARK: - Clic, survol

  override func hitTest(_ point: NSPoint) -> NSView? {
    if let grabbed = slider.hitTest(point) { return grabbed }
    let local = convert(point, from: superview)
    let center = CGPoint(x: circle.frame.midX, y: circle.frame.midY)
    let radius = circle.frame.width / 2
    guard hypot(local.x - center.x, local.y - center.y) <= radius else { return nil }
    // Boutons et écriteau répondent eux-mêmes ; le reste du cercle revient à cette vue.
    let hit = circle.hitTest(local)
    return hit === circle ? self : hit
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    pressStart = canAdjust ? event.locationInWindow : nil
    // Relayé au panneau : à la souris, un glissé sur le cercle change d'onglet.
    super.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressStart = nil
      super.mouseUp(with: event)
    }
    guard let start = pressStart, canAdjust else { return }
    guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) < 4 else {
      return
    }
    // Le second clic d'un double-clic annule le gel du premier avant de revenir à 1×.
    toggleFreeze()
    if event.clickCount >= 2 { resetZoom() }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
    updateControlsVisibility(animated: true)
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    updateControlsVisibility(animated: true)
  }

  private func updateControlsVisibility(animated: Bool) {
    let visible = canAdjust && isHovering
    if visible { controls.isHidden = false }
    let duration = animated && OverlayAnimation.allowsMotion ? 0.15 : 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      controls.animator().alphaValue = visible ? 1 : 0
    } completionHandler: { [weak self] in
      guard let self else { return }
      controls.isHidden = !(canAdjust && isHovering)
    }
  }

  // MARK: - Image figée, miroir, copie

  private func toggleFreeze() {
    isFrozen.toggle()
    // Couper la connexion fige la dernière image à l'écran, sans arrêter la caméra.
    previewLayer.connection?.isEnabled = !isFrozen
    copyButton.isHidden = !isFrozen
    copyButton.title = "Copy frame"
    updateBadge(animated: true)
    needsLayout = true
  }

  private func toggleMirror() {
    isMirrored.toggle()
    previewLayer.springAnimate(keyPath: "transform.scale.x", to: isMirrored ? -1.0 : 1.0)
  }

  private func updateBadge(animated: Bool) {
    var parts: [String] = []
    if isFrozen { parts.append("Paused") }
    if zoom.isZoomed { parts.append(String(format: "%.1f×", zoom.settled)) }
    let text = parts.joined(separator: " · ")
    let wasHidden = badge.isHidden
    badge.isHidden = text.isEmpty
    guard badgeLabel.stringValue != text else { return }
    badgeLabel.stringValue = text
    needsLayout = true
    if animated, wasHidden, !text.isEmpty {
      badge.layer?.crossfadeIn(delay: 0, duration: 0.18)
    }
  }

  /// Copie l'image telle qu'on la voit : recadrée au zoom, dans le sens du miroir, sans les voiles.
  private func copyFrame() {
    guard let source = viewModel.snapshot() ?? placeholderImage(),
      let image = renderCopy(of: source)
    else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])

    copyButton.title = "Copied"
    needsLayout = true
    copiedTask?.cancel()
    copiedTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(1200))
      guard !Task.isCancelled, let self else { return }
      copyButton.title = "Copy frame"
      needsLayout = true
    }
  }

  private func renderCopy(of source: CGImage) -> NSImage? {
    let size = CGSize(width: source.width, height: source.height)
    let crop = MirrorZoom.visibleRect(imageSize: size, zoom: zoom.settled).integral
    guard let cropped = source.cropping(to: crop) else { return nil }
    let side = Int(min(crop.width, crop.height))
    guard
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    if isMirrored {
      context.translateBy(x: CGFloat(side), y: 0)
      context.scaleBy(x: -1, y: 1)
    }
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let result = context.makeImage() else { return nil }
    return NSImage(cgImage: result, size: NSSize(width: side, height: side))
  }

  /// La fausse source n'a pas d'image : le dégradé en tient lieu, pour que la copie se vérifie aussi.
  private func placeholderImage() -> CGImage? {
    let side = 240
    guard
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    placeholderLayer.render(in: context)
    return context.makeImage()
  }
}
