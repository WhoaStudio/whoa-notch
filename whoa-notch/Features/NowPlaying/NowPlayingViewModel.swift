import Foundation

/// Décide ce que montre la vue « Now Playing ». Les ailes de l'encoche sont visibles tant que
/// quelque chose joue, puis encore `hideDelay` après l'arrêt ou la pause, pour qu'une pause depuis
/// l'encoche ne les fasse pas disparaître sous le doigt : c'est `onStateChanged` (`nil` = masquer).
/// Le lecteur de l'onglet Global, lui, reste : `onPlayerChanged` donne toujours le dernier
/// morceau connu, en pause une fois la lecture finie, ou `nil` si rien n'a encore joué. Ne tient
/// aucun contrôleur.
final class NowPlayingViewModel {

  var onStateChanged: ((NowPlayingState?) -> Void)?
  var onPlayerChanged: ((NowPlayingState?) -> Void)?

  private let provider: NowPlayingProviding
  private let hideDelay: Duration
  private var hideTask: Task<Void, Never>?
  private(set) var state: NowPlayingState?
  private(set) var lastTrack: NowPlayingState?

  init(provider: NowPlayingProviding, hideDelay: Duration = .seconds(5)) {
    self.provider = provider
    self.hideDelay = hideDelay
  }

  func activate() {
    provider.onUpdate = { [weak self] update in self?.receive(update) }
    provider.start()
  }

  func send(_ command: NowPlayingCommand) {
    provider.send(command)
  }

  func seek(to seconds: TimeInterval) {
    provider.seek(to: seconds)
  }

  func receive(_ update: NowPlayingState?) {
    // Plus aucune session : le lecteur garde le dernier morceau, à l'arrêt.
    if let update {
      lastTrack = update
      onPlayerChanged?(update)
    } else if var last = lastTrack, last.isPlaying {
      last.isPlaying = false
      lastTrack = last
      onPlayerChanged?(last)
    }

    if let update, update.isPlaying {
      hideTask?.cancel()
      hideTask = nil
      publish(update)
      return
    }

    // En pause on garde le titre à l'écran (visualiseur arrêté) ; sans plus aucune session
    // il n'y a rien de neuf à montrer, la dernière image reste jusqu'au masquage.
    if let update { publish(update) }
    scheduleHide()
  }

  private func publish(_ update: NowPlayingState) {
    guard update != state else { return }
    state = update
    onStateChanged?(update)
  }

  private func scheduleHide() {
    guard hideTask == nil, state != nil else { return }
    hideTask = Task { [weak self, hideDelay] in
      try? await Task.sleep(for: hideDelay)
      guard !Task.isCancelled, let self else { return }
      hideTask = nil
      state = nil
      onStateChanged?(nil)
    }
  }
}
