import AppKit

/// Balayage horizontal d'un bloc de l'onglet Usage (trackpad à deux doigts ou glisser à la
/// souris) : le bloc suit le doigt 1:1, résiste au bord quand il n'y a rien au-delà, et au
/// relâché on projette où le geste allait (même physique que la grille du mois) pour décider s'il
/// change de page. Un geste surtout vertical, ou une molette de souris, n'est pas pour lui : la
/// vue le relaie au panneau.
///
/// Les vues lui passent leurs événements ; il appelle `onTrack` pendant le geste puis `onCommit`
/// ou `onCancel` au relâché.
final class NotchUsageSwipePager {

  /// Sens du doigt : `+1` vers la droite (page d'avant), `-1` vers la gauche (page d'après).
  typealias Page = Int

  /// Largeur de référence d'une page, pour la projection et la résistance.
  var width: () -> CGFloat = { 1 }
  /// Dit si on peut aller dans ce sens ; sinon le bloc résiste et revient.
  var allows: (Page) -> Bool = { _ in true }
  /// Translation actuelle du bloc, pour rattraper une animation en vol au début d'un geste.
  var presentedOffset: () -> CGFloat = { 0 }
  /// Le doigt déplace le bloc de `offset` (déjà amorti au bord).
  var onTrack: (CGFloat) -> Void = { _ in }
  /// Le geste change de page : `from` est la translation au relâché, `velocity` en pt/s.
  var onCommit: (Page, _ from: CGFloat, _ velocity: CGFloat) -> Void = { _, _, _ in }
  /// Le geste revient à sa place.
  var onCancel: (_ from: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }

  private var tracker = TabSwipeTracker()
  private var grabOffset: CGFloat = 0
  private var samples: [(time: TimeInterval, offset: CGFloat)] = []
  private var ownsScrollGesture = false
  /// L'inertie qui suit un balayage du bloc lui appartient jusqu'à sa fin.
  private var ownsMomentum = false
  private var isMouseDown = false

  var isSwiping: Bool { tracker.isSwiping }

  // MARK: - Trackpad

  /// Renvoie `true` quand l'événement appartient au bloc (il ne faut pas le relayer).
  func scrollWheel(_ event: NSEvent) -> Bool {
    // Molette de souris, ou défilement sans phase : jamais pour le bloc.
    guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty || !event.momentumPhase.isEmpty
    else { return false }

    // L'inertie qui suit un balayage du bloc lui appartient : la relayer ferait balayer autre
    // chose après coup.
    if !event.momentumPhase.isEmpty {
      let owned = ownsMomentum
      if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
        ownsMomentum = false
      }
      return owned
    }

    if event.phase.contains(.began) {
      ownsScrollGesture = false
      ownsMomentum = false
      begin()
      ownsScrollGesture = move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp)
      return ownsScrollGesture
    }
    if event.phase.contains(.cancelled) {
      let owned = ownsScrollGesture
      ownsScrollGesture = false
      let from = currentOffset
      tracker.cancel()
      if owned { onCancel(from, 0) }
      return owned
    }

    if move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp) {
      ownsScrollGesture = true
    }
    let owned = ownsScrollGesture
    if event.phase.contains(.ended) {
      end(at: event.timestamp)
      ownsMomentum = owned
      ownsScrollGesture = false
    }
    return owned
  }

  // MARK: - Souris

  func mouseDown(_ event: NSEvent) {
    isMouseDown = true
    begin()
  }

  func mouseDragged(_ event: NSEvent) {
    guard isMouseDown else { return }
    _ = move(dx: event.deltaX, dy: -event.deltaY, at: event.timestamp)
  }

  /// Renvoie `true` quand le geste était un balayage : ce n'était alors pas un clic.
  @discardableResult
  func mouseUp(_ event: NSEvent) -> Bool {
    guard isMouseDown else { return false }
    isMouseDown = false
    let wasSwiping = tracker.isSwiping
    end(at: event.timestamp)
    return wasSwiping
  }

  /// Abandonne le geste en cours (panneau qui se replie).
  func cancel() {
    guard tracker.isSwiping || grabOffset != 0 else {
      tracker.cancel()
      return
    }
    let from = currentOffset
    tracker.cancel()
    ownsScrollGesture = false
    isMouseDown = false
    onCancel(from, 0)
  }

  // MARK: - Interne

  private var rawOffset: CGFloat { grabOffset + tracker.offset }
  private var currentOffset: CGFloat { dampened(rawOffset) }

  private func begin() {
    tracker.cancel()
    grabOffset = OverlayAnimation.allowsMotion ? presentedOffset() : 0
    samples = []
  }

  private func move(dx: CGFloat, dy: CGFloat, at time: TimeInterval) -> Bool {
    guard tracker.move(dx: dx, dy: dy) else { return false }
    let raw = rawOffset
    samples.append((time, raw))
    samples.removeAll { time - $0.time > 0.1 }
    if OverlayAnimation.allowsMotion { onTrack(dampened(raw)) }
    return true
  }

  private func end(at time: TimeInterval) {
    let wasSwiping = tracker.isSwiping
    let raw = rawOffset
    tracker.cancel()
    defer { grabOffset = 0 }
    guard wasSwiping else {
      if grabOffset != 0 { onCancel(grabOffset, 0) }
      return
    }
    let velocity = MonthGridView.releaseVelocity(samples: samples, at: time)
    // `settlePage` rend -1 (page d'après), 0 ou 1 (page d'avant) : le même sens que le doigt.
    var page = Int(MonthGridView.settlePage(offset: raw, velocity: velocity, width: width()))
    if page != 0, !allows(page) { page = 0 }
    if page != 0 {
      onCommit(page, dampened(raw), velocity)
    } else {
      onCancel(dampened(raw), velocity)
    }
  }

  /// Résistance progressive : libre dans un sens permis, bien plus dure dans l'autre, et dans les
  /// deux cas jamais au-delà d'une page.
  private func dampened(_ x: CGFloat) -> CGFloat {
    let page = max(1, width())
    let direction = x >= 0 ? 1 : -1
    let limit = allows(direction) ? page : page * 0.18
    let constant: CGFloat = 0.55
    let magnitude = abs(x)
    if allows(direction), magnitude <= limit { return x }
    let over = allows(direction) ? magnitude - limit : magnitude
    let damped = (over * limit * constant) / (limit + constant * over)
    let base = allows(direction) ? limit : 0
    return CGFloat(direction) * (base + damped)
  }
}

