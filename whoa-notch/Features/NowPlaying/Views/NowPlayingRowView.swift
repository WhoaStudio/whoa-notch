import AppKit

/// Lecteur de l'onglet Global, déplié : pochette portant l'icône de l'application qui joue, titre
/// et artiste avec le visualiseur à leur droite, puis la progression encadrée du temps écoulé et
/// du temps restant, et enfin précédent / lecture-pause / suivant avec le volume du système.
///
/// Quand une source sait donner la suite (Apple Musique, Spotify), la colonne « Playing Next »
/// s'ouvre à droite, séparée par un filet, et le lecteur se resserre sur la gauche ; sinon il
/// occupe toute la largeur.
final class NowPlayingRowView: NSView {

  var onCommand: ((NowPlayingCommand) -> Void)?
  /// Position choisie en glissant sur la barre de progression, en secondes.
  var onSeek: ((TimeInterval) -> Void)?

  private let artworkView = ArtworkView()
  private let titleLabel = NowPlayingRowView.label(size: 14, weight: .semibold, color: .white)
  private let titleMarquee = TitleMarqueeOverlay()
  private let artistLabel = NowPlayingRowView.label(
    size: 12, weight: .regular, color: .white.withAlphaComponent(0.5))
  private let visualizer = AudioVisualizerView()
  private let elapsedLabel = NowPlayingRowView.label(
    size: 11, weight: .regular, color: .white.withAlphaComponent(0.5))
  private let remainingLabel = NowPlayingRowView.label(
    size: 11, weight: .regular, color: .white.withAlphaComponent(0.5))
  private let progress = NowPlayingSliderView(isInteractive: false, isScrubbable: true)
  private let volumeSlider = NowPlayingSliderView(isInteractive: true)
  private let volumeIcon = NSImageView()
  private let previousButton = NowPlayingControlButton(symbol: "backward.fill", size: 14)
  private let playPauseButton = NowPlayingControlButton(symbol: "pause.fill", size: 18)
  private let nextButton = NowPlayingControlButton(symbol: "forward.fill", size: 14)

  private var outgoingQueueLayers: [ObjectIdentifier: CALayer] = [:]
  private let queueHeader = NowPlayingRowView.label(
    size: 13, weight: .semibold, color: .white.withAlphaComponent(0.5))
  private let queueDivider = NSBox()
  private let queueViews = (0..<3).map { _ in QueueItemView() }

  private var state: NowPlayingState?
  private var tickTimer: Timer?

  /// Balayage de piste : même suiveur que le balayage d'onglets, pour que les deux gestes
  /// partagent seuils et abandon d'un geste vertical.
  private var trackSwipe = TabSwipeTracker()
  private var swipeCrossedCommit = false
  private let swipeFeedback: OverlayFeedback = SystemOverlayFeedback(playsSound: false)
  /// Sens du dernier saut demandé (+1 suivant, -1 précédent) et jusqu'à quand il vaut : le
  /// titre suivant arrive du côté d'où il vient, au lieu de toujours glisser du même côté.
  private var pendingSkip: (direction: CGFloat, until: Date)?
  private var queue: [QueueItem] = []

  /// Part de la largeur gardée par le lecteur quand la colonne de droite est ouverte.
  private let playerShare: CGFloat = 0.58
  private let queueGap: CGFloat = 20

  private let controlsHeight: CGFloat = 26
  private let progressHeight: CGFloat = 12
  private let rowGap: CGFloat = 4
  private let buttonPitch: CGFloat = 40
  private let volumeWidth: CGFloat = 120
  private let minimumTimeWidth: CGFloat = 34
  /// Marge interne d'un `NSTextField` de chaque côté : sans elle compensée, le texte ne tombe
  /// pas sur les bords de la pochette et du curseur de volume.
  private let labelPadding: CGFloat = 2

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    artworkView.badgeScale = 0.36
    artworkView.badgeInset = 4
    addSubview(artworkView)

