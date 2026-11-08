import Foundation

/// Tient la colonne « Playing Next » à jour : relit la file de la bonne source quand le morceau
/// change, quand la lecture reprend et quand le panneau se déplie, et la vide dès que plus rien
/// n'est connu. Pousse le résultat par `onItemsChanged` ; ne tient aucun contrôleur.
final class PlayingNextViewModel {

  var onItemsChanged: (([QueueItem]) -> Void)?

  private let providers: [any PlayingNextProviding]
  private let limit: Int
  private let settleDelay: Duration
  private let minimumRefreshInterval: TimeInterval

  private var state: NowPlayingState?
  private var trackKey: String?
  private var fetchTask: Task<Void, Never>?
  private var lastFetch: Date = .distantPast
  private(set) var items: [QueueItem] = []

  /// `settleDelay` laisse la source se mettre à jour après un changement de morceau : Spotify et
  /// Musique renvoient sinon encore la file d'avant.
  init(
    providers: [any PlayingNextProviding], limit: Int = 3,
    settleDelay: Duration = .milliseconds(400),
    minimumRefreshInterval: TimeInterval = 5
  ) {
    self.providers = providers
    self.limit = limit
    self.settleDelay = settleDelay
    self.minimumRefreshInterval = minimumRefreshInterval
  }

  /// Appelé à chaque changement du lecteur (dernier morceau connu, en pause ou non).
  func update(for newState: NowPlayingState?) {
    let previous = state
    state = newState

    guard let newState else {
      reset()
      return
    }

    let key = newState.bundleIdentifier + "\u{1F}" + newState.title + "\u{1F}" + newState.artist
    if key != trackKey {
      trackKey = key
      publish([])
      fetch(settling: true)
    } else if previous?.isPlaying == false, newState.isPlaying {
      fetch(settling: false)
    }
  }

  /// Relit la file sans changement de morceau — le panneau vient de se déplier. Au plus une fois
  /// par `minimumRefreshInterval`.
  func refresh() {
    guard state != nil, Date.now.timeIntervalSince(lastFetch) >= minimumRefreshInterval else {
      return
    }
    fetch(settling: false)
  }

  private func reset() {
    fetchTask?.cancel()
    fetchTask = nil
    trackKey = nil
    publish([])
  }

  private func fetch(settling: Bool) {
    fetchTask?.cancel()
    guard let state,
      let provider = providers.first(where: {
        $0.supports(bundleIdentifier: state.bundleIdentifier)
      })
    else {
      publish([])
      return
    }
    let key = trackKey
    fetchTask = Task { [weak self, limit, settleDelay] in
      if settling { try? await Task.sleep(for: settleDelay) }
      guard !Task.isCancelled else { return }
      let upcoming = await provider.upcoming(limit: limit)
      guard !Task.isCancelled, let self, trackKey == key else { return }
      lastFetch = .now
      publish(upcoming)
    }
  }

  private func publish(_ newItems: [QueueItem]) {
    guard newItems != items else { return }
    items = newItems
    onItemsChanged?(newItems)
  }
}
