import Observation
import SwiftUI

/// Cadres que l'AppKit relit : la pochette et le visualiseur font un bout du trajet vers les
/// ailes de l'encoche (voir `NotchPanelContentView`), la carte du titre est la zone de balayage.
/// Repère SwiftUI, origine en haut à gauche.
nonisolated struct PlayerFrames: Equatable {
  var artwork: CGRect = .zero
  var visualizer: CGRect = .zero
  var card: CGRect = .zero
}

nonisolated enum PlayerFramesKey: PreferenceKey {
  static let defaultValue = PlayerFrames()

  static func reduce(value: inout PlayerFrames, nextValue: () -> PlayerFrames) {
    let next = nextValue()
    if !next.artwork.isEmpty { value.artwork = next.artwork }
    if !next.visualizer.isEmpty { value.visualizer = next.visualizer }
    if !next.card.isEmpty { value.card = next.card }
  }
}

/// État du lecteur SwiftUI : `NowPlayingRowView` le remplit, la vue le lit.
@Observable
final class NowPlayingPlayerModel {

  var state: NowPlayingState?
  var queue: [QueueItem] = []
  /// Volume du système, de 0 à 1.
  var volume: Double = 0
  /// Décalage de la carte pendant un balayage, déjà retenu (voir `follow(rawOffset:)`).
  var swipeOffset: CGFloat = 0
  /// Vrai pendant que les doublures de pochette et de visualiseur font le trajet des ailes.
  var sharedHidden = false
  /// Position visée pendant un glissé sur la barre de progression, de 0 à 1.
  var scrubFraction: Double?
  /// Vrai quand le panneau des ambiances a pris la place du lecteur.
  var showsAmbient = false
  /// Ambiance qui joue, `nil` quand aucune.
  var activeAmbient: AmbientSound?

  @ObservationIgnored var frames = PlayerFrames()
  @ObservationIgnored var onCommand: ((NowPlayingCommand) -> Void)?
  @ObservationIgnored var onSeek: ((TimeInterval) -> Void)?
  @ObservationIgnored let swipeFeedback: OverlayFeedback = SystemOverlayFeedback(playsSound: false)
  @ObservationIgnored private var swipeCrossedCommit = false
  @ObservationIgnored private let ambientPlayer = AmbientSoundPlayer()
  /// Sens du dernier saut demandé (+1 suivant, -1 précédent) et jusqu'à quand il vaut : le
  /// titre suivant arrive du côté d'où il vient.
  @ObservationIgnored private var pendingSkip: (direction: CGFloat, until: Date)?

  var isPlaying: Bool { state?.isPlaying ?? false }

  /// Change quand le morceau change : la carte se rejoue alors avec sa transition.
  var trackIdentity: String {
    guard let state else { return "" }
    return "\(state.bundleIdentifier)|\(state.title)|\(state.artist)|\(state.album)"
  }

  var skipDirection: CGFloat {
    if let pendingSkip, pendingSkip.until > .now { return pendingSkip.direction }
    return 1
  }

  func togglePlayPause() { onCommand?(.togglePlayPause) }

  /// Une tuile choisie joue ; choisie à nouveau, elle s'arrête.
  func toggleAmbient(_ sound: AmbientSound) {
    if activeAmbient == sound {
      ambientPlayer.stop()
      activeAmbient = nil
    } else {
      activeAmbient = sound
      ambientPlayer.play(sound)
    }
  }

  /// Garde le dernier cadre connu de chaque élément : quand le panneau des ambiances a chassé
  /// le lecteur, la pochette n'est plus mesurée, mais le trajet vers les ailes en a besoin.
  func mergeFrames(_ new: PlayerFrames) {
    if !new.artwork.isEmpty { frames.artwork = new.artwork }
    if !new.visualizer.isEmpty { frames.visualizer = new.visualizer }
    if !new.card.isEmpty { frames.card = new.card }
  }

  /// Précédent ou suivant, depuis un bouton ou un balayage.
  func skip(_ command: NowPlayingCommand) {
    guard command == .nextTrack || command == .previousTrack else { return }
    pendingSkip = (command == .nextTrack ? 1 : -1, Date.now.addingTimeInterval(3))
    onCommand?(command)
  }

  func setVolume(_ value: Double) {
    let clamped = min(1, max(0, value))
    guard clamped != volume else { return }
    volume = clamped
    SystemVolumeService.shared.setVolume(Float(clamped))
  }

  /// Au relâchement : la position part vers le lecteur, et la vue la prend tout de suite pour
  /// acquise — le lecteur ne la renvoie qu'avec retard, et la barre reculerait entre-temps.
  func commitScrub(_ fraction: Double) {
    defer { scrubFraction = nil }
    guard var current = state, let duration = current.duration, duration > 0 else { return }
    let target = min(1, max(0, fraction)) * duration
    current.elapsed = target
    current.timestamp = .now
    state = current
    onSeek?(target)
  }

  // MARK: - Balayage de piste

  /// La carte suit les doigts, un peu retenue. Un tic se fait sentir une fois, au franchissement
  /// du seuil : c'est le moment où lâcher change de piste.
  func follow(rawOffset: CGFloat) {
    swipeOffset = rawOffset * 0.6
    let crossed = abs(rawOffset) >= TabSwipeTracker.commitThreshold
    if crossed != swipeCrossedCommit {
      swipeCrossedCommit = crossed
      if crossed { swipeFeedback.tickCrossed() }
    }
  }

  func settleSwipe(_ direction: TabSwipeTracker.Direction?) {
    swipeCrossedCommit = false
    if OverlayAnimation.allowsMotion {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { swipeOffset = 0 }
    } else {
      swipeOffset = 0
    }
    switch direction {
    case .next: skip(.nextTrack)
    case .previous: skip(.previousTrack)
    case nil: break
    }
  }
}