    titleLabel.lineBreakMode = .byTruncatingTail
    artistLabel.lineBreakMode = .byTruncatingTail
    titleMarquee.onActiveChanged = { [weak self] active in
      self?.titleLabel.alphaValue = active ? 0 : 1
    }
    for label in [elapsedLabel, remainingLabel] {
      label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }
    remainingLabel.alignment = .right
    for view in [
      titleLabel, titleMarquee, artistLabel, visualizer, elapsedLabel, remainingLabel, progress,
    ] as [NSView] {
      addSubview(view)
    }

    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
    volumeIcon.image = NSImage(
      systemSymbolName: "speaker.fill", accessibilityDescription: "Volume")?
      .withSymbolConfiguration(configuration)
    volumeIcon.contentTintColor = .white.withAlphaComponent(0.5)
    addSubview(volumeIcon)
    volumeSlider.setAccessibilityLabel("Volume")
    volumeSlider.onChange = { value in SystemVolumeService.shared.setVolume(Float(value)) }
    addSubview(volumeSlider)

    progress.setAccessibilityLabel("Playback position")
    progress.onScrub = { [weak self] value in self?.previewScrub(value) }
    progress.onScrubEnd = { [weak self] value in self?.commitScrub(value) }

    previousButton.onClick = { [weak self] in self?.skip(.previousTrack) }
    playPauseButton.onClick = { [weak self] in self?.onCommand?(.togglePlayPause) }
    nextButton.onClick = { [weak self] in self?.skip(.nextTrack) }
    [previousButton, playPauseButton, nextButton].forEach(addSubview)

    queueHeader.stringValue = "Playing Next"
    queueDivider.boxType = .custom
    queueDivider.borderWidth = 0
    queueDivider.fillColor = .white.withAlphaComponent(0.15)
    for view in [queueHeader, queueDivider] as [NSView] { addSubview(view) }
    queueViews.forEach(addSubview)
    apply(queue: [])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func label(size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.wantsLayer = true
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    return label
  }

  func apply(_ state: NowPlayingState?) {
    let previous = self.state
    let animates = window != nil && !isHiddenOrHasHiddenAncestor && OverlayAnimation.allowsMotion
    // Rien ↔ un morceau : fondu de toute la ligne. Un morceau → un autre : la pochette seule
    // fond, le texte glisse déjà (voir `updateMetadata`).
    if animates, (previous == nil) != (state == nil) {
      fade(layer, duration: 0.25)
    } else if animates, let previous, let state, previous.title != state.title {
      fade(artworkView.layer, duration: 0.25)
      artworkView.layer?.springReveal(x: revealOffset())
    }
    self.state = state
    guard let state else {
      tickTimer?.invalidate()
      tickTimer = nil
      updateMetadata(title: "Nothing playing", subtitle: "")
      artworkView.setArtwork(nil)
      artworkView.clearSource()
      visualizer.setAnimating(false)
      playPauseButton.setSymbol("play.fill")
      updateProgress()
      needsLayout = true
      return
    }
    updateMetadata(
      title: state.title,
      subtitle: [state.artist, state.album].filter { !$0.isEmpty }.joined(separator: " - ")
    )
    artworkView.setArtwork(state.artwork)
    artworkView.setSource(bundleIdentifier: state.bundleIdentifier)
    visualizer.setAnimating(state.isPlaying)
    playPauseButton.setSymbol(state.isPlaying ? "pause.fill" : "play.fill")
    // En pause, la barre s'atténue : on voit d'un coup d'œil que le temps ne court plus.
    let progressAlpha: CGFloat = state.isPlaying ? 1 : 0.55
    if animates {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        progress.animator().alphaValue = progressAlpha
      }
    } else {
      progress.alphaValue = progressAlpha
    }
    updateProgress()

