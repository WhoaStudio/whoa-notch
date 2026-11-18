import AppKit
import SwiftUI

/// Lecteur de l'onglet Global, déplié. L'interface est en SwiftUI (`NowPlayingPlayerView`) ; cette
/// vue AppKit en garde la façade pour `NotchPanelContentView` : commandes, état, file, volume,
/// cadres de la pochette et du visualiseur, et balayage de piste à deux doigts.
final class NowPlayingRowView: NSView {

  var onCommand: ((NowPlayingCommand) -> Void)? {
    didSet { model.onCommand = onCommand }
  }
  /// Position choisie en glissant sur la barre de progression, en secondes.
  var onSeek: ((TimeInterval) -> Void)? {
    didSet { model.onSeek = onSeek }
  }

  private let model: NowPlayingPlayerModel
  private let host: NSHostingView<NowPlayingPlayerView>

  /// Balayage de piste : même suiveur que le balayage d'onglets, pour que les deux gestes
  /// partagent seuils et abandon d'un geste vertical.
  private var trackSwipe = TabSwipeTracker()

  override init(frame frameRect: NSRect) {
    let model = NowPlayingPlayerModel()
    let host = PassthroughHostingView(rootView: NowPlayingPlayerView(model: model))
    // Le panneau pose les cadres lui-même : la vue ne doit rien imposer à la fenêtre.
    host.sizingOptions = []
    self.model = model
    self.host = host
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(host)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ state: NowPlayingState?) {
    model.state = state
  }

  /// Les prochains titres ; vide referme la colonne.
  func apply(queue newQueue: [QueueItem]) {
    model.queue = newQueue
  }

  /// Relit le volume du système — à chaque dépliage, il a pu changer ailleurs.
  func refreshVolume() {
    model.volume = Double(SystemVolumeService.shared.getVolume())
  }

  override func layout() {
    super.layout()
    // Le fond déborde du cadre de `PlayerStyle.bleed` de chaque côté ; les commandes, elles,
    // restent sur les bords du cadre.
    host.frame = bounds.insetBy(dx: -PlayerStyle.bleed, dy: 0)
  }

  // MARK: - Cadres partagés

  /// Cadres de la pochette et du visualiseur, dans le repère de la vue : un bout du trajet vers
  /// les ailes de l'encoche repliée (voir `NotchPanelContentView`).
  var artworkFrame: NSRect {
    appKitRect(model.frames.artwork, fallback: NSRect(x: 8, y: 8, width: 0, height: 0))
  }
  var visualizerFrame: NSRect {
    appKitRect(model.frames.visualizer, fallback: .zero)
  }

  /// SwiftUI compte les y depuis le haut ; la vue AppKit, depuis le bas.
  private func appKitRect(_ rect: CGRect, fallback: NSRect) -> NSRect {
    guard !rect.isEmpty else { return fallback }
    return NSRect(
      x: rect.minX - PlayerStyle.bleed, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
  }

  /// Cache pochette et visualiseur pendant que leurs doublures font le trajet.
  func setSharedElementsHidden(_ hidden: Bool) {
    model.sharedHidden = hidden
  }

  // MARK: - Balayage de piste à deux doigts

  /// Zone qui réagit au balayage : la carte du morceau. Ailleurs (commandes, volume), le
  /// balayage à deux doigts garde son sens d'origine, le changement d'onglet.
  private var swipeZone: NSRect { appKitRect(model.frames.card, fallback: .zero) }

  override func scrollWheel(with event: NSEvent) {
    let inZone = swipeZone.contains(convert(event.locationInWindow, from: nil))
    guard model.state != nil, !model.showsAmbient, event.hasPreciseScrollingDeltas, !event.phase.isEmpty,
      trackSwipe.isSwiping || inZone
    else {
      super.scrollWheel(with: event)
      return
    }
    if event.phase.contains(.began) { trackSwipe.cancel() }
    if event.phase.contains(.cancelled) {
      trackSwipe.cancel()
      model.settleSwipe(nil)
      return
    }

    if trackSwipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) {
      model.follow(rawOffset: trackSwipe.offset)
    } else if !trackSwipe.isSwiping {
      super.scrollWheel(with: event)
    }
    if event.phase.contains(.ended) {
      model.settleSwipe(trackSwipe.end())
    }
  }
}

/// Laisse la molette à la rangée : le balayage à deux doigts y est décodé (`scrollWheel`).
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
  override func scrollWheel(with event: NSEvent) {
    if let superview { superview.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
  }
}