// MARK: - Transition d'un bloc

extension CALayer {

  private static let swipeKeys = ["transform.translation.x", "opacity", "swipeOut"]

  /// Pose le bloc à `x` sans animation, plein opacité : le doigt le tient.
  func trackSwipe(to x: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    Self.swipeKeys.forEach { removeAnimation(forKey: $0) }
    setValue(x, forKeyPath: "transform.translation.x")
    opacity = 1
    CATransaction.commit()
  }

  /// Translation à l'écran, rattrapée au vol.
  var presentedTranslationX: CGFloat {
    (presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat)
      ?? (value(forKeyPath: "transform.translation.x") as? CGFloat) ?? 0
  }

  /// Le bloc revient à sa place au ressort, en gardant la vitesse du doigt.
  func settleSwipe(from x: CGFloat, velocity: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    removeAnimation(forKey: "swipeOut")
    opacity = 1
    CATransaction.commit()
    guard OverlayAnimation.allowsMotion else {
      trackSwipe(to: 0)
      return
    }
    let relative = abs(x) > 0.5 ? velocity / -x : 0
    springAnimate(
      keyPath: "transform.translation.x", to: 0, from: x, preset: .snappy, velocity: relative)
  }

  /// Le bloc change de contenu dans le sens du geste : l'ancien part de ce côté en s'effaçant,
  /// `swap` pose le nouveau, qui arrive du côté opposé au ressort. Sans mouvement permis, le
  /// contenu change simplement.
  func commitSwipe(page: Int, from x: CGFloat, swap: @escaping () -> Void) {
    guard OverlayAnimation.allowsMotion else {
      trackSwipe(to: 0)
      swap()
      return
    }
    let travel = CGFloat(page) * 72

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      // Un doigt qui reprend le bloc pendant la sortie retire l'animation, ce qui la termine aussi :
      // sans cette garde, le contenu changerait sous le doigt.
      guard let self, self.animation(forKey: "swipeOut") != nil else { return }
      // Le nouveau contenu entre du côté d'où le doigt vient, comme un onglet qu'on tourne.
      swap()
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      self.removeAnimation(forKey: "swipeOut")
      self.setValue(-travel * 0.6, forKeyPath: "transform.translation.x")
      self.opacity = 0
      CATransaction.commit()
      self.springAnimate(
        keyPath: "transform.translation.x", to: 0, from: -travel * 0.6, preset: .snappy)
      self.springAnimate(keyPath: "opacity", to: 1, from: 0, preset: .gentle)
    }
    let slide = CABasicAnimation(keyPath: "transform.translation.x")
    slide.fromValue = x
    slide.toValue = travel
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    let group = CAAnimationGroup()
    group.animations = [slide, fade]
    group.duration = 0.14
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    group.fillMode = .forwards
    group.isRemovedOnCompletion = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    setValue(travel, forKeyPath: "transform.translation.x")
    opacity = 0
    CATransaction.commit()
    add(group, forKey: "swipeOut")
    CATransaction.commit()
  }
}