    // La position n'est renvoyée qu'aux changements : on l'avance ici, tant que ça joue.
    if state.isPlaying, tickTimer == nil {
      let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateProgress() }
      }
      timer.tolerance = 0.2
      RunLoop.main.add(timer, forMode: .common)
      tickTimer = timer
    } else if !state.isPlaying {
      tickTimer?.invalidate()
      tickTimer = nil
    }
    needsLayout = true
  }

  private func updateMetadata(title: String, subtitle: String) {
    for (label, value) in [(titleLabel, title), (artistLabel, subtitle)] {
      guard label.stringValue != value else { continue }
      label.stringValue = value
      label.toolTip = value
      if window != nil { label.layer?.springReveal(x: revealOffset(), y: 0) }
    }
    titleMarquee.apply(text: title, font: titleLabel.font, color: titleLabel.textColor)
  }

  /// D'où arrive le nouveau texte : du côté du geste si l'on vient de sauter une piste.
  private func revealOffset() -> CGFloat {
    if let skip = pendingSkip, skip.until > .now { return skip.direction * 14 }
    return 8
  }

  /// Fondu de croisement posé sur un calque, avant que son contenu ne change.
  private func fade(_ layer: CALayer?, duration: CFTimeInterval) {
    let transition = CATransition()
    transition.type = .fade
    transition.duration = duration
    transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer?.add(transition, forKey: "crossfade")
  }

  /// Précédent ou suivant, depuis un bouton ou un balayage.
  private func skip(_ command: NowPlayingCommand) {
    guard command == .nextTrack || command == .previousTrack else { return }
    pendingSkip = (command == .nextTrack ? 1 : -1, Date.now.addingTimeInterval(3))
    onCommand?(command)
  }

  /// Les prochains titres ; vide referme la colonne.
  func apply(queue newQueue: [QueueItem]) {
    let previousQueue = queue
    let visible = !newQueue.isEmpty
    let animateWidth =
      window != nil && !isHiddenOrHasHiddenAncestor
      && OverlayAnimation.allowsMotion && previousQueue.isEmpty != newQueue.isEmpty
    let playerViews: [NSView] = [
      titleLabel, artistLabel, visualizer, remainingLabel, progress, volumeIcon, volumeSlider,
    ]
    let geometry =
      animateWidth
      ? playerViews.compactMap { view -> (CALayer, CGPoint, CGRect)? in
        guard let layer = view.layer else { return nil }
        let current = layer.presentation() ?? layer
        return (layer, current.position, current.bounds)
      } : []
    queue = newQueue
    if !visible {
      dismissQueueView(queueHeader)
      dismissQueueView(queueDivider)
    } else if previousQueue.isEmpty {
      for view in [queueHeader, queueDivider] as [NSView] {
        cancelQueueExit(view)
        view.wantsLayer = true
        view.layer?.springReveal(x: 8, y: 0)
      }
    }
    queueHeader.isHidden = !visible
    queueDivider.isHidden = !visible
    for (index, view) in queueViews.enumerated() {
      if index >= newQueue.count { dismissQueueView(view) }
      view.isHidden = index >= newQueue.count
      if index < newQueue.count {
        cancelQueueExit(view)
        view.apply(newQueue[index])
        if !previousQueue.indices.contains(index) || previousQueue[index] != newQueue[index] {
          view.layer?.springReveal(x: 8, y: 0)
        }
      }
    }
    needsLayout = true
    if animateWidth {
      layoutSubtreeIfNeeded()
      for (layer, position, bounds) in geometry {
        layer.springAnimate(keyPath: "position", to: layer.position, from: position)
        layer.springAnimate(keyPath: "bounds", to: layer.bounds, from: bounds)
      }
    }
  }

  private func cancelQueueExit(_ view: NSView) {
    outgoingQueueLayers.removeValue(forKey: ObjectIdentifier(view))?.removeFromSuperlayer()
  }

  /// Garde une image sans interaction pendant que la colonne libère sa place.
  private func dismissQueueView(_ view: NSView) {
    guard OverlayAnimation.allowsMotion, !view.isHidden, window != nil,
      !isHiddenOrHasHiddenAncestor,
      let layer, !view.bounds.isEmpty,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let image = bitmap.cgImage else { return }

    let id = ObjectIdentifier(view)
    cancelQueueExit(view)
    let outgoing = CALayer()
    outgoingQueueLayers[id] = outgoing
    let displayed = view.layer?.presentation()
    outgoing.frame = displayed?.frame ?? view.frame
    outgoing.opacity = displayed?.opacity ?? 1
    outgoing.contents = image
    layer.addSublayer(outgoing)
    outgoing.springAnimate(keyPath: "transform.translation.x", to: CGFloat(8))
    outgoing.springAnimate(keyPath: "opacity", to: Float(0)) { [weak self, weak outgoing] in
      guard let self, let outgoing, outgoingQueueLayers[id] === outgoing else { return }
      outgoingQueueLayers.removeValue(forKey: id)?.removeFromSuperlayer()
    }
  }

  /// Relit le volume du système — à chaque dépliage, il a pu changer ailleurs.
  func refreshVolume() {
    volumeSlider.setValue(Double(SystemVolumeService.shared.getVolume()))
  }

  /// Pendant le glissé, les temps montrent la position visée, pas celle du lecteur.
  private func previewScrub(_ value: Double) {
    guard let duration = state?.duration, duration > 0 else { return }
    let target = value * duration
    elapsedLabel.stringValue = NowPlayingClock.format(target)
    remainingLabel.stringValue = NowPlayingClock.formatRemaining(duration - target)
  }

  /// Au relâchement : la position est envoyée au lecteur, et la vue la prend tout de suite pour
  /// acquise — le lecteur ne la renvoie qu'avec retard, et la barre reculerait entre-temps.
  private func commitScrub(_ value: Double) {
    guard var current = state, let duration = current.duration, duration > 0 else {
      updateProgress()
      return
    }
    let target = value * duration
    current.elapsed = target
    current.timestamp = .now
    state = current
    onSeek?(target)
    updateProgress()
  }

  private func updateProgress() {
    // Le doigt est sur la barre : on ne la lui reprend pas.
    guard !progress.isDragging else { return }
    guard let state, let duration = state.duration, duration > 0, let position = state.position()
    else {
      progress.setValue(0)
      elapsedLabel.stringValue = ""
      remainingLabel.stringValue = ""
      return
    }
    progress.setValue(position / duration)
    let elapsed = NowPlayingClock.format(position)
    let remaining = NowPlayingClock.formatRemaining(duration - position)
    // La largeur des temps suit leur texte : un passage à `h:mm:ss` relance la mise en page.
    let widthChanged =
      elapsed.count != elapsedLabel.stringValue.count
      || remaining.count != remainingLabel.stringValue.count
    elapsedLabel.stringValue = elapsed
    remainingLabel.stringValue = remaining
    if widthChanged { needsLayout = true }
  }

  /// Largeur commune aux deux temps : celle du plus long texte affiché, jamais moins que la
  /// largeur d'un `m:ss`. Chiffres à chasse fixe, donc elle ne bouge pas à chaque seconde.
  private var timeWidth: CGFloat {
    let widest = max(
      elapsedLabel.intrinsicContentSize.width, remainingLabel.intrinsicContentSize.width)
    return max(minimumTimeWidth, ceil(widest))
  }

  /// Cadres de la pochette et du visualiseur, dans le repère de la vue : un bout du trajet vers
  /// les ailes de l'encoche repliée (voir `NotchPanelContentView`).
  var artworkFrame: NSRect { artworkView.frame }
  var visualizerFrame: NSRect { visualizer.frame }

  /// Cache pochette et visualiseur pendant que leurs doublures font le trajet.
  func setSharedElementsHidden(_ hidden: Bool) {
    artworkView.isHidden = hidden
    visualizer.isHidden = hidden
  }

  // MARK: - Balayage de piste

  /// Zone qui réagit au balayage : la pochette et le bloc titre/artiste. Ailleurs (commandes,
  /// barre, volume), le balayage à deux doigts garde son sens d'origine, le changement
  /// d'onglet.
  private var swipeZone: NSRect {
    artworkView.frame.union(titleLabel.frame).union(artistLabel.frame)
  }

  private var swipeViews: [NSView] { [artworkView, titleLabel, artistLabel] }

  override func scrollWheel(with event: NSEvent) {
    let inZone = swipeZone.contains(convert(event.locationInWindow, from: nil))
    guard state != nil, event.hasPreciseScrollingDeltas, !event.phase.isEmpty,
      trackSwipe.isSwiping || inZone
    else {
      super.scrollWheel(with: event)
      return
    }
    if event.phase.contains(.began) {
      trackSwipe.cancel()
      swipeCrossedCommit = false
    }
    if event.phase.contains(.cancelled) {
      trackSwipe.cancel()
      settleTrackSwipe(direction: nil)
      return
    }

    if trackSwipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) {
      followTrackSwipe()
    } else if !trackSwipe.isSwiping {
      super.scrollWheel(with: event)
    }
    if event.phase.contains(.ended) {
      settleTrackSwipe(direction: trackSwipe.end())
    }
  }

  /// Pochette et textes suivent les doigts, un peu retenus, et pâlissent à mesure qu'ils
  /// partent. Un tic se fait sentir une fois, au franchissement du seuil : c'est le moment
  /// où lâcher change de piste.
  private func followTrackSwipe() {
    let shift = trackSwipe.offset * 0.6
    let alpha = Float(max(0.4, 1 - abs(shift) / 160))
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for view in swipeViews {
      view.layer?.removeAnimation(forKey: "transform.translation.x")
      view.layer?.transform = CATransform3DMakeTranslation(shift, 0, 0)
      view.layer?.opacity = alpha
    }
    CATransaction.commit()

    let crossed = abs(trackSwipe.offset) >= TabSwipeTracker.commitThreshold
    if crossed != swipeCrossedCommit {
      swipeCrossedCommit = crossed
      if crossed { swipeFeedback.tickCrossed() }
    }
  }

  private func settleTrackSwipe(direction: TabSwipeTracker.Direction?) {
    swipeCrossedCommit = false
    for view in swipeViews {
      guard let layer = view.layer else { continue }
      let hadOffset = !CATransform3DIsIdentity(layer.transform)
      layer.transform = CATransform3DIdentity
      layer.opacity = 1
      if hadOffset, OverlayAnimation.allowsMotion {
        layer.springAnimate(keyPath: "transform.translation.x", to: 0)
      }
    }
    switch direction {
    case .next: skip(.nextTrack)
    case .previous: skip(.previousTrack)
    case nil: break
    }
  }

  override func layout() {
    super.layout()
    // Pochette pleine hauteur à gauche. À droite, de haut en bas : titre et artiste, progression,
    // puis commandes à gauche et volume à droite, tous alignés sur le bord de la pochette.
    let artSize = bounds.height
    artworkView.frame = NSRect(x: 0, y: 0, width: artSize, height: artSize)

    // Le lecteur tient dans `playerWidth` ; la colonne de droite prend le reste.
    let hasQueue = !queue.isEmpty
    let playerWidth = hasQueue ? (bounds.width * playerShare).rounded() : bounds.width
    layoutQueueColumn(playerWidth: playerWidth, headerY: 0, artSize: artSize)

    let textX = artSize + 14
    let titleHeight: CGFloat = 22
    let artistHeight: CGFloat = 20
    let hasArtist = !artistLabel.stringValue.isEmpty

    // Titre et artiste sont collés au haut de la colonne ; le visualiseur reste sur la ligne du titre.
    let titleY = bounds.height - titleHeight
    let artistY = titleY - artistHeight
    let vizSize = visualizer.intrinsicContentSize
    visualizer.frame = NSRect(
      x: playerWidth - vizSize.width, y: titleY + (titleHeight - vizSize.height) / 2,
      width: vizSize.width, height: vizSize.height)
    let textWidth = max(0, visualizer.frame.minX - 10 - textX)
    titleLabel.frame = NSRect(
      x: textX - labelPadding, y: titleY, width: textWidth, height: titleHeight)
    titleMarquee.frame = titleLabel.frame
    artistLabel.frame = NSRect(
      x: textX - labelPadding, y: artistY, width: max(0, playerWidth - textX), height: artistHeight)

    // Les commandes occupent le bas ; la progression se centre dans l'espace restant au-dessus.
    let controlsY: CGFloat = 0
    let gapBottom = controlsY + controlsHeight
    let gapTop = hasArtist ? artistY : titleY
    let progressY = max(
      gapBottom + rowGap, gapBottom + (gapTop - gapBottom - progressHeight) / 2)

    // Temps écoulé et restant sont calés sur les bords de la colonne et du volume.
    elapsedLabel.frame = NSRect(
      x: textX - labelPadding, y: progressY - 1, width: timeWidth, height: progressHeight + 2)
    remainingLabel.frame = NSRect(
      x: playerWidth - timeWidth + labelPadding, y: progressY - 1, width: timeWidth,
      height: progressHeight + 2)
    progress.frame = NSRect(
      x: textX + timeWidth + 6 - labelPadding, y: progressY,
      width: max(0, playerWidth - textX - 2 * (timeWidth + 6 - labelPadding)),
      height: progressHeight)

    // Les trois commandes commencent sous le titre ; le volume colle au bord droit et se réduit
    // si la colonne est trop étroite pour tout afficher.
    let buttons = [previousButton, playPauseButton, nextButton]
    let groupWidth = buttonPitch * CGFloat(buttons.count)
    let groupX = textX - labelPadding - (buttonPitch - 20) / 2
    let groupEnd = groupX + groupWidth
    let controlsMidY = controlsY + (controlsHeight - 16) / 2
    let volume = min(
      hasQueue ? volumeWidth * 0.6 : volumeWidth, max(0, playerWidth - groupEnd - 38))
    volumeSlider.frame = NSRect(x: playerWidth - volume, y: controlsMidY, width: volume, height: 16)
    volumeIcon.frame = NSRect(
      x: volumeSlider.frame.minX - 26, y: controlsMidY, width: 18, height: 16)

    for (index, button) in buttons.enumerated() {
      button.frame = NSRect(
        x: groupX + CGFloat(index) * buttonPitch, y: controlsY, width: buttonPitch,
        height: controlsHeight)
    }
  }
}

extension NowPlayingRowView {

  /// Filet, titre de colonne et trois lignes, alignés sur le haut de la pochette.
  fileprivate func layoutQueueColumn(playerWidth: CGFloat, headerY: CGFloat, artSize: CGFloat) {
    let columnX = playerWidth + queueGap
    let columnWidth = max(0, bounds.width - columnX)
    let top = headerY + artSize

    queueDivider.frame = NSRect(
      x: playerWidth + queueGap / 2, y: 4, width: 1, height: max(0, bounds.height - 8))
    queueHeader.frame = NSRect(x: columnX - 2, y: top - 18, width: columnWidth, height: 18)

    let rowHeight: CGFloat = 32
    let firstRowTop = top - 24
    for (index, view) in queueViews.enumerated() {
      view.frame = NSRect(
        x: columnX, y: firstRowTop - CGFloat(index + 1) * rowHeight - CGFloat(index) * 2,
        width: columnWidth, height: rowHeight)
    }
  }
}

/// Une ligne de la file : petite pochette, titre, artiste.
final class QueueItemView: NSView {

  private let artworkView = ArtworkView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let artistLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    artworkView.showsSourceBadge = false
    artworkView.cornerRadius = 5
    addSubview(artworkView)

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .white
    artistLabel.font = .systemFont(ofSize: 12)
    artistLabel.textColor = .white.withAlphaComponent(0.5)
    for label in [titleLabel, artistLabel] {
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ item: QueueItem) {
    titleLabel.stringValue = item.title
    artistLabel.stringValue = item.artist
    artworkView.setArtwork(item.artwork)
  }

  override func layout() {
    super.layout()
    let art = bounds.height - 4
    artworkView.frame = NSRect(x: 0, y: 2, width: art, height: art)
    let textX = art + 10
    let width = max(0, bounds.width - textX)
    titleLabel.frame = NSRect(x: textX - 2, y: bounds.midY, width: width + 2, height: 16)
    artistLabel.frame = NSRect(x: textX - 2, y: bounds.midY - 15, width: width + 2, height: 15)
  }
}

/// Bouton-glyphe qui s'éclaircit au survol, sur le modèle de `NotchGearButtonView`.
final class NowPlayingControlButton: NSView {

  var onClick: (() -> Void)?

  private let iconView = NSImageView()
  private let pointSize: CGFloat
  private var currentSymbol: String?
  private let hoverLayer = CALayer()
  private var isHovered = false {
    didSet {
      iconView.contentTintColor = .white.withAlphaComponent(isHovered ? 1 : 0.9)
      updateBackground()
    }
  }
  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      updateBackground()
      layer?.springScale(to: isPressed ? 0.88 : 1)
    }
  }
  private var trackingArea: NSTrackingArea?

  init(symbol: String, size: CGFloat) {
    pointSize = size
    super.init(frame: .zero)
    wantsLayer = true
    hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(0).cgColor
    layer?.insertSublayer(hoverLayer, at: 0)
    setAccessibilityRole(.button)
    iconView.imageScaling = .scaleProportionallyDown
    iconView.contentTintColor = .white.withAlphaComponent(0.9)
    addSubview(iconView)
    setSymbol(symbol)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSymbol(_ name: String) {
    guard name != currentSymbol else { return }
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return }

    if currentSymbol != nil, window != nil, OverlayAnimation.allowsMotion {
      iconView.setSymbolImage(image, contentTransition: .replace)
    } else {
      iconView.image = image
    }
    currentSymbol = name
  }

  /// Pastille claire derrière le glyphe : plus franche à l'appui qu'au survol.
  private func updateBackground() {
    let alpha: CGFloat = isPressed ? 0.2 : (isHovered ? 0.1 : 0)
    CATransaction.begin()
    if OverlayAnimation.allowsMotion {
      CATransaction.setAnimationDuration(0.12)
    } else {
      CATransaction.setDisableActions(true)
    }
    hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    iconView.frame = bounds
    let side = min(bounds.width, bounds.height)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    hoverLayer.frame = NSRect(
      x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    hoverLayer.cornerRadius = side / 2
    CATransaction.commit()
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
